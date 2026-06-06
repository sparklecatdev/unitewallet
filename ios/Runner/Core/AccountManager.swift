import Foundation
import Combine

#if canImport(GRDB)
import GRDB
#endif

final class AccountManager {
    private let passcodeManager: PasscodeManager
    private let keychainStorage: KeychainStorage
    private let userDefaults: UserDefaultsStorage
    private let databaseManager: DatabaseManager

    private let accountsSubject = CurrentValueSubject<[Account], Never>([])
    private let activeAccountSubject = CurrentValueSubject<Account?, Never>(nil)
    private let accountUpdatedSubject = PassthroughSubject<Account, Never>()
    private let accountDeletedSubject = PassthroughSubject<Account, Never>()

    private var accountsByID: [String: Account] = [:]
    private var activeAccountID: String?
    private var lastCreatedAccount: Account?

    private var cancellables = Set<AnyCancellable>()

    init(
        passcodeManager: PasscodeManager,
        keychainStorage: KeychainStorage,
        userDefaultsStorage: UserDefaultsStorage,
        databaseManager: DatabaseManager
    ) {
        self.passcodeManager = passcodeManager
        self.keychainStorage = keychainStorage
        self.userDefaults = userDefaultsStorage
        self.databaseManager = databaseManager

        passcodeManager.$currentPasscodeLevel
            .sink { [weak self] _ in self?.syncAccounts() }
            .store(in: &cancellables)

        loadAccounts()
    }

    var accountsPublisher: AnyPublisher<[Account], Never> {
        accountsSubject.eraseToAnyPublisher()
    }

    var activeAccountPublisher: AnyPublisher<Account?, Never> {
        activeAccountSubject.eraseToAnyPublisher()
    }

    var accountUpdatedPublisher: AnyPublisher<Account, Never> {
        accountUpdatedSubject.eraseToAnyPublisher()
    }

    var accountDeletedPublisher: AnyPublisher<Account, Never> {
        accountDeletedSubject.eraseToAnyPublisher()
    }

    var activeAccount: Account? {
        activeAccountSubject.value
    }

    var accounts: [Account] {
        accountsSubject.value
    }

    var activeAccountIDValue: String? {
        activeAccountID
    }

    func set(activeAccountId: String?) {
        guard activeAccountID != activeAccountId else { return }
        activeAccountID = activeAccountId
        let level = passcodeManager.currentPasscodeLevel
        let key = AccountStorageKeys.activeAccountIdKey(level: level)
        userDefaults.set(string: activeAccountId, forKey: key)

        #if canImport(GRDB)
        do {
            let record = BlockchainSetting(key: "active_account_id", value: activeAccountId, updatedAt: Date())
            try databaseManager.write { db in
                try record.upsert(db)
            }
        } catch {
            print("[AccountManager] failed to persist active account ID: \(error)")
        }
        #endif

        syncAccounts()
    }

    func save(account: Account) {
        accountsByID[account.id] = account
        persistAccount(account)
        persistAccountIndex()
        accountsSubject.send(visibleAccounts)

        if lastCreatedAccount?.id == account.id {
            lastCreatedAccount = account
        }
    }

    func handleLaunch() {
        syncAccounts()
    }

    func set(lastCreatedAccount: Account) {
        self.lastCreatedAccount = lastCreatedAccount
    }

    func popLastCreatedAccount() -> Account? {
        defer { lastCreatedAccount = nil }
        return lastCreatedAccount
    }

    func delete(account: Account) {
        accountsByID.removeValue(forKey: account.id)

        try? keychainStorage.remove(key: AccountStorageKeys.wordsKey(accountId: account.id))
        try? keychainStorage.remove(key: AccountStorageKeys.saltKey(accountId: account.id))
        try? keychainStorage.remove(key: AccountStorageKeys.dataKey(accountId: account.id))
        try? keychainStorage.remove(key: AccountStorageKeys.privateKeyKey(accountId: account.id))

        #if canImport(GRDB)
        do {
            try databaseManager.write { db in
                try AccountRecord
                    .filter(AccountRecord.Columns.id == account.id)
                    .deleteAll(db)

                try WalletRecord
                    .filter(WalletRecord.Columns.accountID == account.id)
                    .deleteAll(db)

                try TransactionRecord
                    .filter(TransactionRecord.Columns.accountID == account.id)
                    .deleteAll(db)
            }
        } catch {
            print("[AccountManager] failed to delete account from db: \(error)")
        }
        #endif

        persistAccountIndex()

        if activeAccountID == account.id {
            let remaining = visibleAccounts
            set(activeAccountId: remaining.first?.id)
        }

        accountDeletedSubject.send(account)
        accountsSubject.send(visibleAccounts)
    }

