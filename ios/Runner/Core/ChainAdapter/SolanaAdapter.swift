import Foundation

#if canImport(WalletCore)
import WalletCore
#endif

final class SolanaAdapter: ChainAdapter {
    let chainID: String = WalletNetwork.solana.rawValue
    let network: WalletNetwork = .solana
    let displayName: String = "Solana"
    let symbol: String = "SOL"
    let decimals: Int = 9
    let feeSymbol: String = "SOL"

    private let rpcURL: URL = URL(string: "https://api.mainnet-beta.solana.com")!
    private let explorerBase: String = "https://solscan.io"

    func balance(address: String) async throws -> Decimal {
        let response: CoreSolanaBalanceResponse = try await JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "getBalance", params: [CoreAnyEncodable(address), CoreAnyEncodable(["commitment": "confirmed"])]),
            url: rpcURL,
            responseType: CoreSolanaBalanceResponse.self
        )
        return Decimal(response.result.value) / Decimal(1_000_000_000)
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

        let tokenAccounts = try await splTokenAccounts(owner: address)
        for token in network.tokenRegistry {
            guard let match = tokenAccounts.first(where: { $0.mint == token.contractAddress }) else { continue }
            if match.uiAmount > 0 {
                assets.append(
                    WalletAssetBalance(
                        chainID: chainID,
                        symbol: token.symbol,
                        name: token.name,
                        decimals: token.decimals,
                        balance: Decimal(match.uiAmount),
                        isNative: false,
                        contractAddress: token.contractAddress,
                        tokenStandard: token.tokenStandard,
                        accountAddress: match.tokenAccountAddress
                    )
                )
            }
        }

        return assets
    }

    func validate(address: String) -> Bool {
        #if canImport(WalletCore)
        return CoinType.solana.validate(address: address)
        #else
        return false
        #endif
    }

    func estimateFee(address: String) async throws -> Decimal {
        Decimal(5_000) / pow10(decimals)
    }

    // MARK: - SPL Token Helpers

    struct SplTokenAccountMatch {
        let mint: String
        let tokenAccountAddress: String
        let uiAmount: Double
    }

    private func splTokenAccounts(owner: String) async throws -> [SplTokenAccountMatch] {
        let params: [CoreAnyEncodable] = [
            CoreAnyEncodable(owner),
            CoreAnyEncodable(["programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"]),
            CoreAnyEncodable(["encoding": "jsonParsed", "commitment": "confirmed"])
        ]

        struct TokenAccountsResponse: Decodable {
            let result: TokenAccountsResult
        }
        struct TokenAccountsResult: Decodable {
            let value: [TokenAccount]
        }
        struct TokenAccount: Decodable {
            let pubkey: String
            let account: AccountInfo
        }
        struct AccountInfo: Decodable {
            let data: ParsedData
        }
        struct ParsedData: Decodable {
            let parsed: ParsedInfo
        }
        struct ParsedInfo: Decodable {
            let info: TokenInfo
        }
        struct TokenInfo: Decodable {
            let mint: String
            let tokenAmount: TokenAmount
        }
        struct TokenAmount: Decodable {
            let uiAmount: Double
        }

        let response: TokenAccountsResponse = try await JSONRPCHelper.post(
            CoreJSONRPCRequest(method: "getTokenAccountsByOwner", params: params),
            url: rpcURL,
            responseType: TokenAccountsResponse.self
        )

        return response.result.value.map {
            SplTokenAccountMatch(
                mint: $0.account.data.parsed.info.mint,
                tokenAccountAddress: $0.pubkey,
                uiAmount: $0.account.data.parsed.info.tokenAmount.uiAmount
            )
        }
    }

}
