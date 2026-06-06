import Foundation

#if canImport(WalletCore)
import WalletCore
#endif

final class EvmTransactionService: TransactionServiceProtocol {
    private let network: WalletNetwork

    init(network: WalletNetwork) {
        self.network = network
    }

    func quote(
        draft: TransferDraft,
        asset: WalletAssetBalance,
        sourceChain: WalletChain,
        signing: WalletSigningContext
    ) async throws -> TransferQuote {
        guard network.family == .evm else { throw TransactionServiceError.unsupportedNetwork }
        guard draft.amount > 0 else { throw TransactionServiceError.invalidAmount }
        guard WalletCoreBridge.validateAddress(draft.recipient, chainID: network.rawValue) else {
            throw TransactionServiceError.invalidRecipient
        }

        let fees = try await feeComponents()
        let gasLimit: Decimal = asset.isNative ? 21_000 : 65_000
        let feeWei = gasLimit * Decimal(fees.maxFeePerGas)
        let fee = feeWei / pow10(network.decimals)
        let totalDebit = asset.isNative ? draft.amount + fee : draft.amount

        if asset.isNative && asset.balance < totalDebit {
            throw TransactionServiceError.insufficientFunds
        }

        let maxFeeGwei = Decimal(fees.maxFeePerGas) / Decimal(1_000_000_000)
        return TransferQuote(
            asset: asset,
            fee: fee,
            feeSymbol: network.feeSymbol,
            totalDebit: totalDebit,
            networkDetail: "max \(maxFeeGwei.formattedString(maxFractionDigits: 2)) gwei",
            editableFee: true
        )
    }

    func send(
        review: TransferReview,
        signing: WalletSigningContext
    ) async throws -> BroadcastReceipt {
        #if canImport(WalletCore)
        let asset = review.quote.asset
        let nonce = try await fetchNonce(address: signing.chain.address)
        let fees = try await feeComponents()
        let gasLimit: UInt64 = asset.isNative ? 21_000 : 65_000
        let keyData = try WalletCoreBridge.privateKeyData(for: signing)

        let output = try sign(
            asset: asset,
            review: review,
            nonce: nonce,
            maxFeePerGas: fees.maxFeePerGas,
            priorityFeePerGas: fees.priorityFeePerGas,
            gasLimit: gasLimit,
            keyData: keyData
        )

        let txHash = try await broadcast(rawTransaction: output.encoded.hexString.prefixed0x)
        return BroadcastReceipt(
            chainID: network.rawValue,
            txHash: txHash,
            submittedAt: Date(),
            explorerURL: URL(string: "\(network.explorerBase)/tx/\(txHash)")
        )
        #else
        throw TransactionServiceError.signingUnavailable
        #endif
    }

    private func feeComponents() async throws -> EthereumFeeComponents {
        async let gasPrice: CoreEthereumBalanceResponse = JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "eth_gasPrice", params: []),
            url: network.rpcURL,
            responseType: CoreEthereumBalanceResponse.self
        )

        struct BlockResponse: Decodable {
            let result: BlockResult
        }
        struct BlockResult: Decodable {
            let baseFeePerGas: String?
        }

        async let block: BlockResponse = JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "eth_getBlockByNumber", params: [CoreAnyEncodable("latest"), CoreAnyEncodable(false)]),
            url: network.rpcURL,
            responseType: BlockResponse.self
        )

        async let priority: CoreEthereumBalanceResponse = JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "eth_maxPriorityFeePerGas", params: []),
            url: network.rpcURL,
            responseType: CoreEthereumBalanceResponse.self
        )

        let gas = try await gasPrice
        let blockResult = try await block
        let priorityFee = try await priority

        let baseFee = UInt64(blockResult.result.baseFeePerGas?.stripHexPrefix ?? gas.result.stripHexPrefix, radix: 16) ?? 0
        let priorityFeeValue = UInt64(priorityFee.result.stripHexPrefix, radix: 16) ?? 1_500_000_000
        let gasPriceValue = UInt64(gas.result.stripHexPrefix, radix: 16)
        let maxFee = max(baseFee * 2 + priorityFeeValue, gasPriceValue ?? priorityFeeValue)

        return EthereumFeeComponents(maxFeePerGas: maxFee, priorityFeePerGas: priorityFeeValue)
    }

    private func fetchNonce(address: String) async throws -> UInt64 {
        let response: CoreEthereumBalanceResponse = try await JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "eth_getTransactionCount", params: [CoreAnyEncodable(address), CoreAnyEncodable("pending")]),
            url: network.rpcURL,
            responseType: CoreEthereumBalanceResponse.self
        )
        return UInt64(response.result.stripHexPrefix, radix: 16) ?? 0
    }

    private func broadcast(rawTransaction: String) async throws -> String {
        let response: CoreEthereumBalanceResponse = try await JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "eth_sendRawTransaction", params: [CoreAnyEncodable(rawTransaction)]),
            url: network.rpcURL,
            responseType: CoreEthereumBalanceResponse.self
        )
        guard response.result.hasPrefix("0x") else {
            throw TransactionServiceError.broadcastFailed("\(network.displayName) transaction broadcast failed.")
        }
        return response.result
    }

    #if canImport(WalletCore)
    private func sign(
        asset: WalletAssetBalance,
        review: TransferReview,
        nonce: UInt64,
        maxFeePerGas: UInt64,
        priorityFeePerGas: UInt64,
        gasLimit: UInt64,
        keyData: Data
    ) throws -> EthereumSigningOutput {
        guard let chainID = network.evmChainID else {
            throw TransactionServiceError.unsupportedNetwork
        }

        var input = EthereumSigningInput.with {
            $0.chainID = Data.hexUInt64(chainID)
            $0.nonce = Data.hexUInt64(nonce)
            $0.gasLimit = Data.hexUInt64(gasLimit)
            $0.maxFeePerGas = Data.hexUInt64(maxFeePerGas)
            $0.maxInclusionFeePerGas = Data.hexUInt64(priorityFeePerGas)
            $0.txMode = .enveloped
            $0.privateKey = keyData
        }

        if asset.isNative {
            let transferAmount = try review.draft.amount.smallestUnit(decimals: asset.decimals)
            input.toAddress = review.draft.recipient
            input.transaction = EthereumTransaction.with {
                $0.transfer = EthereumTransaction.Transfer.with {
                    $0.amount = Data(hexString: String(transferAmount, radix: 16).leftPaddedToEvenLength) ?? Data()
                }
            }
        } else {
            guard let contract = asset.contractAddress else { throw TransactionServiceError.unsupportedAsset }
            let tokenAmount = try review.draft.amount.smallestUnit(decimals: asset.decimals)
            input.toAddress = contract
            input.transaction = EthereumTransaction.with {
                $0.erc20Transfer = EthereumTransaction.ERC20Transfer.with {
                    $0.to = review.draft.recipient
                    $0.amount = Data(hexString: String(tokenAmount, radix: 16).leftPaddedToEvenLength) ?? Data()
                }
            }
        }

        let output: EthereumSigningOutput = AnySigner.sign(input: input, coin: .ethereum)
        guard output.error == .ok else {
            let reason = output.errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TransactionServiceError.broadcastFailed(
                reason.isEmpty
                    ? "\(network.displayName) transaction signing failed."
                    : "\(network.displayName) transaction signing failed: \(reason)"
            )
        }
        return output
    }
    #endif
}

private struct EthereumFeeComponents {
    let maxFeePerGas: UInt64
    let priorityFeePerGas: UInt64
}
