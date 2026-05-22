import Foundation

#if canImport(WalletCore)
import WalletCore
#endif

struct WalletChain: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let address: String
    let derivationPath: String
    let standards: String

    var shortAddress: String {
        guard address.count > 14 else { return address }
        return "\(address.prefix(6))...\(address.suffix(6))"
    }

    var family: String {
        switch network {
        case .bitcoin?, .ethereum?:
            return "secp256k1"
        case .solana?:
            return "Ed25519"
        case nil:
            return "Unknown"
        }
    }

    var network: WalletNetwork? {
        WalletNetwork(rawValue: id)
    }
}

struct WalletMaterial {
    let mnemonic: String
    let privateKey: String
    let primaryAddress: String
    let chains: [WalletChain]
    let engine: String
}

enum WalletNetwork: String, CaseIterable, Codable, Identifiable {
    case bitcoin
    case ethereum
    case solana

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bitcoin: "Bitcoin"
        case .ethereum: "Ethereum"
        case .solana: "Solana"
        }
    }

    var symbol: String {
        switch self {
        case .bitcoin: "BTC"
        case .ethereum: "ETH"
        case .solana: "SOL"
        }
    }

    var derivationStandard: String {
        switch self {
        case .bitcoin: "BIP44 / secp256k1"
        case .ethereum: "BIP44 / secp256k1"
        case .solana: "SLIP-0010 / Ed25519"
        }
    }

    var coinGeckoID: String {
        rawValue
    }

    var fractionDigits: Int {
        switch self {
        case .bitcoin: 8
        case .ethereum, .solana: 6
        }
    }

    var decimals: Int {
        switch self {
        case .bitcoin: 8
        case .ethereum: 18
        case .solana: 9
        }
    }

    var feeSymbol: String {
        symbol
    }

    var rpcURL: URL {
        switch self {
        case .bitcoin:
            return URL(string: "https://blockstream.info/api")!
        case .ethereum:
            return URL(string: "https://ethereum-rpc.publicnode.com")!
        case .solana:
            return URL(string: "https://api.mainnet-beta.solana.com")!
        }
    }

    var caipNamespace: String {
        switch self {
        case .bitcoin: "bip122"
        case .ethereum: "eip155"
        case .solana: "solana"
        }
    }

    var caipReference: String {
        switch self {
        case .bitcoin:
            return "000000000019d6689c085ae165831e93"
        case .ethereum:
            return "1"
        case .solana:
            return "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"
        }
    }

    var tokenRegistry: [WalletAssetToken] {
        switch self {
        case .bitcoin:
            return []
        case .ethereum:
            return [
                .init(chainID: rawValue, symbol: "USDC", name: "USD Coin", decimals: 6, assetID: "usd-coin", contractAddress: "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", tokenStandard: .erc20),
                .init(chainID: rawValue, symbol: "USDT", name: "Tether USD", decimals: 6, assetID: "tether", contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7", tokenStandard: .erc20),
                .init(chainID: rawValue, symbol: "DAI", name: "Dai", decimals: 18, assetID: "dai", contractAddress: "0x6B175474E89094C44Da98b954EedeAC495271d0F", tokenStandard: .erc20)
            ]
        case .solana:
            return [
                .init(chainID: rawValue, symbol: "USDC", name: "USD Coin", decimals: 6, assetID: "usd-coin", contractAddress: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", tokenStandard: .spl),
                .init(chainID: rawValue, symbol: "JUP", name: "Jupiter", decimals: 6, assetID: "jupiter-exchange-solana", contractAddress: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN", tokenStandard: .spl),
                .init(chainID: rawValue, symbol: "BONK", name: "Bonk", decimals: 5, assetID: "bonk", contractAddress: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263", tokenStandard: .spl)
            ]
        }
    }
}

enum WalletAssetStandard: String, Codable {
    case native
    case erc20
    case spl
}

struct WalletAssetToken: Identifiable, Codable, Equatable {
    var id: String { "\(chainID):\(assetID):\(contractAddress ?? symbol)" }
    let chainID: String
    let symbol: String
    let name: String
    let decimals: Int
    let assetID: String
    let contractAddress: String?
    let tokenStandard: WalletAssetStandard
}

struct WalletAssetBalance: Identifiable, Codable, Equatable {
    let id: String
    let chainID: String
    let symbol: String
    let name: String
    let decimals: Int
    let balance: Decimal
    let isNative: Bool
    let contractAddress: String?
    let tokenStandard: WalletAssetStandard
    let accountAddress: String
    let sendable: Bool

    init(
        chainID: String,
        symbol: String,
        name: String,
        decimals: Int,
        balance: Decimal,
        isNative: Bool,
        contractAddress: String?,
        tokenStandard: WalletAssetStandard,
        accountAddress: String,
        sendable: Bool = true
    ) {
        id = "\(chainID):\(contractAddress ?? "native")"
        self.chainID = chainID
        self.symbol = symbol
        self.name = name
        self.decimals = decimals
        self.balance = balance
        self.isNative = isNative
        self.contractAddress = contractAddress
        self.tokenStandard = tokenStandard
        self.accountAddress = accountAddress
        self.sendable = sendable
    }
}

struct TransferDraft: Identifiable, Codable, Equatable {
    let id: UUID
    var chainID: String
    var assetID: String
    var recipient: String
    var amount: Decimal
    var saveRecipientName: String

    init(id: UUID = UUID(), chainID: String, assetID: String, recipient: String, amount: Decimal, saveRecipientName: String = "") {
        self.id = id
        self.chainID = chainID
        self.assetID = assetID
        self.recipient = recipient
        self.amount = amount
        self.saveRecipientName = saveRecipientName
    }
}

struct TransferQuote: Codable, Equatable {
    let asset: WalletAssetBalance
    let fee: Decimal
    let feeSymbol: String
    let totalDebit: Decimal
    let networkDetail: String
    let editableFee: Bool
}

struct TransferReview: Codable, Equatable {
    let draft: TransferDraft
    let quote: TransferQuote
    let sourceAddress: String
}

struct BroadcastReceipt: Codable, Equatable {
    let chainID: String
    let txHash: String
    let submittedAt: Date
    let explorerURL: URL?
}

struct WalletSigningContext {
    let mnemonic: String
    let privateKey: String
    let chain: WalletChain
}

protocol ChainTransactionService {
    var network: WalletNetwork { get }
    func quote(draft: TransferDraft, asset: WalletAssetBalance, sourceChain: WalletChain, signing: WalletSigningContext) async throws -> TransferQuote
    func send(review: TransferReview, signing: WalletSigningContext) async throws -> BroadcastReceipt
    func discoverAssets(for chain: WalletChain) async throws -> [WalletAssetBalance]
}

enum TransactionServiceError: LocalizedError {
    case unsupportedNetwork
    case invalidAmount
    case invalidRecipient
    case unsupportedAsset
    case insufficientFunds
    case missingKey
    case signingUnavailable
    case broadcastFailed(String)
    case rpcError(String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unsupportedNetwork:
            return "That network is not supported in this build."
        case .invalidAmount:
            return "Enter an amount greater than zero."
        case .invalidRecipient:
            return "The recipient address does not match the selected network."
        case .unsupportedAsset:
            return "That asset is not sendable from this wallet yet."
        case .insufficientFunds:
            return "The wallet does not have enough balance for this transfer and its network fee."
        case .missingKey:
            return "The signing key for this network is unavailable on this device."
        case .signingUnavailable:
            return "Transaction signing is unavailable on this build."
        case .broadcastFailed(let reason):
            return reason
        case .rpcError(let reason):
            return reason
        case .malformedResponse:
            return "The network response could not be understood."
        }
    }
}

enum WalletCoreBridge {
    enum ImportError: LocalizedError {
        case engineUnavailable
        case invalidMnemonic
        case invalidPrivateKey
        case noAddress

        var errorDescription: String? {
            switch self {
            case .engineUnavailable:
                return "The wallet engine is unavailable. This beta cannot create or open wallets on this build."
            case .invalidMnemonic:
                return "That recovery phrase could not be opened. Check the words and spacing, then try again."
            case .invalidPrivateKey:
                return "That private key could not be opened. Use a Solana base58 key or a 64-character hex key."
            case .noAddress:
                return "The wallet opened, but no supported address could be created."
            }
        }
    }

    static let supportedChainID = WalletNetwork.solana.rawValue

    static func createWallet() throws -> WalletMaterial {
        #if canImport(WalletCore)
        guard let wallet = HDWallet(strength: 128, passphrase: "") else {
            throw ImportError.invalidMnemonic
        }
        return try material(from: wallet)
        #else
        throw ImportError.engineUnavailable
        #endif
    }

    static func importMnemonic(_ mnemonic: String) throws -> WalletMaterial {
        #if canImport(WalletCore)
        guard let wallet = HDWallet(mnemonic: mnemonic, passphrase: "") else {
            throw ImportError.invalidMnemonic
        }
        return try material(from: wallet)
        #else
        throw ImportError.engineUnavailable
        #endif
    }

    static func importPrivateKey(_ privateKey: String, chainID: String = supportedChainID) throws -> WalletMaterial {
        #if canImport(WalletCore)
        guard let keyData = decodedPrivateKey(privateKey), let key = PrivateKey(data: keyData) else {
            throw ImportError.invalidPrivateKey
        }

        guard let network = WalletNetwork(rawValue: chainID) else {
            throw ImportError.invalidPrivateKey
        }

        let address: String
        switch network {
        case .bitcoin:
            address = CoinType.bitcoin.deriveAddress(privateKey: key)
        case .ethereum:
            address = CoinType.ethereum.deriveAddress(privateKey: key)
        case .solana:
            address = CoinType.solana.deriveAddress(privateKey: key)
        }
        guard !address.isEmpty else {
            throw ImportError.noAddress
        }

        return WalletMaterial(
            mnemonic: "",
            privateKey: privateKey,
            primaryAddress: address,
            chains: [chain(network: network, address: address, derivationPath: "Imported private key")],
            engine: "Unite Core"
        )
        #else
        throw ImportError.engineUnavailable
        #endif
    }

    static func validateAddress(_ address: String, chainID: String = supportedChainID) -> Bool {
        #if canImport(WalletCore)
        guard let network = WalletNetwork(rawValue: chainID) else { return false }
        switch network {
        case .bitcoin:
            return CoinType.bitcoin.validate(address: address)
        case .ethereum:
            return CoinType.ethereum.validate(address: address)
        case .solana:
            return CoinType.solana.validate(address: address)
        }
        #else
        return false
        #endif
    }

    static func signingContext(mnemonic: String, privateKey: String, chain: WalletChain) -> WalletSigningContext {
        WalletSigningContext(mnemonic: mnemonic, privateKey: privateKey, chain: chain)
    }

    static func resolveImportedMnemonicMaterial(_ material: WalletMaterial) async -> WalletMaterial {
        guard !material.mnemonic.isEmpty else { return material }
        guard let wallet = HDWallet(mnemonic: material.mnemonic, passphrase: "") else { return material }
        guard let solanaIndex = material.chains.firstIndex(where: { $0.id == WalletNetwork.solana.rawValue }) else { return material }

        let candidates = uniqueSolanaCandidates(from: wallet, current: material.chains[solanaIndex])
        guard candidates.count > 1 else { return material }

        var bestChain = material.chains[solanaIndex]
        var bestBalance = Decimal.zero

        await withTaskGroup(of: (WalletChain, Decimal?).self) { group in
            for chain in candidates {
                group.addTask {
                    let balance = try? await solanaBalance(address: chain.address)
                    return (chain, balance)
                }
            }

            for await (chain, balance) in group {
                guard let balance, balance > bestBalance else { continue }
                bestChain = chain
                bestBalance = balance
            }
        }

        guard bestChain != material.chains[solanaIndex] else { return material }

        var chains = material.chains
        chains[solanaIndex] = bestChain
        return WalletMaterial(
            mnemonic: material.mnemonic,
            privateKey: material.privateKey,
            primaryAddress: bestChain.address,
            chains: chains,
            engine: material.engine
        )
    }

    static func service(for chainID: String) -> ChainTransactionService? {
        guard let network = WalletNetwork(rawValue: chainID) else { return nil }
        switch network {
        case .bitcoin:
            return BitcoinTransactionAdapter()
        case .ethereum:
            return EthereumTransactionAdapter()
        case .solana:
            return SolanaTransactionAdapter()
        }
    }

    static func defaultAssets(for chains: [WalletChain]) -> [WalletAssetBalance] {
        chains.compactMap { chain in
            guard let network = chain.network else { return nil }
            return WalletAssetBalance(
                chainID: chain.id,
                symbol: network.symbol,
                name: network.displayName,
                decimals: network.decimals,
                balance: 0,
                isNative: true,
                contractAddress: nil,
                tokenStandard: .native,
                accountAddress: chain.address
            )
        }
    }

    #if canImport(WalletCore)
    static func privateKeyData(for signing: WalletSigningContext) throws -> Data {
        let cleanedMnemonic = signing.mnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedMnemonic.isEmpty {
            guard let wallet = HDWallet(mnemonic: cleanedMnemonic, passphrase: "") else {
                throw ImportError.invalidMnemonic
            }
            let derivationPath = signing.chain.derivationPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if derivationPath.hasPrefix("m/") {
                return try wallet.getKey(coin: coinType(for: signing.chain), derivationPath: derivationPath).data
            }
            return try wallet.getKeyForCoin(coin: coinType(for: signing.chain)).data
        }

        guard let key = decodedPrivateKey(signing.privateKey) else {
            throw TransactionServiceError.missingKey
        }
        return key
    }

    static func publicKeyData(for signing: WalletSigningContext) throws -> Data {
        guard let key = PrivateKey(data: try privateKeyData(for: signing)) else {
            throw TransactionServiceError.missingKey
        }
        return key.getPublicKeySecp256k1(compressed: false).data
    }

    static func keccak256(_ data: Data) -> Data {
        let input = TWDataCreateWithNSData(data)
        defer { TWDataDelete(input) }
        return TWDataNSData(TWHashKeccak256(input))
    }

    static func recoverPublicKey(signature: Data, message: Data) -> Data? {
        let signatureData = TWDataCreateWithNSData(signature)
        let messageData = TWDataCreateWithNSData(message)
        defer {
            TWDataDelete(signatureData)
            TWDataDelete(messageData)
        }
        guard let recovered = TWPublicKeyRecover(signatureData, messageData) else {
            return nil
        }
        defer { TWPublicKeyDelete(recovered) }
        return TWDataNSData(TWPublicKeyData(recovered))
    }

    private static func material(from wallet: HDWallet) throws -> WalletMaterial {
        let chains = WalletNetwork.allCases.compactMap { network -> WalletChain? in
            let coinType = coinType(for: network)

            let address = wallet.getAddressForCoin(coin: coinType)
            guard !address.isEmpty else { return nil }
            return chain(network: network, address: address, derivationPath: coinType.derivationPath())
        }

        guard let primaryChain = chains.first(where: { $0.id == WalletNetwork.solana.rawValue }) ?? chains.first else {
            throw ImportError.noAddress
        }

        let walletPrivateKey = wallet.getKeyForCoin(coin: .ethereum).data.hexString
        return WalletMaterial(
            mnemonic: wallet.mnemonic,
            privateKey: walletPrivateKey,
            primaryAddress: primaryChain.address,
            chains: chains,
            engine: "Unite Core"
        )
    }

    private static func coinType(for chain: WalletChain) throws -> CoinType {
        guard let network = chain.network else {
            throw TransactionServiceError.unsupportedNetwork
        }
        return coinType(for: network)
    }

    private static func coinType(for network: WalletNetwork) -> CoinType {
        switch network {
        case .bitcoin: return .bitcoin
        case .ethereum: return .ethereum
        case .solana: return .solana
        }
    }

    private static func decodedPrivateKey(_ privateKey: String) -> Data? {
        let cleaned = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if let hex = Data(hexString: cleaned) {
            if hex.count == 32 { return hex }
            if hex.count > 32 { return Data(hex.prefix(32)) }
        }

        if let base58 = Base58.decodeNoCheck(string: cleaned) ?? Base58.decode(string: cleaned) {
            if base58.count == 32 { return base58 }
            if base58.count > 32 { return Data(base58.prefix(32)) }
        }

        return nil
    }
    #endif

    private static func chain(network: WalletNetwork, address: String, derivationPath: String) -> WalletChain {
        WalletChain(
            id: network.rawValue,
            name: network.displayName,
            symbol: network.symbol,
            address: address,
            derivationPath: derivationPath,
            standards: network.derivationStandard
        )
    }

    #if canImport(WalletCore)
    private static func uniqueSolanaCandidates(from wallet: HDWallet, current: WalletChain) -> [WalletChain] {
        let paths = [
            current.derivationPath,
            CoinType.solana.derivationPath(),
            "m/44'/501'/0'/0'",
            "m/44'/501'/0'"
        ]

        var seen = Set<String>()
        var chains: [WalletChain] = []

        for path in paths where seen.insert(path).inserted {
            let address: String
            if path == CoinType.solana.derivationPath() {
                address = wallet.getAddressForCoin(coin: .solana)
            } else {
                let key = wallet.getKey(coin: .solana, derivationPath: path)
                guard let privateKey = PrivateKey(data: key.data) else { continue }
                address = CoinType.solana.deriveAddress(privateKey: privateKey)
            }

            guard !address.isEmpty else { continue }
            chains.append(chain(network: .solana, address: address, derivationPath: path))
        }

        return chains
    }

    private static func solanaBalance(address: String) async throws -> Decimal {
        let request = JSONRPCRequest(method: "getBalance", params: [address, ["commitment": "confirmed"]])
        let result = try await postJSONRPC(request, url: WalletNetwork.solana.rpcURL, responseType: SolanaBalanceResponse.self)
        return Decimal(result.result.value) / Decimal(1_000_000_000)
    }

    private static func postJSONRPC<Response: Decodable>(_ request: JSONRPCRequest, url: URL, responseType: Response.Type) async throws -> Response {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try decodeJSONRPCResponse(data, as: Response.self)
    }
    #endif
}

private struct BitcoinTransactionAdapter: ChainTransactionService {
    let network: WalletNetwork = .bitcoin

    func quote(draft: TransferDraft, asset: WalletAssetBalance, sourceChain: WalletChain, signing: WalletSigningContext) async throws -> TransferQuote {
        guard draft.amount > 0 else { throw TransactionServiceError.invalidAmount }
        guard WalletCoreBridge.validateAddress(draft.recipient, chainID: network.rawValue) else { throw TransactionServiceError.invalidRecipient }
        guard asset.isNative else { throw TransactionServiceError.unsupportedAsset }

        let utxos = try await fetchUTXOs(address: sourceChain.address)
        let feeRate = try await feeRateSatsPerByte()
        let totalAvailable = utxos.reduce(Decimal.zero) { $0 + Decimal($1.value) / Decimal(100_000_000) }
        let fee = Decimal(Int(max(2, feeRate)) * 225) / Decimal(100_000_000)
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

    func send(review: TransferReview, signing: WalletSigningContext) async throws -> BroadcastReceipt {
        #if canImport(WalletCore)
        let utxos = try await fetchUTXOs(address: signing.chain.address)
        let feeRate = try await feeRateSatsPerByte()
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

        var request = URLRequest(url: network.rpcURL.appending(path: "tx"))
        request.httpMethod = "POST"
        request.httpBody = output.encoded
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw TransactionServiceError.broadcastFailed(String(data: data, encoding: .utf8) ?? "Bitcoin broadcast failed.")
        }

        let txHash = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return BroadcastReceipt(
            chainID: network.rawValue,
            txHash: txHash?.isEmpty == false ? txHash! : output.transactionID,
            submittedAt: Date(),
            explorerURL: URL(string: "https://blockstream.info/tx/\(txHash ?? output.transactionID)")
        )
        #else
        throw TransactionServiceError.signingUnavailable
        #endif
    }

    func discoverAssets(for chain: WalletChain) async throws -> [WalletAssetBalance] {
        let snapshot = try await fetchAddressSnapshot(address: chain.address)
        let sats = snapshot.chainStats.fundedTxoSum - snapshot.chainStats.spentTxoSum + snapshot.mempoolStats.fundedTxoSum - snapshot.mempoolStats.spentTxoSum
        return [
            WalletAssetBalance(
                chainID: chain.id,
                symbol: network.symbol,
                name: network.displayName,
                decimals: network.decimals,
                balance: Decimal(sats) / Decimal(100_000_000),
                isNative: true,
                contractAddress: nil,
                tokenStandard: .native,
                accountAddress: chain.address
            )
        ]
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

        input.utxo = try utxos.map { utxo in
            let txHashData = Data(hexString: utxo.txid)?.reversedData() ?? Data()
            let script = BitcoinScript.lockScriptForAddress(address: changeAddress, coin: .bitcoin)
            return try BitcoinUnspentTransaction.with {
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

    private func fetchAddressSnapshot(address: String) async throws -> BlockstreamAddressPayload {
        let url = network.rpcURL.appending(path: "address/\(address)")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(BlockstreamAddressPayload.self, from: data)
    }

    private func fetchUTXOs(address: String) async throws -> [BlockstreamUTXO] {
        let url = network.rpcURL.appending(path: "address/\(address)/utxo")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([BlockstreamUTXO].self, from: data)
    }

    private func feeRateSatsPerByte() async throws -> Double {
        let url = network.rpcURL.appending(path: "fee-estimates")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode([String: Double].self, from: data)
        return payload["3"] ?? payload["6"] ?? 5
    }
}

private struct EthereumTransactionAdapter: ChainTransactionService {
    let network: WalletNetwork = .ethereum

    func quote(draft: TransferDraft, asset: WalletAssetBalance, sourceChain: WalletChain, signing: WalletSigningContext) async throws -> TransferQuote {
        guard draft.amount > 0 else { throw TransactionServiceError.invalidAmount }
        guard WalletCoreBridge.validateAddress(draft.recipient, chainID: network.rawValue) else { throw TransactionServiceError.invalidRecipient }

        let fees = try await feeComponents()
        let gasLimit = asset.isNative ? Decimal(21_000) : Decimal(65_000)
        let maxFeeWei = fees.maxFeePerGas
        let feeWei = gasLimit * Decimal(maxFeeWei)
        let fee = feeWei / pow10(18)
        let totalDebit = asset.isNative ? draft.amount + fee : draft.amount

        if asset.isNative && asset.balance < totalDebit {
            throw TransactionServiceError.insufficientFunds
        }

        return TransferQuote(
            asset: asset,
            fee: fee,
            feeSymbol: network.feeSymbol,
            totalDebit: totalDebit,
            networkDetail: "max \(weiToGwei(maxFeeWei).formattedString(maxFractionDigits: 2)) gwei",
            editableFee: true
        )
    }

    func send(review: TransferReview, signing: WalletSigningContext) async throws -> BroadcastReceipt {
        #if canImport(WalletCore)
        let asset = review.quote.asset
        let nonce = try await nonce(address: signing.chain.address)
        let fees = try await feeComponents()
        let gasLimit: UInt64 = asset.isNative ? 21_000 : 65_000
        let keyData = try WalletCoreBridge.privateKeyData(for: signing)

        let output = try sign(
            asset: asset,
            review: review,
            nonce: nonce,
            maxFeePerGas: fees.maxFeePerGas,
            priorityFeePerGas: fees.priorityFeePerGas,
            gasLimit: gasLimit,
            keyData: keyData
        )

        let txHash = try await broadcast(rawTransaction: output.encoded.hexString.prefixed0x)
        return BroadcastReceipt(
            chainID: network.rawValue,
            txHash: txHash,
            submittedAt: Date(),
            explorerURL: URL(string: "https://etherscan.io/tx/\(txHash)")
        )
        #else
        throw TransactionServiceError.signingUnavailable
        #endif
    }

    func discoverAssets(for chain: WalletChain) async throws -> [WalletAssetBalance] {
        var assets: [WalletAssetBalance] = [
            WalletAssetBalance(
                chainID: chain.id,
                symbol: network.symbol,
                name: network.displayName,
                decimals: network.decimals,
                balance: try await nativeBalance(address: chain.address),
                isNative: true,
                contractAddress: nil,
                tokenStandard: .native,
                accountAddress: chain.address
            )
        ]

        for token in network.tokenRegistry {
            let balance = try await erc20Balance(address: chain.address, token: token)
            if balance > 0 {
                assets.append(
                    WalletAssetBalance(
                        chainID: chain.id,
                        symbol: token.symbol,
                        name: token.name,
                        decimals: token.decimals,
                        balance: balance,
                        isNative: false,
                        contractAddress: token.contractAddress,
                        tokenStandard: token.tokenStandard,
                        accountAddress: chain.address
                    )
                )
            }
        }

        return assets
    }

    #if canImport(WalletCore)
    private func sign(
        asset: WalletAssetBalance,
        review: TransferReview,
        nonce: UInt64,
        maxFeePerGas: UInt64,
        priorityFeePerGas: UInt64,
        gasLimit: UInt64,
        keyData: Data
    ) throws -> EthereumSigningOutput {
        var input = EthereumSigningInput.with {
            $0.chainID = Data([0x01])
            $0.nonce = Data.hexUInt64(nonce)
            $0.gasLimit = Data.hexUInt64(gasLimit)
            $0.maxFeePerGas = Data.hexUInt64(maxFeePerGas)
            $0.maxInclusionFeePerGas = Data.hexUInt64(priorityFeePerGas)
            $0.txMode = .enveloped
            $0.privateKey = keyData
        }

        if asset.isNative {
            let transferAmount = try review.draft.amount
                .smallestUnit(decimals: 18)
                .ethereumQuantityData()
            input.toAddress = review.draft.recipient
            input.transaction = EthereumTransaction.with {
                $0.transfer = EthereumTransaction.Transfer.with {
                    $0.amount = transferAmount
                }
            }
        } else {
            guard let contract = asset.contractAddress else { throw TransactionServiceError.unsupportedAsset }
            let tokenAmount = try review.draft.amount
                .smallestUnit(decimals: asset.decimals)
                .ethereumQuantityData()
            input.toAddress = contract
            input.transaction = EthereumTransaction.with {
                $0.erc20Transfer = EthereumTransaction.ERC20Transfer.with {
                    $0.to = review.draft.recipient
                    $0.amount = tokenAmount
                }
            }
        }

        return AnySigner.sign(input: input, coin: .ethereum)
    }
    #endif

    private func nativeBalance(address: String) async throws -> Decimal {
        let response: EthereumBalanceResponse = try await post(request: .init(method: "eth_getBalance", params: [address, "latest"]))
        return Decimal(hexString: response.result) / pow10(network.decimals)
    }

    private func erc20Balance(address: String, token: WalletAssetToken) async throws -> Decimal {
        guard let contract = token.contractAddress else { return 0 }
        let callObject: [String: String] = [
            "to": contract,
            "data": "0x70a08231" + address.stripHexPrefix.leftPadded(to: 64)
        ]
        let response: EthereumBalanceResponse = try await post(request: .init(method: "eth_call", params: [callObject, "latest"]))
        return Decimal(hexString: response.result) / pow10(token.decimals)
    }

    private func nonce(address: String) async throws -> UInt64 {
        let response: EthereumBalanceResponse = try await post(request: .init(method: "eth_getTransactionCount", params: [address, "pending"]))
        return UInt64(hexString: response.result) ?? 0
    }

    private func feeComponents() async throws -> EthereumFeeComponents {
        let gas: EthereumBalanceResponse = try await post(request: .init(method: "eth_gasPrice", params: []))
        let block: EthereumBlockResponse = try await post(request: .init(method: "eth_getBlockByNumber", params: ["latest", false]))
        let priority: EthereumBalanceResponse = try await post(request: .init(method: "eth_maxPriorityFeePerGas", params: []))
        let baseFee = UInt64(hexString: block.result.baseFeePerGas ?? gas.result) ?? 0
        let priorityFee = UInt64(hexString: priority.result) ?? 1_500_000_000
        let maxFee = max(baseFee * 2 + priorityFee, UInt64(hexString: gas.result) ?? priorityFee)
        return EthereumFeeComponents(maxFeePerGas: maxFee, priorityFeePerGas: priorityFee)
    }

    private func broadcast(rawTransaction: String) async throws -> String {
        let response: EthereumBalanceResponse = try await post(request: .init(method: "eth_sendRawTransaction", params: [rawTransaction]))
        guard response.result.hasPrefix("0x") else {
            throw TransactionServiceError.broadcastFailed("Ethereum broadcast failed.")
        }
        return response.result
    }

    private func post<Response: Decodable>(request: JSONRPCRequest) async throws -> Response {
        var urlRequest = URLRequest(url: network.rpcURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try decodeJSONRPCResponse(data, as: Response.self)
    }
}

private func decodeJSONRPCResponse<Response: Decodable>(_ data: Data, as type: Response.Type) throws -> Response {
    do {
        return try JSONDecoder().decode(Response.self, from: data)
    } catch {
        if let rpcError = try? JSONDecoder().decode(JSONRPCErrorResponse.self, from: data) {
            throw TransactionServiceError.rpcError("RPC error \(rpcError.error.code): \(rpcError.error.message)")
        }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw TransactionServiceError.rpcError(raw?.isEmpty == false ? raw! : "Unexpected RPC response.")
    }
}

private struct SolanaTransactionAdapter: ChainTransactionService {
    let network: WalletNetwork = .solana

    func quote(draft: TransferDraft, asset: WalletAssetBalance, sourceChain: WalletChain, signing: WalletSigningContext) async throws -> TransferQuote {
        guard draft.amount > 0 else { throw TransactionServiceError.invalidAmount }
        guard WalletCoreBridge.validateAddress(draft.recipient, chainID: network.rawValue) else { throw TransactionServiceError.invalidRecipient }

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

    func send(review: TransferReview, signing: WalletSigningContext) async throws -> BroadcastReceipt {
        #if canImport(WalletCore)
        let asset = review.quote.asset
        let blockhash: String
        do {
            blockhash = try await recentBlockhash()
        } catch let error as TransactionServiceError {
            throw error
        } catch {
            throw TransactionServiceError.broadcastFailed("Solana blockhash fetch failed: \(error.localizedDescription)")
        }

        let keyData: Data
        do {
            keyData = try WalletCoreBridge.privateKeyData(for: signing)
        } catch let error as TransactionServiceError {
            throw error
        } catch {
            throw TransactionServiceError.broadcastFailed("Solana key load failed: \(error.localizedDescription)")
        }

        let output: SolanaSigningOutput
        do {
            output = try sign(asset: asset, review: review, signing: signing, blockhash: blockhash, keyData: keyData)
        } catch let error as TransactionServiceError {
            throw error
        } catch {
            throw TransactionServiceError.broadcastFailed("Solana signing failed: \(error.localizedDescription)")
        }

        let signature: String
        do {
            signature = try await broadcast(base64Transaction: output.encoded)
        } catch let error as TransactionServiceError {
            throw error
        } catch {
            throw TransactionServiceError.broadcastFailed("Solana broadcast failed: \(error.localizedDescription)")
        }

        return BroadcastReceipt(
            chainID: network.rawValue,
            txHash: signature,
            submittedAt: Date(),
            explorerURL: URL(string: "https://solscan.io/tx/\(signature)")
        )
        #else
        throw TransactionServiceError.signingUnavailable
        #endif
    }

    func discoverAssets(for chain: WalletChain) async throws -> [WalletAssetBalance] {
        var assets: [WalletAssetBalance] = [
            WalletAssetBalance(
                chainID: chain.id,
                symbol: network.symbol,
                name: network.displayName,
                decimals: network.decimals,
                balance: try await nativeBalance(address: chain.address),
                isNative: true,
                contractAddress: nil,
                tokenStandard: .native,
                accountAddress: chain.address
            )
        ]

        let tokenAccounts = try await splAccounts(owner: chain.address)
        for token in network.tokenRegistry {
            guard let match = tokenAccounts.first(where: { $0.account.data.parsed.info.mint == token.contractAddress }) else { continue }
            let amount = Decimal(string: match.account.data.parsed.info.tokenAmount.uiAmountString) ?? 0
            if amount > 0 {
                assets.append(
                    WalletAssetBalance(
                        chainID: chain.id,
                        symbol: token.symbol,
                        name: token.name,
                        decimals: token.decimals,
                        balance: amount,
                        isNative: false,
                        contractAddress: token.contractAddress,
                        tokenStandard: token.tokenStandard,
                        accountAddress: match.pubkey
                    )
                )
            }
        }

        return assets
    }

    #if canImport(WalletCore)
    private func sign(asset: WalletAssetBalance, review: TransferReview, signing: WalletSigningContext, blockhash: String, keyData: Data) throws -> SolanaSigningOutput {
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
            throw TransactionServiceError.broadcastFailed(output.errorMessage.isEmpty ? "Solana signing failed." : output.errorMessage)
        }
        return output
    }
    #endif

    private func nativeBalance(address: String) async throws -> Decimal {
        let response: SolanaBalanceResponse = try await post(request: .init(method: "getBalance", params: [address, ["commitment": "confirmed"]]))
        return Decimal(response.result.value) / pow10(network.decimals)
    }

    private func recentBlockhash() async throws -> String {
        let response: SolanaBlockhashResponse = try await post(request: .init(method: "getLatestBlockhash", params: [["commitment": "confirmed"]]))
        return response.result.value.blockhash
    }

    private func splAccounts(owner: String) async throws -> [SolanaTokenAccount] {
        let params: [AnyEncodable] = [
            AnyEncodable(owner),
            AnyEncodable(["programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"]),
            AnyEncodable(["encoding": "jsonParsed", "commitment": "confirmed"])
        ]
        let response: SolanaTokenAccountsResponse = try await post(request: JSONRPCRequest(method: "getTokenAccountsByOwner", params: params))
        return response.result.value
    }

    private func broadcast(base64Transaction: String) async throws -> String {
        let params: [AnyEncodable] = [
            AnyEncodable(base64Transaction),
            AnyEncodable(["encoding": "base64", "skipPreflight": false, "preflightCommitment": "confirmed"])
        ]
        let response: SolanaSignatureResponse = try await post(request: JSONRPCRequest(method: "sendTransaction", params: params))
        return response.result
    }

    private func post<Response: Decodable>(request: JSONRPCRequest) async throws -> Response {
        var urlRequest = URLRequest(url: network.rpcURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try decodeJSONRPCResponse(data, as: Response.self)
    }
}

private struct EthereumFeeComponents {
    let maxFeePerGas: UInt64
    let priorityFeePerGas: UInt64
}

struct BlockstreamUTXO: Decodable, Equatable {
    let txid: String
    let vout: Int
    let value: Int64
}

struct EthereumBlockResponse: Decodable {
    let result: EthereumBlockPayload
}

struct EthereumBlockPayload: Decodable {
    let baseFeePerGas: String?
}

struct SolanaBlockhashResponse: Decodable {
    let result: SolanaBlockhashValue
}

struct SolanaBlockhashValue: Decodable {
    let value: SolanaBlockhashInner
}

struct SolanaBlockhashInner: Decodable {
    let blockhash: String
}

struct JSONRPCErrorResponse: Decodable {
    let error: JSONRPCErrorPayload
}

struct JSONRPCErrorPayload: Decodable {
    let code: Int
    let message: String
}

struct SolanaSignatureResponse: Decodable {
    let result: String
}

struct SolanaTokenAccountsResponse: Decodable {
    let result: SolanaTokenAccountsValue
}

struct SolanaTokenAccountsValue: Decodable {
    let value: [SolanaTokenAccount]
}

struct SolanaTokenAccount: Decodable {
    let pubkey: String
    let account: SolanaTokenAccountInfo
}

struct SolanaTokenAccountInfo: Decodable {
    let data: SolanaTokenAccountData
}

struct SolanaTokenAccountData: Decodable {
    let parsed: SolanaParsedTokenData
}

struct SolanaParsedTokenData: Decodable {
    let info: SolanaParsedTokenInfo
}

struct SolanaParsedTokenInfo: Decodable {
    let mint: String
    let tokenAmount: SolanaTokenAmount
}

struct SolanaTokenAmount: Decodable {
    let uiAmountString: String
}

private func pow10(_ power: Int) -> Decimal {
    Decimal(sign: .plus, exponent: power, significand: 1)
}

private func weiToGwei(_ value: UInt64) -> Decimal {
    Decimal(value) / Decimal(1_000_000_000)
}

private extension Decimal {
    func smallestUnit(decimals: Int) throws -> Int64 {
        guard self > 0 else { throw TransactionServiceError.invalidAmount }
        let scaled = self * pow10(decimals)
        let rounded = NSDecimalNumber(decimal: scaled).rounding(accordingToBehavior: nil)
        return rounded.int64Value
    }
}

private extension Int64 {
    func ethereumQuantityData() -> Data {
        let hex = String(self, radix: 16)
        return Data(hexString: hex.leftPaddedToEvenLength) ?? Data()
    }
}

private extension UInt64 {
    init?(hexString: String) {
        self.init(hexString.stripHexPrefix, radix: 16)
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    static func hexUInt64(_ value: UInt64) -> Data {
        Data(hexString: String(value, radix: 16).leftPaddedToEvenLength) ?? Data()
    }

    func reversedData() -> Data {
        Data(reversed())
    }
}

private extension String {
    var stripHexPrefix: String {
        hasPrefix("0x") ? String(dropFirst(2)) : self
    }

    var prefixed0x: String {
        hasPrefix("0x") ? self : "0x\(self)"
    }

    func leftPadded(to count: Int) -> String {
        if self.count >= count { return self }
        return String(repeating: "0", count: count - self.count) + self
    }

    var leftPaddedToEvenLength: String {
        count.isMultiple(of: 2) ? self : "0\(self)"
    }
}
