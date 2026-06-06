import Foundation

final class TransactionServiceFactory {
    func service(for chain: WalletChain) -> TransactionServiceProtocol? {
        guard let network = chain.network else { return nil }

        switch network.family {
        case .utxo:
            return UtxoTransactionService(network: network)
        case .evm:
            return EvmTransactionService(network: network)
        case .solana:
            return SolanaTransactionService(network: network)
        case .tron, .ton:
            return nil
        }
    }
}
