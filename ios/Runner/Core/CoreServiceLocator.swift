import Foundation

final class CoreServiceLocator {
    static let shared = CoreServiceLocator()

    private var services: [String: Any] = [:]

    func register<T>(_ service: T, for type: T.Type) {
        let key = String(describing: type)
        services[key] = service
    }

    func resolve<T>(_ type: T.Type) -> T? {
        let key = String(describing: type)
        return services[key] as? T
    }

    func registerSingletons() {
        let defaultsStorage = UserDefaultsStorage()
        let secureStore = KeychainSecureStore.shared
        let keychainStorage = KeychainStorage(secureStore: secureStore)

        register(defaultsStorage, for: UserDefaultsStorage.self)
        register(keychainStorage, for: KeychainStorage.self)

        let passcodeManager = PasscodeManager(keychainStorage: keychainStorage, userDefaults: defaultsStorage)
        register(passcodeManager, for: PasscodeManager.self)

        let databaseManager = DatabaseManager.shared
        register(databaseManager, for: DatabaseManager.self)

        let accountManager = AccountManager(
            passcodeManager: passcodeManager,
            keychainStorage: keychainStorage,
            userDefaultsStorage: defaultsStorage,
            databaseManager: databaseManager
        )
        register(accountManager, for: AccountManager.self)

        let walletManager = WalletManager(
            accountManager: accountManager,
            userDefaultsStorage: defaultsStorage,
            databaseManager: databaseManager
        )
        register(walletManager, for: WalletManager.self)

        let contactManager = ContactBookManager(
            userDefaultsStorage: defaultsStorage,
            databaseManager: databaseManager
        )
        register(contactManager, for: ContactBookManager.self)

        let adapterManager = AdapterManager()
        register(adapterManager, for: AdapterManager.self)

        let transactionStorage = TransactionStorage(
            databaseManager: databaseManager,
            userDefaults: defaultsStorage
        )
        register(transactionStorage, for: TransactionStorage.self)
    }
}
