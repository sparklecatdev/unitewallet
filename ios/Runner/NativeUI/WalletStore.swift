import CryptoKit
import Foundation

@MainActor
final class WalletStore: ObservableObject {
    enum SecureKey {
        static let mnemonic = "wallet.mnemonic"
        static let privateKey = "wallet.privateKey"
        static let passcodeHash = "wallet.passcodeHash"
        static let passcodeSalt = "wallet.passcodeSalt"
    }

    enum SupportResource {
        static let email = "support@unitewallet.app"
        static let privacyURL = URL(string: "https://unitewallet.app/privacy")!
        static let termsURL = URL(string: "https://unitewallet.app/terms")!
        static let feedbackURL = URL(string: "https://unitewallet.app/beta-feedback")!
    }

    private enum DefaultsKey {
        static let hasWallet = "unite.native.hasWallet"
        static let backupConfirmed = "unite.native.backupConfirmed"
        static let address = "unite.native.address"
        static let importType = "unite.native.importType"
        static let walletEngine = "unite.native.walletEngine"
        static let chains = "unite.native.chains"
        static let primaryChainID = "unite.native.primaryChainID"
        static let chainStates = "unite.native.chainStates"
        static let diagnosticsEnabled = "unite.native.diagnosticsEnabled"
        static let biometricLockEnabled = "unite.native.biometricLockEnabled"
        static let marketAutoRefreshEnabled = "unite.native.marketAutoRefreshEnabled"
        static let watchedMarketAssetIDs = "unite.native.watchedMarketAssetIDs"
        static let contacts = "unite.native.contacts"
        static let marketPriceAlerts = "unite.native.marketPriceAlerts"
        static let assetLayout = "unite.native.assetLayout"
        static let hideSmallBalances = "unite.native.hideSmallBalances"
        static let hideNFTs = "unite.native.hideNFTs"
        static let lastUnlockTimestamp = "unite.native.lastUnlockTimestamp"
    }

    private enum SyncKey {
        static let encryptedWallet = "unite.sync.wallet"
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
    @Published var passcodeConfigured: Bool
    @Published var faceIDEnabled: Bool
    @Published var lastUnlockTimestamp: Date?
    @Published var lockReason: AppLockReason
    @Published var assetLayout: AssetLayoutPreset
    @Published var hideSmallBalances: Bool
    @Published var hideNFTs: Bool
    @Published var syncMessage: String
    @Published var hasSyncBackup: Bool

    private let defaults: UserDefaults
    private let secureStore: SecureStoring
    private let authenticator: DeviceAuthenticating
    private let chainDataProvider: ChainDataProviding
    private let ubiquitousStore: NSUbiquitousKeyValueStore

