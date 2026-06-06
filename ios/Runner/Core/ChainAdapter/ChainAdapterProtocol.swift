import Foundation

// MARK: - Chain Adapter Protocol

protocol ChainAdapter {
    var chainID: String { get }
    var network: WalletNetwork { get }
    var displayName: String { get }
    var symbol: String { get }
    var decimals: Int { get }
    var feeSymbol: String { get }

    /// Fetch native balance for the given address
    func balance(address: String) async throws -> Decimal

    /// Discover all assets (native + tokens) for the given address
    func discoverAssets(address: String, chain: WalletChain) async throws -> [WalletAssetBalance]

    /// Validate a destination address for this chain
    func validate(address: String) -> Bool

    /// Estimate fee for a standard transfer (used for chain state snapshots)
    func estimateFee(address: String) async throws -> Decimal
}

extension ChainAdapter {
    var feeSymbol: String { symbol }
}
