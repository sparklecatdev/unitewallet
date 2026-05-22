import Foundation

@MainActor
final class WalletStore: ObservableObject {
    enum SecureKey {
        static let mnemonic = "wallet.mnemonic"
        static let privateKey = "wallet.privateKey"
    }

    enum SupportResource {
        static let email = "support@unitewallet.app"
        static let privacyURL = URL(string: "https://unitewallet.app/privacy")!
        static let termsURL = URL(string: "https://unitewallet.app/terms")!
        static let feedbackURL = URL(string: "https://unitewallet.app/beta-feedback")!
    }

    @Published var hasWallet: Bool
    @Published var backupConfirmed: Bool
    @Published var address: String
    @Published var mnemonic: String
    @Published var privateKey: String
    @Published var importType: String
    @Published var walletEngine: String
    @Published var chains: [WalletChain]
    @Published var primaryChainID: String
    @Published var chainStates: [String: ChainBalanceSnapshot]
    @Published var isRefreshingChains = false
    @Published var diagnosticsEnabled: Bool
    @Published var biometricLockEnabled: Bool
    @Published var contacts: [WalletContact]
    @Published var balanceSOL: Double = 0
    @Published var marketAssets: [MarketAsset] = MarketAsset.defaults
    @Published var marketUpdatedAt: Date?
    @Published var marketMessage = "Read-only CoinGecko beta data"
    @Published var isRefreshingMarket = false
    @Published var marketAutoRefreshEnabled: Bool
    @Published var watchedMarketAssetIDs: Set<String>
    @Published var marketPriceAlerts: [MarketPriceAlert]
    @Published var isAppLocked: Bool
    @Published var unlockErrorMessage: String?

    private let defaults: UserDefaults
    private let secureStore: SecureStoring
    private let authenticator: DeviceAuthenticating
    private let chainDataProvider: ChainDataProviding

    init(
        defaults: UserDefaults = .standard,
        secureStore: SecureStoring = KeychainSecureStore.shared,
        authenticator: DeviceAuthenticating = DeviceSecurity.shared,
        chainDataProvider: ChainDataProviding = LiveChainDataProvider()
    ) {
        self.defaults = defaults
        self.secureStore = secureStore
        self.authenticator = authenticator
        self.chainDataProvider = chainDataProvider

        let initialHasWallet = defaults.bool(forKey: "unite.native.hasWallet")
        let initialBiometricLockEnabled = defaults.object(forKey: "unite.native.biometricLockEnabled") as? Bool ?? true

        hasWallet = initialHasWallet
        backupConfirmed = defaults.bool(forKey: "unite.native.backupConfirmed")
        address = defaults.string(forKey: "unite.native.address") ?? ""
        mnemonic = (try? secureStore.string(for: SecureKey.mnemonic)) ?? ""
        privateKey = (try? secureStore.string(for: SecureKey.privateKey)) ?? ""
        importType = defaults.string(forKey: "unite.native.importType") ?? "Generated"
        walletEngine = defaults.string(forKey: "unite.native.walletEngine") ?? "Not initialized"
        chains = Self.loadChains(from: defaults)
        primaryChainID = defaults.string(forKey: "unite.native.primaryChainID") ?? WalletNetwork.solana.rawValue
        chainStates = Self.loadChainStates(from: defaults)
        diagnosticsEnabled = defaults.bool(forKey: "unite.native.diagnosticsEnabled")
        biometricLockEnabled = initialBiometricLockEnabled
        contacts = Self.loadContacts(from: defaults)
        marketAutoRefreshEnabled = defaults.object(forKey: "unite.native.marketAutoRefreshEnabled") as? Bool ?? true
        watchedMarketAssetIDs = Set(defaults.stringArray(forKey: "unite.native.watchedMarketAssetIDs") ?? ["solana"])
        marketPriceAlerts = Self.loadMarketPriceAlerts(from: defaults)
        isAppLocked = initialHasWallet && initialBiometricLockEnabled

        clearLegacySecrets()

        if chains.isEmpty, !address.isEmpty {
            chains = [
                WalletChain(
                    id: WalletNetwork.solana.rawValue,
                    name: WalletNetwork.solana.displayName,
                    symbol: WalletNetwork.solana.symbol,
                    address: address,
                    derivationPath: "Existing secure wallet",
                    standards: WalletNetwork.solana.derivationStandard
                )
            ]
        }

        upgradeStoredChainsIfPossible()
        normalizePrimaryChain()
        balanceSOL = nativeBalance(for: WalletNetwork.solana.rawValue)
    }