    func clearAll() {
        let all = accounts
        for account in all {
            try? keychainStorage.remove(key: AccountStorageKeys.wordsKey(accountId: account.id))
            try? keychainStorage.remove(key: AccountStorageKeys.saltKey(accountId: account.id))
            try? keychainStorage.remove(key: AccountStorageKeys.dataKey(accountId: account.id))
            try? keychainStorage.remove(key: AccountStorageKeys.privateKeyKey(accountId: account.id))
        }
        accountsByID.removeAll()
        persistAccountIndex()
        set(activeAccountId: nil)

        #if canImport(GRDB)
        do {
            try databaseManager.write { db in
                try AccountRecord.deleteAll(db)
                try WalletRecord.deleteAll(db)
                try TransactionRecord.deleteAll(db)
            }
        } catch {
            print("[AccountManager] failed to clear database: \(error)")
        }
        #endif

        accountsSubject.send([])
    }

    func storeWords(_ words: String, for accountId: String) throws {
        let key = AccountStorageKeys.wordsKey(accountId: accountId)
        try keychainStorage.store(words, key: key)
    }

    func loadWords(for accountId: String) -> String? {
        let key = AccountStorageKeys.wordsKey(accountId: accountId)
        return try? keychainStorage.value(for: key)
    }

    func storePrivateKey(_ key: String, for accountId: String) throws {
        let k = AccountStorageKeys.privateKeyKey(accountId: accountId)
        try keychainStorage.store(key, key: k)
    }

    func loadPrivateKey(for accountId: String) -> String? {
        let k = AccountStorageKeys.privateKeyKey(accountId: accountId)
        return try? keychainStorage.value(for: k)
    }

    func setDuress(accountIds: [String]) {
        let nextLevel = passcodeManager.currentPasscodeLevel + 1
        for var account in accounts {
            if accountIds.contains(account.id) {
                account.level = nextLevel
                accountsByID[account.id] = account
                persistAccount(account)
            }
        }
        persistAccountIndex()
        syncAccounts()
    }

    private var visibleAccounts: [Account] {
        let currentLevel = passcodeManager.currentPasscodeLevel
        return accountsByID.values
            .filter { $0.level >= currentLevel }
            .sorted { $0.name < $1.name }
    }

    private func syncAccounts() {
        let visible = visibleAccounts
        accountsSubject.send(visible)

        if let activeID = activeAccountID, visible.contains(where: { $0.id == activeID }) {
            activeAccountSubject.send(accountsByID[activeID])
        } else if let first = visible.first {
            set(activeAccountId: first.id)
            activeAccountSubject.send(first)
        } else {
            activeAccountSubject.send(nil)
        }
    }

    private func loadAccounts() {
        let level = passcodeManager.currentPasscodeLevel
        activeAccountID = userDefaults.string(forKey: AccountStorageKeys.activeAccountIdKey(level: level))

        #if canImport(GRDB)
        do {
            let records = try databaseManager.read { db in
                try AccountRecord.fetchAll(db)
            }
            for record in records {
                accountsByID[record.id] = record.toAccount()
            }
        } catch {
            print("[AccountManager] failed to load from db: \(error)")
        }
        #endif

        // Fallback: load from UserDefaults if db is empty
        if accountsByID.isEmpty {
            guard let ids = userDefaults.stringArray(forKey: "unite.accounts.ids"),
                  !ids.isEmpty else {
                syncAccounts()
                return
            }

            let decoder = JSONDecoder()
            for id in ids {
                if let data = userDefaults.data(forKey: "unite.account.\(id)"),
                   let account = try? decoder.decode(Account.self, from: data) {
                    accountsByID[id] = account
                }
            }
        }

        syncAccounts()
    }

    private func persistAccount(_ account: Account) {
        #if canImport(GRDB)
        do {
            let record = AccountRecord.from(account: account)
            try databaseManager.write { db in
                try record.upsert(db)
            }
        } catch {
            print("[AccountManager] failed to persist account: \(error)")
        }
        #endif

        // Always persist to UserDefaults as fallback
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(account) {
            userDefaults.set(data: data, forKey: "unite.account.\(account.id)")
        }
    }

    private func persistAccountIndex() {
        let ids = Array(accountsByID.keys)
        userDefaults.set(stringArray: ids, forKey: "unite.accounts.ids")
    }
}
