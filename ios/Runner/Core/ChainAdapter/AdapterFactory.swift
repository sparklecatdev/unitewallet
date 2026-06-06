import Foundation

// MARK: - Adapter Factory

final class AdapterFactory {

    /// Registry of chainID → adapter creation block
    private var registry: [String: () -> ChainAdapter] = [:]

    init() {
        registerDefaults()
    }

    /// Get the adapter for a specific chain ID
    func adapter(for chainID: String) -> ChainAdapter? {
        registry[chainID]?()
    }

    /// Get all chain IDs with registered adapters
    var registeredChainIDs: [String] {
        Array(registry.keys)
    }

    /// Register a custom adapter for a chain
    func register(chainID: String, factory: @escaping () -> ChainAdapter) {
        registry[chainID] = factory
    }

    /// Remove an adapter registration
    func unregister(chainID: String) {
        registry.removeValue(forKey: chainID)
    }

    // MARK: - Default Adapters

    private func registerDefaults() {
        // Bitcoin
        register(chainID: WalletNetwork.bitcoin.rawValue) {
            BitcoinAdapter()
        }

        // Ethereum Mainnet
        register(chainID: WalletNetwork.ethereum.rawValue) {
            EthereumAdapter(
                chainID: WalletNetwork.ethereum.rawValue,
                network: .ethereum,
                displayName: "Ethereum",
                symbol: "ETH",
                rpcURL: URL(string: "https://ethereum-rpc.publicnode.com")!,
                explorerBase: "https://etherscan.io"
            )
        }

        // Solana
        register(chainID: WalletNetwork.solana.rawValue) {
            SolanaAdapter()
        }

        // Popular EVM chains (using EthereumAdapter with custom configs)
        registerEvmChain(
            network: .bsc,
            displayName: "BNB Smart Chain",
            symbol: "BNB",
            rpcURL: URL(string: "https://bsc-dataseed.binance.org")!,
            explorerBase: "https://bscscan.com"
        )

        registerEvmChain(
            network: .polygon,
            displayName: "Polygon",
            symbol: "MATIC",
            rpcURL: URL(string: "https://polygon-rpc.com")!,
            explorerBase: "https://polygonscan.com"
        )

        registerEvmChain(
            network: .arbitrum,
            displayName: "Arbitrum One",
            symbol: "ETH",
            rpcURL: URL(string: "https://arb1.arbitrum.io/rpc")!,
            explorerBase: "https://arbiscan.io"
        )

        registerEvmChain(
            network: .optimism,
            displayName: "Optimism",
            symbol: "ETH",
            rpcURL: URL(string: "https://mainnet.optimism.io")!,
            explorerBase: "https://optimistic.etherscan.io"
        )

        registerEvmChain(
            network: .avalancheC,
            displayName: "Avalanche C-Chain",
            symbol: "AVAX",
            rpcURL: URL(string: "https://api.avax.network/ext/bc/C/rpc")!,
            explorerBase: "https://snowtrace.io"
        )

        registerEvmChain(
            network: .base,
            displayName: "Base",
            symbol: "ETH",
            rpcURL: URL(string: "https://mainnet.base.org")!,
            explorerBase: "https://basescan.org"
        )

        registerEvmChain(
            network: .gnosis,
            displayName: "Gnosis",
            symbol: "xDAI",
            rpcURL: URL(string: "https://rpc.gnosischain.com")!,
            explorerBase: "https://gnosisscan.io"
        )

        registerEvmChain(
            network: .fantom,
            displayName: "Fantom",
            symbol: "FTM",
            rpcURL: URL(string: "https://rpc.ftm.tools")!,
            explorerBase: "https://ftmscan.com"
        )
    }

    private func registerEvmChain(network: WalletNetwork, displayName: String, symbol: String, rpcURL: URL, explorerBase: String) {
        register(chainID: network.rawValue) {
            EthereumAdapter(
                chainID: network.rawValue,
                network: network,
                displayName: displayName,
                symbol: symbol,
                rpcURL: rpcURL,
                explorerBase: explorerBase
            )
        }
    }
}
