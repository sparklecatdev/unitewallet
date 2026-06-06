import Foundation
import Combine

#if canImport(GRDB)
import GRDB
#endif

struct Wallet: Identifiable, Codable, Equatable {
    let id: String
    let tokenQueryID: String
    let accountID: String
    let coinName: String?
    let coinCode: String?
    let tokenDecimals: Int?
    let coinImage: String?

    init(
        id: String = UUID().uuidString,
        tokenQueryID: String,
        accountID: String,
        coinName: String? = nil,
        coinCode: String? = nil,
        tokenDecimals: Int? = nil,
        coinImage: String? = nil
    ) {
        self.id = id
        self.tokenQueryID = tokenQueryID
        self.accountID = accountID
        self.coinName = coinName
        self.coinCode = coinCode
        self.tokenDecimals = tokenDecimals
        self.coinImage = coinImage
    }

    var tokenID: String {
        tokenQueryID.components(separatedBy: "|").first ?? tokenQueryID
    }

    var isNative: Bool {
        tokenQueryID.hasSuffix("|native")
    }

    var isCustom: Bool {
        coinName != nil
    }
}

struct WalletData {
    let wallets: [Wallet]
    let account: Account?
}

final class WalletManager {
    private let accountManager: AccountManager
    private let userDefaults: UserDefaultsStorage
    private let databaseManager: DatabaseManager

    private let activeWalletDataSubject = CurrentValueSubject<WalletData, Never>(
        WalletData(wallets: [], account: nil)
    )

    private var cancellables = Set<AnyCancellable>()
    private var walletsByAccount: [String: [Wallet]] = [:]

    init(accountManager: AccountManager, userDefaultsStorage: UserDefaultsStorage, databaseManager: DatabaseManager) {
        self.accountManager = accountManager
        self.userDefaults = userDefaultsStorage
        self.databaseManager = databaseManager

        accountManager.activeAccountPublisher
            .sink { [weak self] account in
                self?.reloadWallets(for: account)
            }
            .store(in: &cancellables)

        accountManager.accountDeletedPublisher
            .sink { [weak self] account in
                self?.handleDelete(account: account)
            }
            .store(in: &cancellables)

        loadAllWallets()
    }

    var activeWalletData: WalletData {
        activeWalletDataSubject.value
    }

    var activeWallets: [Wallet] {
        activeWalletData.wallets
    }

    var activeWalletDataPublisher: AnyPublisher<WalletData, Never> {
        activeWalletDataSubject.eraseToAnyPublisher()
    }

    func preloadWallets() {
        if let account = accountManager.activeAccount {
            reloadWallets(for: account)
        }
    }

    func wallets(for account: Account) -> [Wallet] {
        walletsByAccount[account.id] ?? []
    }

    func save(wallets: [Wallet], for account: Account) {
        walletsByAccount[account.id] = wallets
        persistWallets(for: account.id, wallets: wallets)
        if accountManager.activeAccount?.id == account.id {
            activeWalletDataSubject.send(WalletData(wallets: wallets, account: account))
        }
    }

    func add(wallet: Wallet, to account: Account) {
        var existing = walletsByAccount[account.id] ?? []
        guard !existing.contains(where: { $0.tokenQueryID == wallet.tokenQueryID }) else { return }
        existing.append(wallet)
        save(wallets: existing, for: account)
    }

    func remove(wallet: Wallet, from account: Account) {
        var existing = walletsByAccount[account.id] ?? []
        existing.removeAll { $0.tokenQueryID == wallet.tokenQueryID }
        save(wallets: existing, for: account)
    }

    func clearWallets(for accountID: String) {
        walletsByAccount[accountID] = nil
        userDefaults.removeValue(forKey: walletStorageKey(for: accountID))

        #if canImport(GRDB)
        do {
            try databaseManager.write { db in
                try WalletRecord
                    .filter(WalletRecord.Columns.accountID == accountID)
                    .deleteAll(db)
            }
        } catch {
            print("[WalletManager] failed to clear wallets from db: \(error)")
        }
        #endif

        if accountManager.activeAccount?.id == accountID {
            activeWalletDataSubject.send(WalletData(wallets: [], account: accountManager.activeAccount))
        }
    }

    private func handleDelete(account: Account) {
        clearWallets(for: account.id)
    }

    private func reloadWallets(for account: Account?) {
        guard let account else {
            activeWalletDataSubject.send(WalletData(wallets: [], account: nil))
            return
        }
        let wallets = walletsByAccount[account.id] ?? []
        activeWalletDataSubject.send(WalletData(wallets: wallets, account: account))
    }

    private func loadAllWallets() {
        #if canImport(GRDB)
        do {
            let records = try databaseManager.read { db in
                try WalletRecord
                    .order(WalletRecord.Columns.sortOrder)
                    .fetchAll(db)
            }

            if !records.isEmpty {
                var grouped: [String: [Wallet]] = [:]
                for record in records {
                    grouped[record.accountID, default: []].append(record.toWallet())
                }
                walletsByAccount = grouped
            }
        } catch {
            print("[WalletManager] failed to load from db: \(error)")
        }
        #endif

        // Fallback: load from UserDefaults if db is empty
        if walletsByAccount.isEmpty {
            for account in accountManager.accounts {
                if let data = userDefaults.data(forKey: walletStorageKey(for: account.id)),
                   let wallets = try? JSONDecoder().decode([Wallet].self, from: data) {
                    walletsByAccount[account.id] = wallets
                }
            }
        }

        if let active = accountManager.activeAccount {
            reloadWallets(for: active)
        }
    }

    private func persistWallets(for accountID: String, wallets: [Wallet]) {
        // Always persist to UserDefaults as fallback
        guard let data = try? JSONEncoder().encode(wallets) else { return }
        userDefaults.set(data: data, forKey: walletStorageKey(for: accountID))

        // Persist to GRDB
        #if canImport(GRDB)
        do {
            let records = wallets.enumerated().map { idx, wallet in
                WalletRecord.from(wallet: wallet, sortOrder: idx)
            }
            try databaseManager.write { db in
                try WalletRecord
                    .filter(WalletRecord.Columns.accountID == accountID)
                    .deleteAll(db)

                for record in records {
                    try record.insert(db)
                }
            }
        } catch {
            print("[WalletManager] failed to persist wallets to db: \(error)")
        }
        #endif
    }

    private func walletStorageKey(for accountID: String) -> String {
        "unite.wallets.\(accountID)"
    }
}
