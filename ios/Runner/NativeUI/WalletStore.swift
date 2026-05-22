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

    init(
        defaults: UserDefaults = .standard,
        secureStore: SecureStoring = KeychainSecureStore.shared,
        authenticator: DeviceAuthenticating = DeviceSecurity.shared
    ) {
        self.defaults = defaults
        self.secureStore = secureStore
        self.authenticator = authenticator

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
                    id: "solana",
                    name: "Solana",
                    symbol: "SOL",
                    address: address,
                    derivationPath: "Existing secure wallet",
                    standards: "SLIP-0010 / Ed25519"
                )
            ]
        }

        upgradeStoredChainsIfPossible()
    }

    var shortAddress: String {
        guard address.count > 12 else { return address.isEmpty ? "No wallet" : address }
        return "\(address.prefix(5))...\(address.suffix(5))"
    }

    var visibleEngineName: String {
        walletEngine.isEmpty ? "Unite Core" : walletEngine
    }

    var serviceStatuses: [WalletServiceStatus] {
        [
            .init(name: "Wallet security", detail: "Recovery material stays on this device", state: hasWallet ? "Ready" : "Setup"),
            .init(name: "Screen lock", detail: biometricLockEnabled ? "Sensitive views require device authentication" : "Turn on device authentication", state: biometricLockEnabled ? "On" : "Review"),
            .init(name: "Market data", detail: marketUpdatedAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Pull to refresh when you need it", state: "Read-only"),
            .init(name: "Beta access", detail: "Create, import, backup, receive, and market watch", state: "Active")
        ]
    }

    var activities: [WalletActivity] {
        [
            .init(icon: "checkmark.seal", title: "Wallet ready", detail: "Your Solana beta wallet is set up and available on this device.", amount: "", status: hasWallet ? "Ready" : "Setup"),
            .init(icon: "lock.shield", title: "Screen lock", detail: biometricLockEnabled ? "Recovery and wallet details stay behind device authentication." : "Turn on device authentication before wider testing.", amount: "", status: biometricLockEnabled ? "On" : "Review"),
            .init(icon: "key.viewfinder", title: "Backup reminder", detail: backupConfirmed ? "Your recovery material has been confirmed and can be reviewed later." : "Confirm your recovery material before moving funds.", amount: "", status: backupConfirmed ? "Saved" : "Action"),
            .init(icon: "chart.line.uptrend.xyaxis", title: "Market watch", detail: marketUpdatedAt == nil ? "Read-only prices are ready when you refresh." : "Read-only prices are up to date for this beta.", amount: "", status: marketUpdatedAt == nil ? "Idle" : "Live")
        ]
    }

    var notifications: [WalletNotification] {
        [
            .init(title: "Backup", detail: backupConfirmed ? "Your recovery material is available later behind device authentication." : "Confirm and store your recovery material offline before using the wallet.", severity: backupConfirmed ? "OK" : "Action"),
            .init(title: "What this beta covers", detail: "This beta is focused on create, import, backup, receive, and read-only markets.", severity: "Guide"),
            .init(title: "What comes later", detail: "Send, swap, buy, alerts, and custom network controls stay out of the way until they are ready.", severity: "Note")
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

    func importWallet(secret: String, asPrivateKey: Bool) -> String? {
        let cleanSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSecret.isEmpty else {
            return "Enter a recovery phrase or private key."
        }

        do {
            if asPrivateKey {
                let material = try WalletCoreBridge.importPrivateKey(cleanSecret)
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
        balanceSOL = 0
        isAppLocked = false
        unlockErrorMessage = nil
        defaults.removeObject(forKey: "unite.native.hasWallet")
        defaults.removeObject(forKey: "unite.native.backupConfirmed")
        defaults.removeObject(forKey: "unite.native.address")
        defaults.removeObject(forKey: "unite.native.importType")
        defaults.removeObject(forKey: "unite.native.walletEngine")
        defaults.removeObject(forKey: "unite.native.chains")
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

    private func apply(material: WalletMaterial, importType: String, backupConfirmed: Bool) throws {
        mnemonic = material.mnemonic
        privateKey = material.privateKey
        address = material.primaryAddress
        self.importType = importType
        walletEngine = material.engine
        chains = material.chains
        hasWallet = true
        self.backupConfirmed = backupConfirmed
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
            address = material.primaryAddress
            walletEngine = material.engine
            chains = material.chains
            try persistWallet()
        } catch {
            diagnostic("Stored chain upgrade skipped.")
        }
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
        defaults.set(diagnosticsEnabled, forKey: "unite.native.diagnosticsEnabled")
        defaults.set(biometricLockEnabled, forKey: "unite.native.biometricLockEnabled")
        defaults.set(marketAutoRefreshEnabled, forKey: "unite.native.marketAutoRefreshEnabled")
        defaults.set(Array(watchedMarketAssetIDs), forKey: "unite.native.watchedMarketAssetIDs")
        if let data = try? JSONEncoder().encode(chains) {
            defaults.set(data, forKey: "unite.native.chains")
        }
        try secureStore.set(mnemonic, for: SecureKey.mnemonic)
        try secureStore.set(privateKey, for: SecureKey.privateKey)
    }

    private static func loadChains(from defaults: UserDefaults) -> [WalletChain] {
        guard let data = defaults.data(forKey: "unite.native.chains") else { return [] }
        return (try? JSONDecoder().decode([WalletChain].self, from: data)) ?? []
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
