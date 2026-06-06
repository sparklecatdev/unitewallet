import Foundation
import Combine

// MARK: - Adapter Manager

/// Manages chain adapters lifecycle and provides a unified async API
final class AdapterManager {
    private let factory: AdapterFactory
    private let transactionFactory: TransactionServiceFactory

    private let balanceResultsSubject = CurrentValueSubject<[String: ChainBalanceSnapshot], Never>([:])
    private let assetResultsSubject = CurrentValueSubject<[WalletAssetBalance], Never>([])

    init(
        factory: AdapterFactory = AdapterFactory(),
        transactionFactory: TransactionServiceFactory = TransactionServiceFactory()
    ) {
        self.factory = factory
        self.transactionFactory = transactionFactory
    }

    // MARK: - Publishers

    var balanceResultsPublisher: AnyPublisher<[String: ChainBalanceSnapshot], Never> {
        balanceResultsSubject.eraseToAnyPublisher()
    }

    var assetResultsPublisher: AnyPublisher<[WalletAssetBalance], Never> {
        assetResultsSubject.eraseToAnyPublisher()
    }

    // MARK: - Balance Fetching

    /// Fetch balances for multiple chains concurrently
    func fetchBalances(for chains: [WalletChain]) async -> [String: ChainBalanceSnapshot] {
        await withTaskGroup(of: (String, ChainBalanceSnapshot).self) { group in
            for chain in chains {
                group.addTask { [weak self] in
                    await self?.fetchBalance(for: chain) ?? (chain.id, ChainBalanceSnapshot(
                        balance: 0,
                        updatedAt: Date(),
                        status: .failed,
                        message: "Adapter manager unavailable"
                    ))
                }
            }

            var results: [String: ChainBalanceSnapshot] = [:]
            for await (chainID, snapshot) in group {
                results[chainID] = snapshot
            }

            balanceResultsSubject.send(results)
            return results
        }
    }

    private func fetchBalance(for chain: WalletChain) async -> (String, ChainBalanceSnapshot) {
        guard let adapter = factory.adapter(for: chain.id) else {
            return (chain.id, ChainBalanceSnapshot(
                balance: 0,
                updatedAt: Date(),
                status: .failed,
                message: "Unsupported network"
            ))
        }

        do {
            let balance = try await adapter.balance(address: chain.address)
            return (chain.id, ChainBalanceSnapshot(
                balance: balance,
                updatedAt: Date(),
                status: .synced,
                message: nil
            ))
        } catch {
            return (chain.id, ChainBalanceSnapshot(
                balance: 0,
                updatedAt: Date(),
                status: .failed,
                message: error.localizedDescription
            ))
        }
    }

    // MARK: - Asset Discovery

    /// Discover all assets (native + tokens) for a set of chains
    func discoverAssets(for chains: [WalletChain]) async -> [WalletAssetBalance] {
        await withTaskGroup(of: [WalletAssetBalance].self) { group in
            for chain in chains {
                group.addTask { [weak self] in
                    guard let adapter = self?.factory.adapter(for: chain.id) else {
                        // Return default asset with zero balance
                        return WalletCoreBridge.defaultAssets(for: [chain])
                    }
                    return (try? await adapter.discoverAssets(address: chain.address, chain: chain))
                        ?? WalletCoreBridge.defaultAssets(for: [chain])
                }
            }

            var allAssets: [WalletAssetBalance] = []
            for await assets in group {
                allAssets.append(contentsOf: assets)
            }

            if allAssets.isEmpty {
                allAssets = WalletCoreBridge.defaultAssets(for: chains)
            }

            let sorted = allAssets.sorted { lhs, rhs in
                if lhs.chainID == rhs.chainID {
                    if lhs.isNative == rhs.isNative {
                        return lhs.symbol < rhs.symbol
                    }
                    return lhs.isNative && !rhs.isNative
                }
                return lhs.chainID < rhs.chainID
            }

            assetResultsSubject.send(sorted)
            return sorted
        }
    }

    // MARK: - Transfer Operations

    /// Create a signing context for a chain from the account's secrets
    func signingContext(for chain: WalletChain, mnemonic: String, privateKey: String) -> WalletSigningContext {
        WalletCoreBridge.signingContext(mnemonic: mnemonic, privateKey: privateKey, chain: chain)
    }

    /// Build a transfer quote for a draft transaction
    func quote(
        draft: TransferDraft,
        asset: WalletAssetBalance,
        chain: WalletChain,
        signing: WalletSigningContext
    ) async throws -> TransferQuote {
        guard let service = transactionFactory.service(for: chain) else {
            throw TransactionServiceError.unsupportedNetwork
        }
        return try await service.quote(draft: draft, asset: asset, sourceChain: chain, signing: signing)
    }

    /// Sign and broadcast a reviewed transfer
    func send(
        review: TransferReview,
        chain: WalletChain,
        signing: WalletSigningContext
    ) async throws -> BroadcastReceipt {
        guard let service = transactionFactory.service(for: chain) else {
            throw TransactionServiceError.unsupportedNetwork
        }
        return try await service.send(review: review, signing: signing)
    }

    /// Check if a chain has a registered adapter
    func isSupported(chainID: String) -> Bool {
        factory.adapter(for: chainID) != nil
    }

    /// Get list of all supported chain IDs
    var supportedChainIDs: [String] {
        factory.registeredChainIDs
    }

    /// Register a new adapter at runtime (e.g., for custom EVM chains)
    func registerAdapter(chainID: String, adapter: @escaping () -> ChainAdapter) {
        factory.register(chainID: chainID, factory: adapter)
    }

    /// Remove an adapter
    func unregisterAdapter(chainID: String) {
        factory.unregister(chainID: chainID)
    }
}
