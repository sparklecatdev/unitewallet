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
        network?.keyCurve ?? "Unknown"
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

enum WalletChainFamily: String, Codable {
    case utxo
    case evm
    case solana
    case tron
    case ton
}

enum WalletNetwork: String, CaseIterable, Codable, Identifiable {
    case bitcoin
    case ethereum
    case bsc
    case polygon
    case arbitrum
    case optimism
    case avalancheC = "avalanche_c"
    case base
    case gnosis
    case fantom
    case solana

    var id: String { rawValue }

    var family: WalletChainFamily {
        switch self {
        case .bitcoin:
            return .utxo
        case .ethereum, .bsc, .polygon, .arbitrum, .optimism, .avalancheC, .base, .gnosis, .fantom:
            return .evm
        case .solana:
            return .solana
        }
    }

    var keyCurve: String {
        switch family {
        case .utxo, .evm:
            return "secp256k1"
        case .solana:
            return "Ed25519"
        case .tron, .ton:
            return "Unknown"
        }
    }

    var displayName: String {
        switch self {
        case .bitcoin: "Bitcoin"
        case .ethereum: "Ethereum"
        case .bsc: "BNB Smart Chain"
        case .polygon: "Polygon"
        case .arbitrum: "Arbitrum One"
        case .optimism: "Optimism"
        case .avalancheC: "Avalanche C-Chain"
        case .base: "Base"
        case .gnosis: "Gnosis"
        case .fantom: "Fantom"
        case .solana: "Solana"
        }
    }

    var symbol: String {
        switch self {
        case .bitcoin: "BTC"
        case .ethereum: "ETH"
        case .bsc: "BNB"
        case .polygon: "MATIC"
        case .arbitrum, .optimism, .base: "ETH"
        case .avalancheC: "AVAX"
        case .gnosis: "XDAI"
        case .fantom: "FTM"
        case .solana: "SOL"
        }
    }

    var derivationStandard: String {
        switch self {
        case .bitcoin:
            return "BIP44 / secp256k1"
        case .ethereum, .bsc, .polygon, .arbitrum, .optimism, .avalancheC, .base, .gnosis, .fantom:
            return "BIP44 / secp256k1"
        case .solana:
            return "SLIP-0010 / Ed25519"
        }
    }

    var coinGeckoID: String {
        switch self {
        case .bitcoin: "bitcoin"
        case .ethereum, .arbitrum, .optimism, .base: "ethereum"
        case .bsc: "binancecoin"
        case .polygon: "matic-network"
        case .avalancheC: "avalanche-2"
        case .gnosis: "xdai"
        case .fantom: "fantom"
        case .solana: "solana"
        }
    }

    var fractionDigits: Int {
        switch self {
        case .bitcoin:
            return 8
        case .ethereum, .bsc, .polygon, .arbitrum, .optimism, .avalancheC, .base, .gnosis, .fantom, .solana:
            return 6
        }
    }

    var decimals: Int {
        switch self {
        case .bitcoin:
            return 8
        case .ethereum, .bsc, .polygon, .arbitrum, .optimism, .avalancheC, .base, .gnosis, .fantom:
            return 18
        case .solana:
            return 9
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
        case .bsc:
            return URL(string: "https://bsc-dataseed.binance.org")!
        case .polygon:
            return URL(string: "https://polygon-rpc.com")!
        case .arbitrum:
            return URL(string: "https://arb1.arbitrum.io/rpc")!
        case .optimism:
            return URL(string: "https://mainnet.optimism.io")!
        case .avalancheC:
            return URL(string: "https://api.avax.network/ext/bc/C/rpc")!
        case .base:
            return URL(string: "https://mainnet.base.org")!
        case .gnosis:
            return URL(string: "https://rpc.gnosischain.com")!
        case .fantom:
            return URL(string: "https://rpc.ftm.tools")!
        case .solana:
            return URL(string: "https://api.mainnet-beta.solana.com")!
        }
    }

    var explorerBase: String {
        switch self {
        case .bitcoin:
            return "https://blockstream.info"
        case .ethereum:
            return "https://etherscan.io"
        case .bsc:
            return "https://bscscan.com"
        case .polygon:
            return "https://polygonscan.com"
        case .arbitrum:
            return "https://arbiscan.io"
        case .optimism:
            return "https://optimistic.etherscan.io"
        case .avalancheC:
            return "https://snowtrace.io"
        case .base:
            return "https://basescan.org"
        case .gnosis:
            return "https://gnosisscan.io"
        case .fantom:
            return "https://ftmscan.com"
        case .solana:
            return "https://solscan.io"
        }
    }

    var caipNamespace: String {
        switch self {
        case .bitcoin:
            return "bip122"
        case .ethereum, .bsc, .polygon, .arbitrum, .optimism, .avalancheC, .base, .gnosis, .fantom:
            return "eip155"
        case .solana:
            return "solana"
        }
    }

    var caipReference: String {
        switch self {
        case .bitcoin:
            return "000000000019d6689c085ae165831e93"
        case .ethereum:
            return "1"
        case .bsc:
            return "56"
        case .polygon:
            return "137"
        case .arbitrum:
            return "42161"
        case .optimism:
            return "10"
        case .avalancheC:
            return "43114"
        case .base:
            return "8453"
        case .gnosis:
            return "100"
        case .fantom:
            return "250"
        case .solana:
            return "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"
        }
    }

    var evmChainID: UInt64? {
        guard family == .evm else { return nil }
        return UInt64(caipReference)
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
        case .bsc, .polygon, .arbitrum, .optimism, .avalancheC, .base, .gnosis, .fantom:
            return []
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

    static func deriveChains(mnemonic: String, chains: [WalletNetwork]) throws -> [WalletChain] {
        #if canImport(WalletCore)
        guard let wallet = HDWallet(mnemonic: mnemonic, passphrase: "") else {
            throw ImportError.invalidMnemonic
        }
        return chains.compactMap { network in
            let coin = coinType(for: network)
            let address = wallet.getAddressForCoin(coin: coin)
            guard !address.isEmpty else { return nil }
            return chain(network: network, address: address, derivationPath: coin.derivationPath())
        }
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

        let address = coinType(for: network).deriveAddress(privateKey: key)
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

    static func privateKeyChain(privateKey: String, chainID: String) throws -> WalletChain {
        let material = try importPrivateKey(privateKey, chainID: chainID)
        guard let chain = material.chains.first else {
            throw ImportError.noAddress
        }
        return chain
    }

    static func validateAddress(_ address: String, chainID: String = supportedChainID) -> Bool {
        #if canImport(WalletCore)
        guard let network = WalletNetwork(rawValue: chainID) else { return false }
        return coinType(for: network).validate(address: address)
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
        case .ethereum, .bsc, .polygon, .arbitrum, .optimism, .avalancheC, .base, .gnosis, .fantom:
            return .ethereum
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
        var urlRequest = URLRequest(url: WalletNetwork.solana.rpcURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let result = try JSONDecoder().decode(SolanaBalanceResponse.self, from: data)
        return Decimal(result.result.value) / Decimal(1_000_000_000)
    }
    #endif
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

private func weiToGwei(_ value: UInt64) -> Decimal {
    Decimal(value) / Decimal(1_000_000_000)
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