    var shortAddress: String {
        let activeAddress = currentChain?.address ?? address
        guard activeAddress.count > 12 else { return activeAddress.isEmpty ? "No wallet" : activeAddress }
        return "\(activeAddress.prefix(5))...\(activeAddress.suffix(5))"
    }

    var visibleEngineName: String {
        walletEngine.isEmpty ? "Unite Core" : walletEngine
    }

    var currentChain: WalletChain? {
        chains.first(where: { $0.id == primaryChainID }) ?? chains.first
    }

    var portfolioValue: Double {
        chains.reduce(0) { partial, chain in
            partial + (fiatValue(for: chain) ?? 0)
        }
    }

    var supportedNetworksSummary: String {
        chains.map(\.symbol).joined(separator: " • ")
    }

    var chainSyncStateLabel: String {
        if isRefreshingChains { return "Syncing" }
        let states = chainStates.values.map(\.status)
        if states.contains(.failed) { return "Review" }
        if states.contains(.synced) { return "Live" }
        return hasWallet ? "Idle" : "Setup"
    }

    var lastChainSyncDetail: String {
        if let latest = chainStates.values.compactMap(\.updatedAt).max() {
            return "Balances updated \(latest.formatted(date: .omitted, time: .shortened))"
        }
        if isRefreshingChains {
            return "Fetching balances from live networks"
        }
        return "Pull to sync Bitcoin, Ethereum, and Solana balances"
    }

