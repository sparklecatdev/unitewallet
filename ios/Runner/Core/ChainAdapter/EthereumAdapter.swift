import Foundation

#if canImport(WalletCore)
import WalletCore
#endif

final class EthereumAdapter: ChainAdapter {
    let chainID: String
    let network: WalletNetwork
    let displayName: String
    let symbol: String
    let decimals: Int = 18
    var feeSymbol: String { symbol }

    private let rpcURL: URL
    private let explorerBase: String

    init(
        chainID: String = WalletNetwork.ethereum.rawValue,
        network: WalletNetwork = .ethereum,
        displayName: String = "Ethereum",
        symbol: String = "ETH",
        rpcURL: URL = URL(string: "https://ethereum-rpc.publicnode.com")!,
        explorerBase: String = "https://etherscan.io"
    ) {
        self.chainID = chainID
        self.network = network
        self.displayName = displayName
        self.symbol = symbol
        self.rpcURL = rpcURL
        self.explorerBase = explorerBase
    }

    func balance(address: String) async throws -> Decimal {
        let response: CoreEthereumBalanceResponse = try await JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "eth_getBalance", params: [CoreAnyEncodable(address), CoreAnyEncodable("latest")]),
            url: rpcURL,
            responseType: CoreEthereumBalanceResponse.self
        )
        return Decimal.fromHexString(response.result) / pow10(18)
    }

    func discoverAssets(address: String, chain: WalletChain) async throws -> [WalletAssetBalance] {
        var assets: [WalletAssetBalance] = [
            WalletAssetBalance(
                chainID: chainID,
                symbol: symbol,
                name: displayName,
                decimals: decimals,
                balance: try await balance(address: address),
                isNative: true,
                contractAddress: nil,
                tokenStandard: .native,
                accountAddress: address
            )
        ]

        for token in network.tokenRegistry {
            guard let contractAddress = token.contractAddress else { continue }
            do {
                let tokenBalance = try await erc20Balance(owner: address, contract: contractAddress, decimals: token.decimals)
                if tokenBalance > 0 {
                    assets.append(
                        WalletAssetBalance(
                            chainID: chainID,
                            symbol: token.symbol,
                            name: token.name,
                            decimals: token.decimals,
                            balance: tokenBalance,
                            isNative: false,
                            contractAddress: contractAddress,
                            tokenStandard: token.tokenStandard,
                            accountAddress: address
                        )
                    )
                }
            } catch {
                // Skip individual token fetch failures
                continue
            }
        }

        return assets
    }

    func validate(address: String) -> Bool {
        #if canImport(WalletCore)
        return CoinType.ethereum.validate(address: address)
        #else
        return address.hasPrefix("0x") && address.count == 42
        #endif
    }

    func estimateFee(address: String) async throws -> Decimal {
        let fees = try await feeComponents()
        return Decimal(21_000) * Decimal(fees.maxFeePerGas) / pow10(18)
    }

    // MARK: - Token Helpers

    private func erc20Balance(owner: String, contract: String, decimals: Int) async throws -> Decimal {
        let callObject: [String: String] = [
            "to": contract,
            "data": "0x70a08231" + owner.stripHexPrefix.leftPadded(to: 64)
        ]
        let response: CoreEthereumBalanceResponse = try await JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "eth_call", params: [CoreAnyEncodable(callObject), CoreAnyEncodable("latest")]),
            url: rpcURL,
            responseType: CoreEthereumBalanceResponse.self
        )
        return Decimal.fromHexString(response.result) / pow10(decimals)
    }

    private func fetchNonce(address: String) async throws -> UInt64 {
        let response: CoreEthereumBalanceResponse = try await JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "eth_getTransactionCount", params: [CoreAnyEncodable(address), CoreAnyEncodable("pending")]),
            url: rpcURL,
            responseType: CoreEthereumBalanceResponse.self
        )
        return UInt64(response.result.stripHexPrefix, radix: 16) ?? 0
    }

    private func feeComponents() async throws -> EthereumFeeComponents {
        async let gasPrice: CoreEthereumBalanceResponse = JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "eth_gasPrice", params: []),
            url: rpcURL,
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
            url: rpcURL,
            responseType: BlockResponse.self
        )

        async let priority: CoreEthereumBalanceResponse = JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "eth_maxPriorityFeePerGas", params: []),
            url: rpcURL,
            responseType: CoreEthereumBalanceResponse.self
        )

        let gas = try await gasPrice
        let blockResult = try await block
        let priorityFee = try await priority

        let baseFee = UInt64(blockResult.result.baseFeePerGas?.stripHexPrefix ?? gas.result.stripHexPrefix, radix: 16) ?? 0
        let priorityFeeVal = UInt64(priorityFee.result.stripHexPrefix, radix: 16) ?? 1_500_000_000
        let gasPriceVal = UInt64(gas.result.stripHexPrefix, radix: 16)
        let maxFee = max(baseFee * 2 + priorityFeeVal, gasPriceVal ?? priorityFeeVal)

        return EthereumFeeComponents(maxFeePerGas: maxFee, priorityFeePerGas: priorityFeeVal)
    }

}

private struct EthereumFeeComponents {
    let maxFeePerGas: UInt64
    let priorityFeePerGas: UInt64
}