    init(
        defaults: UserDefaults = .standard,
        secureStore: SecureStoring = KeychainSecureStore.shared,
        authenticator: DeviceAuthenticating = DeviceSecurity.shared,
        chainDataProvider: ChainDataProviding = LiveChainDataProvider(),
        ubiquitousStore: NSUbiquitousKeyValueStore = .default
    ) {
        self.defaults = defaults
        self.secureStore = secureStore
        self.authenticator = authenticator
        self.chainDataProvider = chainDataProvider
        self.ubiquitousStore = ubiquitousStore

        let initialHasWallet = defaults.bool(forKey: DefaultsKey.hasWallet)
        let initialBiometricLockEnabled = defaults.object(forKey: DefaultsKey.biometricLockEnabled) as? Bool ?? true
        let storedPasscodeHash = try? secureStore.string(for: SecureKey.passcodeHash)
        let initialSyncBackup = (ubiquitousStore.string(forKey: SyncKey.encryptedWallet)?.isEmpty == false)

        hasWallet = initialHasWallet
        backupConfirmed = defaults.bool(forKey: DefaultsKey.backupConfirmed)
        address = defaults.string(forKey: DefaultsKey.address) ?? ""
        mnemonic = (try? secureStore.string(for: SecureKey.mnemonic)) ?? ""
        privateKey = (try? secureStore.string(for: SecureKey.privateKey)) ?? ""
        importType = defaults.string(forKey: DefaultsKey.importType) ?? "Generated"
        walletEngine = defaults.string(forKey: DefaultsKey.walletEngine) ?? "Not initialized"
        chains = Self.loadChains(from: defaults)
        primaryChainID = defaults.string(forKey: DefaultsKey.primaryChainID) ?? WalletNetwork.solana.rawValue
        chainStates = Self.loadChainStates(from: defaults)
        diagnosticsEnabled = defaults.bool(forKey: DefaultsKey.diagnosticsEnabled)
        biometricLockEnabled = initialBiometricLockEnabled
        faceIDEnabled = initialBiometricLockEnabled
        contacts = Self.loadContacts(from: defaults)
        marketAutoRefreshEnabled = defaults.object(forKey: DefaultsKey.marketAutoRefreshEnabled) as? Bool ?? true
        watchedMarketAssetIDs = Set(defaults.stringArray(forKey: DefaultsKey.watchedMarketAssetIDs) ?? ["solana"])
        marketPriceAlerts = Self.loadMarketPriceAlerts(from: defaults)
        passcodeConfigured = storedPasscodeHash?.isEmpty == false
        assetLayout = AssetLayoutPreset(rawValue: defaults.integer(forKey: DefaultsKey.assetLayout)) ?? .spacious
        hideSmallBalances = defaults.object(forKey: DefaultsKey.hideSmallBalances) as? Bool ?? false
        hideNFTs = defaults.object(forKey: DefaultsKey.hideNFTs) as? Bool ?? true
        syncMessage = initialSyncBackup ? "Encrypted iCloud backup available." : "No encrypted iCloud backup yet."
        hasSyncBackup = initialSyncBackup
        lastUnlockTimestamp = defaults.object(forKey: DefaultsKey.lastUnlockTimestamp) as? Date
        lockReason = .launch
        isAppLocked = initialHasWallet && storedPasscodeHash?.isEmpty == false

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
        ubiquitousStore.synchronize()
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
            .init(name: "Screen lock", detail: passcodeConfigured ? (faceIDEnabled ? "App passcode plus Face ID unlock" : "App passcode required on this device") : "Set a 6-digit app passcode", state: passcodeConfigured ? "On" : "Action"),
            .init(name: "Market data", detail: marketUpdatedAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Pull to refresh when you need it", state: "Read-only"),
            .init(name: "Network sync", detail: lastChainSyncDetail, state: chainSyncStateLabel),
            .init(name: "iCloud backup", detail: syncMessage, state: hasSyncBackup ? "Ready" : "Review")
        ]
    }

    var activities: [WalletActivity] {
        [
            .init(icon: "checkmark.seal", title: "Wallet ready", detail: "Your multichain wallet is available on this device with \(chains.count) supported networks.", amount: "", status: hasWallet ? "Ready" : "Setup"),
            .init(icon: "lock.shield", title: "Screen lock", detail: passcodeConfigured ? "Wallet access now sits behind a 6-digit app code." : "Set a 6-digit app code before using the wallet.", amount: "", status: passcodeConfigured ? "On" : "Action"),
            .init(icon: "key.viewfinder", title: "Backup reminder", detail: backupConfirmed ? "Your recovery material has been confirmed and can be reviewed later." : "Confirm your recovery material before moving funds.", amount: "", status: backupConfirmed ? "Saved" : "Action"),
            .init(icon: "arrow.trianglehead.2.clockwise", title: "Chain sync", detail: lastChainSyncDetail, amount: "", status: chainSyncStateLabel),
            .init(icon: "icloud", title: "iCloud backup", detail: syncMessage, amount: "", status: hasSyncBackup ? "Ready" : "Review")
        ]
    }

    var notifications: [WalletNotification] {
        [
            .init(title: "Backup", detail: backupConfirmed ? "Your recovery material is available later behind device authentication." : "Confirm and store your recovery material offline before using the wallet.", severity: backupConfirmed ? "OK" : "Action"),
            .init(title: "What this build covers", detail: "This build derives Bitcoin, Ethereum, and Solana addresses from one recovery phrase and syncs native balances from live networks.", severity: "Guide"),
            .init(title: "Current send scope", detail: "Receive, secure storage, app lock, and encrypted sync are live here. Network signing and broadcast still need chain-specific service work.", severity: "Note")
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
        defaults.set(true, forKey: DefaultsKey.backupConfirmed)
    }

    func setDiagnosticsEnabled(_ enabled: Bool) {
        diagnosticsEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.diagnosticsEnabled)
    }

    func setBiometricLockEnabled(_ enabled: Bool) {
        biometricLockEnabled = enabled
        faceIDEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.biometricLockEnabled)
        diagnostic("Biometric lock setting changed.")
    }

