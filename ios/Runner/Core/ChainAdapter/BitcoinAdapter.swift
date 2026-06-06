import Foundation

#if canImport(WalletCore)
import WalletCore
#endif

final class BitcoinAdapter: ChainAdapter {
    let chainID: String = WalletNetwork.bitcoin.rawValue
    let network: WalletNetwork = .bitcoin
    let displayName: String = "Bitcoin"
    let symbol: String = "BTC"
    let decimals: Int = 8
    let feeSymbol: String = "BTC"

    func balance(address: String) async throws -> Decimal {
        let utxos = try await fetchUTXOs(address: address)
        let totalSats = utxos.reduce(0) { $0 + $1.value }
        return Decimal(totalSats) / pow10(8)
    }

    func discoverAssets(address: String, chain: WalletChain) async throws -> [WalletAssetBalance] {
        let utxos = try await fetchUTXOs(address: address)
        let totalSats = utxos.reduce(0) { $0 + $1.value }
        return [
            WalletAssetBalance(
                chainID: chainID,
                symbol: symbol,
                name: displayName,
                decimals: decimals,
                balance: Decimal(totalSats) / pow10(8),
                isNative: true,
                contractAddress: nil,
                tokenStandard: .native,
                accountAddress: address
            )
        ]
    }

    func validate(address: String) -> Bool {
        #if canImport(WalletCore)
        return CoinType.bitcoin.validate(address: address)
        #else
        return false
        #endif
    }

    func estimateFee(address: String) async throws -> Decimal {
        let feeRate = try await fetchFeeRate()
        return Decimal(Int(max(2, feeRate)) * 225) / pow10(8)
    }

    // MARK: - RPC Calls

    private func fetchUTXOs(address: String) async throws -> [BlockstreamUTXO] {
        let url = URL(string: "https://blockstream.info/api/address/\(address)/utxo")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([BlockstreamUTXO].self, from: data)
    }

    private func fetchFeeRate() async throws -> Double {
        let url = URL(string: "https://mempool.space/api/v1/fees/recommended")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            // Fallback to blockstream
            let altURL = URL(string: "https://blockstream.info/api/fee-estimates")!
            let (altData, altResponse) = try await URLSession.shared.data(from: altURL)
            guard (altResponse as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let payload = try JSONDecoder().decode([String: Double].self, from: altData)
            return payload["3"] ?? payload["6"] ?? 5
        }

        struct MempoolFees: Decodable {
            let fastestFee: Double
            let halfHourFee: Double
            let hourFee: Double
            let economyFee: Double
            let minimumFee: Double
        }
        let fees = try JSONDecoder().decode(MempoolFees.self, from: data)
        return fees.fastestFee
    }
}
