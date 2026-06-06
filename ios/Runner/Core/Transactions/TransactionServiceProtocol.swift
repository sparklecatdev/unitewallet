import Foundation

protocol TransactionServiceProtocol {
    func quote(
        draft: TransferDraft,
        asset: WalletAssetBalance,
        sourceChain: WalletChain,
        signing: WalletSigningContext
    ) async throws -> TransferQuote

    func send(
        review: TransferReview,
        signing: WalletSigningContext
    ) async throws -> BroadcastReceipt
}
