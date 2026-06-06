import Foundation

#if canImport(WalletCore)
import WalletCore
#endif

final class UtxoTransactionService: TransactionServiceProtocol {
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
        guard network == .bitcoin else { throw TransactionServiceError.unsupportedNetwork }
        guard draft.amount > 0 else { throw TransactionServiceError.invalidAmount }
        guard WalletCoreBridge.validateAddress(draft.recipient, chainID: network.rawValue) else {
            throw TransactionServiceError.invalidRecipient
        }
        guard asset.isNative else { throw TransactionServiceError.unsupportedAsset }

        let utxos = try await fetchUTXOs(address: sourceChain.address)
        let feeRate = try await fetchFeeRate()
        let totalAvailable = utxos.reduce(Decimal.zero) { $0 + Decimal($1.value) / pow10(network.decimals) }
        let fee = Decimal(Int(max(2, feeRate)) * 225) / pow10(network.decimals)
        let totalDebit = draft.amount + fee
        guard totalAvailable >= totalDebit else { throw TransactionServiceError.insufficientFunds }

        return TransferQuote(
            asset: asset,
            fee: fee,
            feeSymbol: network.feeSymbol,
            totalDebit: totalDebit,
            networkDetail: "\(Int(max(2, feeRate))) sat/vB",
            editableFee: true
        )
    }

    func send(
        review: TransferReview,
        signing: WalletSigningContext
    ) async throws -> BroadcastReceipt {
        #if canImport(WalletCore)
        let utxos = try await fetchUTXOs(address: signing.chain.address)
        let feeRate = try await fetchFeeRate()
        let amountSats = try review.draft.amount.smallestUnit(decimals: network.decimals)
        let keyData = try WalletCoreBridge.privateKeyData(for: signing)

        let output = try sign(
            recipient: review.draft.recipient,
            amountSats: amountSats,
            feeRate: UInt64(max(2, Int(feeRate))),
            utxos: utxos,
            changeAddress: signing.chain.address,
            keyData: keyData
        )

        let rpcURL = URL(string: "https://blockstream.info/api/tx")!
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.httpBody = output.encoded
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let reason = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw TransactionServiceError.broadcastFailed(
                reason?.isEmpty == false
                    ? "\(network.displayName) transaction broadcast failed: \(reason!)"
                    : "\(network.displayName) transaction broadcast failed."
            )
        }

        let txHash = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return BroadcastReceipt(
            chainID: network.rawValue,
            txHash: txHash?.isEmpty == false ? txHash! : output.transactionID,
            submittedAt: Date(),
            explorerURL: URL(string: "\(network.explorerBase)/tx/\(txHash ?? output.transactionID)")
        )
        #else
        throw TransactionServiceError.signingUnavailable
        #endif
    }

    #if canImport(WalletCore)
    private func sign(
        recipient: String,
        amountSats: Int64,
        feeRate: UInt64,
        utxos: [BlockstreamUTXO],
        changeAddress: String,
        keyData: Data
    ) throws -> BitcoinSigningOutput {
        guard let privateKey = PrivateKey(data: keyData) else {
            throw TransactionServiceError.missingKey
        }

        var input = BitcoinSigningInput.with {
            $0.hashType = BitcoinScript.hashTypeForCoin(coinType: .bitcoin)
            $0.amount = amountSats
            $0.byteFee = Int64(feeRate)
            $0.toAddress = recipient
            $0.changeAddress = changeAddress
            $0.coinType = CoinType.bitcoin.rawValue
            $0.privateKey = [privateKey.data]
        }

        input.utxo = utxos.map { utxo in
            let txHashData = Data(hexString: utxo.txid)?.reversedData() ?? Data()
            let script = BitcoinScript.lockScriptForAddress(address: changeAddress, coin: .bitcoin)
            return BitcoinUnspentTransaction.with {
                $0.outPoint.hash = txHashData
                $0.outPoint.index = UInt32(utxo.vout)
                $0.outPoint.sequence = UInt32.max
                $0.script = script.data
                $0.amount = utxo.value
            }
        }

        let plan: BitcoinTransactionPlan = AnySigner.plan(input: input, coin: .bitcoin)
        input.plan = plan
        return AnySigner.sign(input: input, coin: .bitcoin)
    }
    #endif

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
        }

        let fees = try JSONDecoder().decode(MempoolFees.self, from: data)
        return fees.fastestFee
    }
}