    var serviceStatuses: [WalletServiceStatus] {
        [
            .init(name: "Wallet security", detail: "Recovery material stays on this device", state: hasWallet ? "Ready" : "Setup"),
            .init(name: "Screen lock", detail: biometricLockEnabled ? "Sensitive views require device authentication" : "Turn on device authentication", state: biometricLockEnabled ? "On" : "Review"),
            .init(name: "Market data", detail: marketUpdatedAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Pull to refresh when you need it", state: "Read-only"),
            .init(name: "Network sync", detail: lastChainSyncDetail, state: chainSyncStateLabel)
        ]
    }

    var activities: [WalletActivity] {
        [
            .init(icon: "checkmark.seal", title: "Wallet ready", detail: "Your multichain wallet is available on this device with \(chains.count) supported networks.", amount: "", status: hasWallet ? "Ready" : "Setup"),
            .init(icon: "lock.shield", title: "Screen lock", detail: biometricLockEnabled ? "Recovery and wallet details stay behind device authentication." : "Turn on device authentication before wider testing.", amount: "", status: biometricLockEnabled ? "On" : "Review"),
            .init(icon: "key.viewfinder", title: "Backup reminder", detail: backupConfirmed ? "Your recovery material has been confirmed and can be reviewed later." : "Confirm your recovery material before moving funds.", amount: "", status: backupConfirmed ? "Saved" : "Action"),
            .init(icon: "arrow.trianglehead.2.clockwise", title: "Chain sync", detail: lastChainSyncDetail, amount: "", status: chainSyncStateLabel)
        ]
    }

    var notifications: [WalletNotification] {
        [
            .init(title: "Backup", detail: backupConfirmed ? "Your recovery material is available later behind device authentication." : "Confirm and store your recovery material offline before using the wallet.", severity: backupConfirmed ? "OK" : "Action"),
            .init(title: "What this build covers", detail: "This build derives Bitcoin, Ethereum, and Solana addresses from one recovery phrase and syncs native balances from live networks.", severity: "Guide"),
            .init(title: "Current send scope", detail: "Receive and balance sync are live across supported chains. Transaction sending still needs chain-specific signing and broadcast flows.", severity: "Note")
        ]
    }

    func createWallet() -> String? {
        do {
            let material = try WalletCoreBridge.createWallet()
            try apply(material: material, importType: "Generated", backupConfirmed: false)
            diagnostic("Created wallet.")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func importWallet(secret: String, asPrivateKey: Bool, privateKeyChainID: String = WalletNetwork.solana.rawValue) -> String? {
        let cleanSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSecret.isEmpty else {
            return "Enter a recovery phrase or private key."
        }

        do {
            if asPrivateKey {
                let material = try WalletCoreBridge.importPrivateKey(cleanSecret, chainID: privateKeyChainID)
                try apply(material: material, importType: "Private key", backupConfirmed: true)
            } else {
                let words = cleanSecret.split(whereSeparator: \.isWhitespace)
                guard [12, 15, 18, 21, 24].contains(words.count) else {
                    return "Recovery phrases are usually 12, 15, 18, 21, or 24 words."
                }
                let material = try WalletCoreBridge.importMnemonic(words.joined(separator: " "))
                try apply(material: material, importType: "Recovery phrase", backupConfirmed: true)
            }
            diagnostic("Imported wallet.")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func confirmBackup() {
        backupConfirmed = true
        defaults.set(true, forKey: "unite.native.backupConfirmed")
    }

    func setDiagnosticsEnabled(_ enabled: Bool) {
        diagnosticsEnabled = enabled
        defaults.set(enabled, forKey: "unite.native.diagnosticsEnabled")
    }

    func setBiometricLockEnabled(_ enabled: Bool) {
        biometricLockEnabled = enabled
        defaults.set(enabled, forKey: "unite.native.biometricLockEnabled")
        if !enabled {
            isAppLocked = false
            unlockErrorMessage = nil
        } else if hasWallet {
            isAppLocked = true
        }
        diagnostic("Biometric lock setting changed.")
    }

    func setMarketAutoRefreshEnabled(_ enabled: Bool) {
        marketAutoRefreshEnabled = enabled
        defaults.set(enabled, forKey: "unite.native.marketAutoRefreshEnabled")
    }

    func setPrimaryChain(_ chainID: String) {
        guard chains.contains(where: { $0.id == chainID }) else { return }
        primaryChainID = chainID
        address = currentChain?.address ?? address
        defaults.set(chainID, forKey: "unite.native.primaryChainID")
    }

    func lockApp() {
        guard hasWallet, biometricLockEnabled else { return }
        isAppLocked = true
        unlockErrorMessage = nil
    }

    func unlockApp() async -> Bool {
        guard hasWallet, biometricLockEnabled else {
            isAppLocked = false
            return true
        }

        do {
            let allowed = try await authenticator.authenticate(reason: "Unlock Unite Wallet to view recovery material and wallet details.")
            isAppLocked = !allowed
            unlockErrorMessage = allowed ? nil : "Authentication was cancelled."
            return allowed
        } catch {
            unlockErrorMessage = error.localizedDescription
            return false
        }
    }

    func isWatchingMarketAsset(_ asset: MarketAsset) -> Bool {
        watchedMarketAssetIDs.contains(asset.id)
    }

    func toggleMarketWatch(_ asset: MarketAsset) {
        if watchedMarketAssetIDs.contains(asset.id) {
            watchedMarketAssetIDs.remove(asset.id)
        } else {
            watchedMarketAssetIDs.insert(asset.id)
        }
        defaults.set(Array(watchedMarketAssetIDs), forKey: "unite.native.watchedMarketAssetIDs")
    }

    func priceAlert(for asset: MarketAsset) -> MarketPriceAlert? {
        marketPriceAlerts.first { $0.assetID == asset.id }
    }

    func setPriceAlert(asset: MarketAsset, targetPrice: Double) {
        marketPriceAlerts.removeAll { $0.assetID == asset.id }
        marketPriceAlerts.insert(.init(assetID: asset.id, symbol: asset.symbol, targetPrice: targetPrice), at: 0)
        persistMarketPriceAlerts()
    }

    func removePriceAlert(for asset: MarketAsset) {
        marketPriceAlerts.removeAll { $0.assetID == asset.id }
        persistMarketPriceAlerts()
    }

    func saveContact(name: String, address: String, chain: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedAddress.isEmpty else { return }
        contacts.removeAll { $0.address == trimmedAddress && $0.chain == chain }
        contacts.insert(.init(name: trimmedName, address: trimmedAddress, chain: chain), at: 0)
        persistContacts()
    }

    func removeContact(_ contact: WalletContact) {
        contacts.removeAll { $0.id == contact.id }
        persistContacts()
    }

    func removeWallet() {
        hasWallet = false
        backupConfirmed = false
        address = ""
        mnemonic = ""
        privateKey = ""
        importType = "Generated"
        walletEngine = "Not initialized"
        chains = []
        primaryChainID = WalletNetwork.solana.rawValue
        chainStates = [:]
        balanceSOL = 0
        isAppLocked = false
        unlockErrorMessage = nil
        defaults.removeObject(forKey: "unite.native.hasWallet")
        defaults.removeObject(forKey: "unite.native.backupConfirmed")
        defaults.removeObject(forKey: "unite.native.address")
        defaults.removeObject(forKey: "unite.native.importType")
        defaults.removeObject(forKey: "unite.native.walletEngine")
        defaults.removeObject(forKey: "unite.native.chains")
        defaults.removeObject(forKey: "unite.native.primaryChainID")
        defaults.removeObject(forKey: "unite.native.chainStates")
        defaults.removeObject(forKey: "unite.native.mnemonic")
        defaults.removeObject(forKey: "unite.native.privateKey")
        try? secureStore.removeValue(for: SecureKey.mnemonic)
        try? secureStore.removeValue(for: SecureKey.privateKey)
        diagnostic("Removed wallet.")
    }

    func refreshMarket() async {
        guard !isRefreshingMarket else { return }
        isRefreshingMarket = true
        defer { isRefreshingMarket = false }

        do {
            let ids = marketAssets.map(\.id).joined(separator: ",")
            var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")!
            components.queryItems = [
                URLQueryItem(name: "vs_currency", value: "usd"),
                URLQueryItem(name: "ids", value: ids),
                URLQueryItem(name: "order", value: "market_cap_desc"),
                URLQueryItem(name: "sparkline", value: "true"),
                URLQueryItem(name: "price_change_percentage", value: "1h,24h,7d"),
                URLQueryItem(name: "precision", value: "4")
            ]

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            let session = URLSession(configuration: configuration)
            let (data, response) = try await session.data(from: components.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let remote = try JSONDecoder().decode([CoinGeckoMarketAsset].self, from: data)
            let byID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
            marketAssets = marketAssets.map { asset in
                guard let item = byID[asset.id] else { return asset }
                return asset.updated(with: item)
            }
            marketUpdatedAt = Date()
            marketMessage = marketAutoRefreshEnabled ? "Read-only market sync is on." : "Market updated."
            diagnostic("Market refresh succeeded.")
        } catch {
            marketMessage = "Market data is temporarily unavailable."
            diagnostic("Market refresh failed.")
        }
    }

    func refreshChains() async {
        guard hasWallet, !isRefreshingChains else { return }
        isRefreshingChains = true
        defer {
            isRefreshingChains = false
            balanceSOL = nativeBalance(for: WalletNetwork.solana.rawValue)
        }

        let results = await chainDataProvider.fetchBalances(for: chains)
        for chain in chains {
            if let result = results[chain.id] {
                chainStates[chain.id] = result
            } else {
                chainStates[chain.id] = ChainBalanceSnapshot(balance: 0, updatedAt: nil, status: .failed, message: "Balance unavailable")
            }
        }
        persistChainStates()
        diagnostic("Chain balance refresh finished.")
    }

    private func apply(material: WalletMaterial, importType: String, backupConfirmed: Bool) throws {
        mnemonic = material.mnemonic
        privateKey = material.privateKey
        self.importType = importType
        walletEngine = material.engine
        chains = material.chains
        primaryChainID = material.chains.first(where: { $0.id == WalletNetwork.solana.rawValue })?.id ?? material.chains.first?.id ?? WalletNetwork.solana.rawValue
        address = chains.first(where: { $0.id == primaryChainID })?.address ?? material.primaryAddress
        hasWallet = true
        self.backupConfirmed = backupConfirmed
        chainStates = Dictionary(uniqueKeysWithValues: material.chains.map { chain in
            (chain.id, ChainBalanceSnapshot(balance: 0, updatedAt: nil, status: .idle, message: "Waiting for first sync"))
        })
        balanceSOL = 0
        try persistWallet()
        isAppLocked = biometricLockEnabled
    }

    private func upgradeStoredChainsIfPossible() {
        guard hasWallet else { return }

        do {
            let material: WalletMaterial
            if !mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                material = try WalletCoreBridge.importMnemonic(mnemonic)
            } else if !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                material = try WalletCoreBridge.importPrivateKey(privateKey)
            } else {
                return
            }

            guard material.chains != chains else { return }
            walletEngine = material.engine
            chains = material.chains
            normalizePrimaryChain()
            address = currentChain?.address ?? material.primaryAddress
            try persistWallet()
        } catch {
            diagnostic("Stored chain upgrade skipped.")
        }
    }

    private func normalizePrimaryChain() {
        if chains.contains(where: { $0.id == primaryChainID }) {
            return
        }
        primaryChainID = chains.first(where: { $0.id == WalletNetwork.solana.rawValue })?.id ?? chains.first?.id ?? WalletNetwork.solana.rawValue
    }

    func balanceSnapshot(for chain: WalletChain) -> ChainBalanceSnapshot {
        chainStates[chain.id] ?? ChainBalanceSnapshot(balance: 0, updatedAt: nil, status: .idle, message: "Waiting for first sync")
    }

    func nativeBalance(for chainID: String) -> Double {
        NSDecimalNumber(decimal: chainStates[chainID]?.balance ?? 0).doubleValue
    }

    func formattedBalance(for chain: WalletChain) -> String {
        let balance = chainStates[chain.id]?.balance ?? 0
        return balance.formattedString(maxFractionDigits: chain.network?.fractionDigits ?? 6)
    }

    func fiatValue(for chain: WalletChain) -> Double? {
        guard let network = chain.network,
              let asset = marketAssets.first(where: { $0.id == network.coinGeckoID }),
              let price = asset.price else {
            return nil
        }
        return nativeBalance(for: chain.id) * price
    }

    private func diagnostic(_ message: String) {
        guard diagnosticsEnabled else { return }
        print("[Unite] \(message)")
    }

    private func clearLegacySecrets() {
        defaults.removeObject(forKey: "unite.native.mnemonic")
        defaults.removeObject(forKey: "unite.native.privateKey")
    }

    private func persistWallet() throws {
        defaults.set(hasWallet, forKey: "unite.native.hasWallet")
        defaults.set(backupConfirmed, forKey: "unite.native.backupConfirmed")
        defaults.set(address, forKey: "unite.native.address")
        defaults.set(importType, forKey: "unite.native.importType")
        defaults.set(walletEngine, forKey: "unite.native.walletEngine")
        defaults.set(primaryChainID, forKey: "unite.native.primaryChainID")
        defaults.set(diagnosticsEnabled, forKey: "unite.native.diagnosticsEnabled")
        defaults.set(biometricLockEnabled, forKey: "unite.native.biometricLockEnabled")
        defaults.set(marketAutoRefreshEnabled, forKey: "unite.native.marketAutoRefreshEnabled")
        defaults.set(Array(watchedMarketAssetIDs), forKey: "unite.native.watchedMarketAssetIDs")
        if let data = try? JSONEncoder().encode(chains) {
            defaults.set(data, forKey: "unite.native.chains")
        }
        persistChainStates()
        try secureStore.set(mnemonic, for: SecureKey.mnemonic)
        try secureStore.set(privateKey, for: SecureKey.privateKey)
    }

    private static func loadChains(from defaults: UserDefaults) -> [WalletChain] {
        guard let data = defaults.data(forKey: "unite.native.chains") else { return [] }
        return (try? JSONDecoder().decode([WalletChain].self, from: data)) ?? []
    }

    private func persistChainStates() {
        if let data = try? JSONEncoder().encode(chainStates) {
            defaults.set(data, forKey: "unite.native.chainStates")
        }
    }

    private static func loadChainStates(from defaults: UserDefaults) -> [String: ChainBalanceSnapshot] {
        guard let data = defaults.data(forKey: "unite.native.chainStates") else { return [:] }
        return (try? JSONDecoder().decode([String: ChainBalanceSnapshot].self, from: data)) ?? [:]
    }

    private func persistContacts() {
        if let data = try? JSONEncoder().encode(contacts) {
            defaults.set(data, forKey: "unite.native.contacts")
        }
    }

    private static func loadContacts(from defaults: UserDefaults) -> [WalletContact] {
        guard let data = defaults.data(forKey: "unite.native.contacts") else { return [] }
        return (try? JSONDecoder().decode([WalletContact].self, from: data)) ?? []
    }

    private func persistMarketPriceAlerts() {
        if let data = try? JSONEncoder().encode(marketPriceAlerts) {
            defaults.set(data, forKey: "unite.native.marketPriceAlerts")
        }
    }

    private static func loadMarketPriceAlerts(from defaults: UserDefaults) -> [MarketPriceAlert] {
        guard let data = defaults.data(forKey: "unite.native.marketPriceAlerts") else { return [] }
        return (try? JSONDecoder().decode([MarketPriceAlert].self, from: data)) ?? []
    }
}

enum ChainSyncStatus: String, Codable {
    case idle
    case synced
    case failed
}

struct ChainBalanceSnapshot: Codable, Equatable {
    var balance: Decimal
    var updatedAt: Date?
    var status: ChainSyncStatus
    var message: String?
}

protocol ChainDataProviding {
    func fetchBalances(for chains: [WalletChain]) async -> [String: ChainBalanceSnapshot]
}

struct LiveChainDataProvider: ChainDataProviding {
    func fetchBalances(for chains: [WalletChain]) async -> [String: ChainBalanceSnapshot] {
        await withTaskGroup(of: (String, ChainBalanceSnapshot).self) { group in
            for chain in chains {
                group.addTask {
                    let snapshot = await fetchBalance(for: chain)
                    return (chain.id, snapshot)
                }
            }

            var balances: [String: ChainBalanceSnapshot] = [:]
            for await (chainID, snapshot) in group {
                balances[chainID] = snapshot
            }
            return balances
        }
    }

    private func fetchBalance(for chain: WalletChain) async -> ChainBalanceSnapshot {
        guard let network = chain.network else {
            return ChainBalanceSnapshot(balance: 0, updatedAt: nil, status: .failed, message: "Unsupported network")
        }

        do {
            let balance: Decimal
            switch network {
            case .bitcoin:
                balance = try await bitcoinBalance(address: chain.address)
            case .ethereum:
                balance = try await ethereumBalance(address: chain.address)
            case .solana:
                balance = try await solanaBalance(address: chain.address)
            }

            return ChainBalanceSnapshot(balance: balance, updatedAt: Date(), status: .synced, message: nil)
        } catch {
            return ChainBalanceSnapshot(balance: 0, updatedAt: nil, status: .failed, message: error.localizedDescription)
        }
    }

    private func bitcoinBalance(address: String) async throws -> Decimal {
        let url = URL(string: "https://blockstream.info/api/address/\(address)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(BlockstreamAddressPayload.self, from: data)
        let sats = payload.chainStats.fundedTxoSum - payload.chainStats.spentTxoSum + payload.mempoolStats.fundedTxoSum - payload.mempoolStats.spentTxoSum
        return Decimal(sats) / Decimal(100_000_000)
    }

    private func ethereumBalance(address: String) async throws -> Decimal {
        let request = JSONRPCRequest(method: "eth_getBalance", params: [address, "latest"])
        let result = try await postJSONRPC(request, url: URL(string: "https://ethereum-rpc.publicnode.com")!, responseType: EthereumBalanceResponse.self)
        return Decimal(hexString: result.result) / Decimal(string: "1000000000000000000")!
    }

    private func solanaBalance(address: String) async throws -> Decimal {
        let request = JSONRPCRequest(method: "getBalance", params: [address, ["commitment": "confirmed"]])
        let result = try await postJSONRPC(request, url: URL(string: "https://api.mainnet-beta.solana.com")!, responseType: SolanaBalanceResponse.self)
        return Decimal(result.result.value) / Decimal(1_000_000_000)
    }

    private func postJSONRPC<Response: Decodable>(_ request: JSONRPCRequest, url: URL, responseType: Response.Type) async throws -> Response {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}

struct WalletServiceStatus: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let detail: String
    let state: String
}

struct WalletActivity: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let amount: String
    let status: String
}

struct WalletNotification: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
    let severity: String
}

struct WalletContact: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var address: String
    var chain: String

    init(id: UUID = UUID(), name: String, address: String, chain: String) {
        self.id = id
        self.name = name
        self.address = address
        self.chain = chain
    }

    var shortAddress: String {
        guard address.count > 14 else { return address }
        return "\(address.prefix(6))...\(address.suffix(6))"
    }
}

struct MarketPriceAlert: Identifiable, Codable, Equatable {
    let id: UUID
    var assetID: String
    var symbol: String
    var targetPrice: Double
    var createdAt: Date

    init(id: UUID = UUID(), assetID: String, symbol: String, targetPrice: Double, createdAt: Date = Date()) {
        self.id = id
        self.assetID = assetID
        self.symbol = symbol
        self.targetPrice = targetPrice
        self.createdAt = createdAt
    }
}

struct MarketAsset: Identifiable, Equatable {
    let id: String
    var name: String
    var symbol: String
    var colorName: String
    var imageURL: URL?
    var price: Double?
    var change1h: Double?
    var change24h: Double?
    var change7d: Double?
    var volume: Double?
    var marketCap: Double?
    var rank: Int?
    var sparkline: [Double]

    var isPositive: Bool { (change24h ?? 0) >= 0 }

    func updated(with remote: CoinGeckoMarketAsset) -> MarketAsset {
        var copy = self
        copy.name = remote.name
        copy.symbol = remote.symbol.uppercased()
        copy.imageURL = remote.image.flatMap(URL.init(string:))
        copy.price = remote.currentPrice
        copy.change1h = remote.priceChangePercentage1h
        copy.change24h = remote.priceChangePercentage24h
        copy.change7d = remote.priceChangePercentage7d
        copy.volume = remote.totalVolume
        copy.marketCap = remote.marketCap
        copy.rank = remote.marketCapRank
        copy.sparkline = remote.sparklineIn7d?.price ?? sparkline
        return copy
    }

    static let defaults: [MarketAsset] = [
        .init(id: "bitcoin", name: "Bitcoin", symbol: "BTC", colorName: "yellow", sparkline: []),
        .init(id: "ethereum", name: "Ethereum", symbol: "ETH", colorName: "blue", sparkline: []),
        .init(id: "solana", name: "Solana", symbol: "SOL", colorName: "mint", sparkline: []),
        .init(id: "usd-coin", name: "USDC", symbol: "USDC", colorName: "blue", sparkline: []),
        .init(id: "jupiter-exchange-solana", name: "Jupiter", symbol: "JUP", colorName: "blue", sparkline: []),
        .init(id: "jito-governance-token", name: "Jito", symbol: "JTO", colorName: "violet", sparkline: []),
        .init(id: "bonk", name: "Bonk", symbol: "BONK", colorName: "yellow", sparkline: []),
        .init(id: "pyth-network", name: "Pyth Network", symbol: "PYTH", colorName: "violet", sparkline: []),
        .init(id: "helium", name: "Helium", symbol: "HNT", colorName: "blue", sparkline: []),
        .init(id: "dogwifcoin", name: "dogwifhat", symbol: "WIF", colorName: "yellow", sparkline: []),
        .init(id: "raydium", name: "Raydium", symbol: "RAY", colorName: "violet", sparkline: []),
        .init(id: "render-token", name: "Render", symbol: "RNDR", colorName: "blue", sparkline: [])
    ]
}

struct CoinGeckoMarketAsset: Decodable {
    let id: String
    let symbol: String
    let name: String
    let image: String?
    let currentPrice: Double?
    let marketCap: Double?
    let marketCapRank: Int?
    let totalVolume: Double?
    let priceChangePercentage1h: Double?
    let priceChangePercentage24h: Double?
    let priceChangePercentage7d: Double?
    let sparklineIn7d: CoinGeckoSparkline?

    enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case name
        case image
        case currentPrice = "current_price"
        case marketCap = "market_cap"
        case marketCapRank = "market_cap_rank"
        case totalVolume = "total_volume"
        case priceChangePercentage1h = "price_change_percentage_1h_in_currency"
        case priceChangePercentage24h = "price_change_percentage_24h_in_currency"
        case priceChangePercentage7d = "price_change_percentage_7d_in_currency"
        case sparklineIn7d = "sparkline_in_7d"
    }
}

struct CoinGeckoSparkline: Decodable, Equatable {
    let price: [Double]
}

private struct JSONRPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id = 1
    let method: String
    let params: [AnyEncodable]

