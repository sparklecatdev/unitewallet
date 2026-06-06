import Foundation
import Combine

#if canImport(GRDB)
import GRDB
#endif

final class Core {
    static let shared = Core()

    let userDefaultsStorage: UserDefaultsStorage
    let keychainStorage: KeychainStorage
    let secureStore: SecureStoring

    let passcodeManager: PasscodeManager
    let databaseManager: DatabaseManager
    let accountManager: AccountManager
    let walletManager: WalletManager
    let contactManager: ContactBookManager
    let transactionStorage: TransactionStorage
    let adapterManager: AdapterManager

    let chainSyncQueue: DispatchQueue

    private init() {
        userDefaultsStorage = UserDefaultsStorage()
        secureStore = KeychainSecureStore.shared
        keychainStorage = KeychainStorage(secureStore: secureStore)

        passcodeManager = PasscodeManager(
            keychainStorage: keychainStorage,
            userDefaults: userDefaultsStorage
        )

        databaseManager = DatabaseManager.shared
        accountManager = AccountManager(
            passcodeManager: passcodeManager,
            keychainStorage: keychainStorage,
            userDefaultsStorage: userDefaultsStorage,
            databaseManager: databaseManager
        )

        walletManager = WalletManager(
            accountManager: accountManager,
            userDefaultsStorage: userDefaultsStorage,
            databaseManager: databaseManager
        )

        contactManager = ContactBookManager(
            userDefaultsStorage: userDefaultsStorage,
            databaseManager: databaseManager
        )

        transactionStorage = TransactionStorage(
            databaseManager: databaseManager,
            userDefaults: userDefaultsStorage
        )

        adapterManager = AdapterManager()

        chainSyncQueue = DispatchQueue(
            label: "\(AppConfig.label).chain-sync",
            qos: .userInitiated
        )
    }

    func launch() {
        do {
            try databaseManager.setup()
        } catch {
            print("[Core] Database setup failed: \(error)")
        }

        accountManager.handleLaunch()
        walletManager.preloadWallets()
    }
}