    func setMarketAutoRefreshEnabled(_ enabled: Bool) {
        marketAutoRefreshEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.marketAutoRefreshEnabled)
    }

    func setPrimaryChain(_ chainID: String) {
        guard chains.contains(where: { $0.id == chainID }) else { return }
        primaryChainID = chainID
        address = currentChain?.address ?? address
        defaults.set(chainID, forKey: DefaultsKey.primaryChainID)
    }

    func setAssetLayout(_ preset: AssetLayoutPreset) {
        assetLayout = preset
        defaults.set(preset.rawValue, forKey: DefaultsKey.assetLayout)
    }

    func setHideSmallBalances(_ hidden: Bool) {
        hideSmallBalances = hidden
        defaults.set(hidden, forKey: DefaultsKey.hideSmallBalances)
    }

    func setHideNFTs(_ hidden: Bool) {
        hideNFTs = hidden
        defaults.set(hidden, forKey: DefaultsKey.hideNFTs)
    }

    func setPasscode(_ passcode: String) -> String? {
        guard passcode.count == 6, passcode.allSatisfy(\.isNumber) else {
            return "Use exactly 6 digits."
        }
        let salt = randomSalt()
        let hash = passcodeHash(for: passcode, salt: salt)
        do {
            try secureStore.set(hash, for: SecureKey.passcodeHash)
            try secureStore.set(salt.base64EncodedString(), for: SecureKey.passcodeSalt)
            passcodeConfigured = true
            isAppLocked = hasWallet
            return nil
        } catch {
            return "The app passcode could not be saved on this device."
        }
    }

    func verifyPasscode(_ passcode: String) -> Bool {
        guard let storedHash = try? secureStore.string(for: SecureKey.passcodeHash),
              let saltString = try? secureStore.string(for: SecureKey.passcodeSalt),
              let salt = Data(base64Encoded: saltString) else {
            unlockErrorMessage = "The app passcode is not set up on this device."
            return false
        }

        let matches = passcodeHash(for: passcode, salt: salt) == storedHash
        unlockErrorMessage = matches ? nil : "That code did not match."
        if matches {
            completeUnlock()
        }
        return matches
    }

    func lockApp(reason: AppLockReason = .background) {
        guard hasWallet, passcodeConfigured else { return }
        lockReason = reason
        isAppLocked = true
        unlockErrorMessage = nil
    }

    func unlockWithFaceID() async -> Bool {
        guard hasWallet, passcodeConfigured, faceIDEnabled else { return false }
        do {
            let allowed = try await authenticator.authenticate(reason: "Unlock Unite Wallet.")
            if allowed {
                completeUnlock()
            } else {
                unlockErrorMessage = "Authentication was cancelled."
            }
            return allowed
        } catch {
            unlockErrorMessage = error.localizedDescription
            return false
        }
    }

    func syncEncryptedWallet(passcode: String) -> String? {
        guard verifyPasscodeMaterial(passcode) else {
            return "The sync passcode did not match your app code."
        }
        guard hasWallet else {
            return "Create or import a wallet before syncing."
        }

        do {
            let payload = SyncWalletPayload(
                mnemonic: mnemonic,
                privateKey: privateKey,
                importType: importType,
                walletEngine: walletEngine,
                primaryChainID: primaryChainID,
                chains: chains,
                chainStates: chainStates,
                backupConfirmed: backupConfirmed,
                settings: SyncWalletSettings(
                    assetLayout: assetLayout,
                    hideSmallBalances: hideSmallBalances,
                    hideNFTs: hideNFTs,
                    watchedMarketAssetIDs: Array(watchedMarketAssetIDs)
                )
            )
            let encrypted = try encryptSyncPayload(payload, passcode: passcode)
            ubiquitousStore.set(encrypted, forKey: SyncKey.encryptedWallet)
            ubiquitousStore.synchronize()
            hasSyncBackup = true
            syncMessage = "Encrypted iCloud backup updated."
            return nil
        } catch {
            syncMessage = "Encrypted iCloud backup failed."
            return "The encrypted iCloud backup could not be updated."
        }
    }

    func restoreWalletFromSync(passcode: String) -> String? {
        guard let encrypted = ubiquitousStore.string(forKey: SyncKey.encryptedWallet), !encrypted.isEmpty else {
            return "No encrypted iCloud backup was found."
        }

        do {
            let payload = try decryptSyncPayload(encrypted, passcode: passcode)
            guard setPasscode(passcode) == nil else {
                return "The app passcode could not be restored on this device."
            }
            try apply(syncPayload: payload)
            hasSyncBackup = true
            syncMessage = "Encrypted iCloud backup restored."
            return nil
        } catch {
            return "That passcode could not open the encrypted iCloud backup."
        }
    }

    func clearSyncBackup() {
        ubiquitousStore.removeObject(forKey: SyncKey.encryptedWallet)
        ubiquitousStore.synchronize()
        hasSyncBackup = false
        syncMessage = "Encrypted iCloud backup removed."
    }

    func unlockApp() async -> Bool {
        await unlockWithFaceID()
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
        defaults.set(Array(watchedMarketAssetIDs), forKey: DefaultsKey.watchedMarketAssetIDs)
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
        defaults.removeObject(forKey: DefaultsKey.backupConfirmed)
        defaults.removeObject(forKey: DefaultsKey.address)
        defaults.removeObject(forKey: DefaultsKey.importType)
        defaults.removeObject(forKey: DefaultsKey.walletEngine)
        defaults.removeObject(forKey: DefaultsKey.chains)
        defaults.removeObject(forKey: DefaultsKey.primaryChainID)
        defaults.removeObject(forKey: DefaultsKey.chainStates)
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
        isAppLocked = passcodeConfigured
    }

    private func apply(syncPayload: SyncWalletPayload) throws {
        mnemonic = syncPayload.mnemonic
        privateKey = syncPayload.privateKey
        importType = syncPayload.importType
        walletEngine = syncPayload.walletEngine
        chains = syncPayload.chains
        primaryChainID = syncPayload.primaryChainID
        address = chains.first(where: { $0.id == primaryChainID })?.address ?? syncPayload.chains.first?.address ?? ""
        chainStates = syncPayload.chainStates
        backupConfirmed = syncPayload.backupConfirmed
        hasWallet = true
        watchedMarketAssetIDs = Set(syncPayload.settings.watchedMarketAssetIDs)
        assetLayout = syncPayload.settings.assetLayout
        hideSmallBalances = syncPayload.settings.hideSmallBalances
        hideNFTs = syncPayload.settings.hideNFTs
        try persistWallet()
        completeUnlock()
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
        defaults.set(hasWallet, forKey: DefaultsKey.hasWallet)
        defaults.set(backupConfirmed, forKey: DefaultsKey.backupConfirmed)
        defaults.set(address, forKey: DefaultsKey.address)
        defaults.set(importType, forKey: DefaultsKey.importType)
        defaults.set(walletEngine, forKey: DefaultsKey.walletEngine)
        defaults.set(primaryChainID, forKey: DefaultsKey.primaryChainID)
        defaults.set(diagnosticsEnabled, forKey: DefaultsKey.diagnosticsEnabled)
        defaults.set(faceIDEnabled, forKey: DefaultsKey.biometricLockEnabled)
        defaults.set(marketAutoRefreshEnabled, forKey: DefaultsKey.marketAutoRefreshEnabled)
        defaults.set(Array(watchedMarketAssetIDs), forKey: DefaultsKey.watchedMarketAssetIDs)
        defaults.set(assetLayout.rawValue, forKey: DefaultsKey.assetLayout)
        defaults.set(hideSmallBalances, forKey: DefaultsKey.hideSmallBalances)
        defaults.set(hideNFTs, forKey: DefaultsKey.hideNFTs)
        if let data = try? JSONEncoder().encode(chains) {
            defaults.set(data, forKey: DefaultsKey.chains)
        }
        persistChainStates()
        try secureStore.set(mnemonic, for: SecureKey.mnemonic)
        try secureStore.set(privateKey, for: SecureKey.privateKey)
    }

    private static func loadChains(from defaults: UserDefaults) -> [WalletChain] {
        guard let data = defaults.data(forKey: DefaultsKey.chains) else { return [] }
        return (try? JSONDecoder().decode([WalletChain].self, from: data)) ?? []
    }

    private func persistChainStates() {
        if let data = try? JSONEncoder().encode(chainStates) {
            defaults.set(data, forKey: DefaultsKey.chainStates)
        }
    }

    private static func loadChainStates(from defaults: UserDefaults) -> [String: ChainBalanceSnapshot] {
        guard let data = defaults.data(forKey: DefaultsKey.chainStates) else { return [:] }
        return (try? JSONDecoder().decode([String: ChainBalanceSnapshot].self, from: data)) ?? [:]
    }

    private func persistContacts() {
        if let data = try? JSONEncoder().encode(contacts) {
            defaults.set(data, forKey: DefaultsKey.contacts)
        }
    }

    private static func loadContacts(from defaults: UserDefaults) -> [WalletContact] {
        guard let data = defaults.data(forKey: DefaultsKey.contacts) else { return [] }
        return (try? JSONDecoder().decode([WalletContact].self, from: data)) ?? []
    }

    private func persistMarketPriceAlerts() {
        if let data = try? JSONEncoder().encode(marketPriceAlerts) {
            defaults.set(data, forKey: DefaultsKey.marketPriceAlerts)
        }
    }

    private static func loadMarketPriceAlerts(from defaults: UserDefaults) -> [MarketPriceAlert] {
        guard let data = defaults.data(forKey: DefaultsKey.marketPriceAlerts) else { return [] }
        return (try? JSONDecoder().decode([MarketPriceAlert].self, from: data)) ?? []
    }

    private func completeUnlock() {
        isAppLocked = false
        unlockErrorMessage = nil
        lastUnlockTimestamp = Date()
        defaults.set(lastUnlockTimestamp, forKey: DefaultsKey.lastUnlockTimestamp)
    }

    private func verifyPasscodeMaterial(_ passcode: String) -> Bool {
        guard let storedHash = try? secureStore.string(for: SecureKey.passcodeHash),
              let saltString = try? secureStore.string(for: SecureKey.passcodeSalt),
              let salt = Data(base64Encoded: saltString) else {
            return false
        }
        return passcodeHash(for: passcode, salt: salt) == storedHash
    }

    private func encryptSyncPayload(_ payload: SyncWalletPayload, passcode: String) throws -> String {
        let salt = randomSalt()
        let key = SymmetricKey(data: Data(SHA256.hash(data: salt + Data(passcode.utf8))))
        let clear = try JSONEncoder().encode(payload)
        let sealed = try AES.GCM.seal(clear, using: key)
        let envelope = SyncEnvelope(
            salt: salt.base64EncodedString(),
            nonce: sealed.nonce.withUnsafeBytes { Data($0).base64EncodedString() },
            ciphertext: sealed.ciphertext.base64EncodedString(),
            tag: sealed.tag.base64EncodedString()
        )
        return try String(data: JSONEncoder().encode(envelope), encoding: .utf8) ?? ""
    }

    private func decryptSyncPayload(_ encrypted: String, passcode: String) throws -> SyncWalletPayload {
        let envelope = try JSONDecoder().decode(SyncEnvelope.self, from: Data(encrypted.utf8))
        let salt = Data(base64Encoded: envelope.salt) ?? Data()
        let key = SymmetricKey(data: Data(SHA256.hash(data: salt + Data(passcode.utf8))))
        let nonceData = Data(base64Encoded: envelope.nonce) ?? Data()
        let ciphertext = Data(base64Encoded: envelope.ciphertext) ?? Data()
        let tag = Data(base64Encoded: envelope.tag) ?? Data()
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let clear = try AES.GCM.open(box, using: key)
        return try JSONDecoder().decode(SyncWalletPayload.self, from: clear)
    }

    private func passcodeHash(for passcode: String, salt: Data) -> String {
        let digest = SHA256.hash(data: salt + Data(passcode.utf8))
        return Data(digest).base64EncodedString()
    }

    private func randomSalt() -> Data {
        let bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes)
    }
}

enum AppLockReason: String {
    case launch
    case background
    case securityAction
}

enum AssetLayoutPreset: Int, CaseIterable, Codable, Identifiable {
    case compact = 1
    case balanced = 2
    case spacious = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .balanced: "Balanced"
        case .spacious: "Spacious"
        }
    }
}

private struct SyncWalletPayload: Codable {
    let mnemonic: String
    let privateKey: String
    let importType: String
    let walletEngine: String
    let primaryChainID: String
    let chains: [WalletChain]
    let chainStates: [String: ChainBalanceSnapshot]
    let backupConfirmed: Bool
    let settings: SyncWalletSettings
}

private struct SyncWalletSettings: Codable {
    let assetLayout: AssetLayoutPreset
    let hideSmallBalances: Bool
    let hideNFTs: Bool
    let watchedMarketAssetIDs: [String]
}

private struct SyncEnvelope: Codable {
    let salt: String
    let nonce: String
    let ciphertext: String
    let tag: String
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