    init(method: String, params: [Any]) {
        self.method = method
        self.params = params.map(AnyEncodable.init)
    }
}

private struct EthereumBalanceResponse: Decodable {
    let result: String
}

private struct SolanaBalanceResponse: Decodable {
    let result: SolanaBalanceValue
}

private struct SolanaBalanceValue: Decodable {
    let value: Int64
}

private struct BlockstreamAddressPayload: Decodable {
    let chainStats: BlockstreamStats
    let mempoolStats: BlockstreamStats

    enum CodingKeys: String, CodingKey {
        case chainStats = "chain_stats"
        case mempoolStats = "mempool_stats"
    }
}

private struct BlockstreamStats: Decodable {
    let fundedTxoSum: Int64
    let spentTxoSum: Int64

    enum CodingKeys: String, CodingKey {
        case fundedTxoSum = "funded_txo_sum"
        case spentTxoSum = "spent_txo_sum"
    }
}

private struct AnyEncodable: Encodable {
    private let encodeBlock: (Encoder) throws -> Void

    init(_ value: Any) {
        self.encodeBlock = { encoder in
            var container = encoder.singleValueContainer()
            switch value {
            case let string as String:
                try container.encode(string)
            case let int as Int:
                try container.encode(int)
            case let int64 as Int64:
                try container.encode(int64)
            case let bool as Bool:
                try container.encode(bool)
            case let dictionary as [String: String]:
                try container.encode(dictionary)
            case let dictionary as [String: AnyEncodable]:
                try container.encode(dictionary)
            default:
                if let nested = value as? [String: Any] {
                    try container.encode(nested.mapValues(AnyEncodable.init))
                } else if let array = value as? [Any] {
                    try container.encode(array.map(AnyEncodable.init))
                } else {
                    throw EncodingError.invalidValue(value, .init(codingPath: container.codingPath, debugDescription: "Unsupported JSON-RPC parameter"))
                }
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeBlock(encoder)
    }
}

private extension Decimal {
    init(hexString: String) {
        self = 0
        let digits = hexString.replacingOccurrences(of: "0x", with: "")
        for scalar in digits.lowercased().unicodeScalars {
            let value: Decimal
            switch scalar {
            case "0"..."9":
                value = Decimal(Int(scalar.value - 48))
            case "a"..."f":
                value = Decimal(Int(scalar.value - 87))
            default:
                continue
            }
            self *= 16
            self += value
        }
    }

    func formattedString(maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter.string(from: self as NSDecimalNumber) ?? "0"
    }
}
