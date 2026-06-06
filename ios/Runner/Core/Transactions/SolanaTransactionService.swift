import Foundation

#if canImport(WalletCore)
import WalletCore
#endif

final class SolanaTransactionService: TransactionServiceProtocol {
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
        guard network.family == .solana else { throw TransactionServiceError.unsupportedNetwork }
        guard draft.amount > 0 else { throw TransactionServiceError.invalidAmount }
        guard WalletCoreBridge.validateAddress(draft.recipient, chainID: network.rawValue) else {
            throw TransactionServiceError.invalidRecipient
        }

        let lamports = asset.isNative ? Decimal(5_000) : Decimal(10_000)
        let fee = lamports / pow10(network.decimals)
        let totalDebit = asset.isNative ? draft.amount + fee : draft.amount
        if asset.isNative && asset.balance < totalDebit {
            throw TransactionServiceError.insufficientFunds
        }

        return TransferQuote(
            asset: asset,
            fee: fee,
            feeSymbol: network.feeSymbol,
            totalDebit: totalDebit,
            networkDetail: asset.isNative ? "base fee" : "token transfer fee",
            editableFee: false
        )
    }

    func send(
        review: TransferReview,
        signing: WalletSigningContext
    ) async throws -> BroadcastReceipt {
        #if canImport(WalletCore)
        let blockhash = try await recentBlockhash()
        let keyData = try WalletCoreBridge.privateKeyData(for: signing)
        let output = try sign(asset: review.quote.asset, review: review, signing: signing, blockhash: blockhash, keyData: keyData)
        let signature = try await broadcast(base64Transaction: output.encoded)

        return BroadcastReceipt(
            chainID: network.rawValue,
            txHash: signature,
            submittedAt: Date(),
            explorerURL: URL(string: "\(network.explorerBase)/tx/\(signature)")
        )
        #else
        throw TransactionServiceError.signingUnavailable
        #endif
    }

    private func recentBlockhash() async throws -> String {
        struct BlockhashResponse: Decodable {
            let result: BlockhashResult
        }
        struct BlockhashResult: Decodable {
            let value: BlockhashValue
        }
        struct BlockhashValue: Decodable {
            let blockhash: String
        }

        let response: BlockhashResponse = try await JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "getLatestBlockhash", params: [CoreAnyEncodable(["commitment": "confirmed"])]),
            url: network.rpcURL,
            responseType: BlockhashResponse.self
        )
        return response.result.value.blockhash
    }

    private func broadcast(base64Transaction: String) async throws -> String {
        struct SignatureResponse: Decodable {
            let result: String
        }

        let response: SignatureResponse = try await JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "sendTransaction", params: [
                CoreAnyEncodable(base64Transaction),
                CoreAnyEncodable([
                    "encoding": CoreAnyEncodable("base64"),
                    "skipPreflight": CoreAnyEncodable(false),
                    "preflightCommitment": CoreAnyEncodable("confirmed")
                ])
            ]),
            url: network.rpcURL,
            responseType: SignatureResponse.self
        )
        return response.result
    }

    #if canImport(WalletCore)
    private func sign(
        asset: WalletAssetBalance,
        review: TransferReview,
        signing: WalletSigningContext,
        blockhash: String,
        keyData: Data
    ) throws -> SolanaSigningOutput {
        let amount = try review.draft.amount.smallestUnit(decimals: asset.decimals)

        var input = SolanaSigningInput.with {
            $0.recentBlockhash = blockhash
            $0.privateKey = keyData
            $0.sender = signing.chain.address
            $0.txEncoding = .base64
        }

        if asset.isNative {
            input.transferTransaction = SolanaTransfer.with {
                $0.recipient = review.draft.recipient
                $0.value = UInt64(amount)
            }
        } else {
            guard let mint = asset.contractAddress else { throw TransactionServiceError.unsupportedAsset }
            input.tokenTransferTransaction = SolanaTokenTransfer.with {
                $0.tokenMintAddress = mint
                $0.senderTokenAddress = asset.accountAddress
                $0.recipientTokenAddress = SolanaAddress(string: review.draft.recipient)?.defaultTokenAddress(tokenMintAddress: mint) ?? ""
                $0.amount = UInt64(amount)
                $0.decimals = UInt32(asset.decimals)
            }
        }

        let output: SolanaSigningOutput = AnySigner.sign(input: input, coin: .solana)
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
