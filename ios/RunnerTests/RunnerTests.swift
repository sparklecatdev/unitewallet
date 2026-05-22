import XCTest
@testable import Runner

@MainActor
final class RunnerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var secureStore: InMemorySecureStore!

    override func setUp() {
        super.setUp()
        suiteName = "RunnerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        secureStore = InMemorySecureStore()
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        suiteName = nil
        defaults = nil
        secureStore = nil
        super.tearDown()
    }

    func testCreateWalletStoresSecretsInSecureStoreOnly() throws {
        let store = WalletStore(
            defaults: defaults,
            secureStore: secureStore,
            authenticator: StubDeviceAuthenticator(result: true)
        )

        XCTAssertNil(store.createWallet())
        XCTAssertTrue(store.hasWallet)
        XCTAssertFalse(store.mnemonic.isEmpty)
        XCTAssertFalse(store.privateKey.isEmpty)
        XCTAssertEqual(defaults.string(forKey: "unite.native.mnemonic"), nil)
        XCTAssertEqual(defaults.string(forKey: "unite.native.privateKey"), nil)
        XCTAssertNotNil(try secureStore.string(for: WalletStore.SecureKey.mnemonic))
        XCTAssertNotNil(try secureStore.string(for: WalletStore.SecureKey.privateKey))
    }

    func testImportRejectsInvalidMnemonic() {
        let store = WalletStore(
            defaults: defaults,
            secureStore: secureStore,
            authenticator: StubDeviceAuthenticator(result: true)
        )

        let result = store.importWallet(secret: "one two three", asPrivateKey: false)
        XCTAssertEqual(result, "Recovery phrases are usually 12, 15, 18, 21, or 24 words.")
        XCTAssertFalse(store.hasWallet)
    }

    func testRemoveWalletClearsSecureStorageAndDefaults() throws {
        let store = WalletStore(
            defaults: defaults,
            secureStore: secureStore,
            authenticator: StubDeviceAuthenticator(result: true)
        )

        XCTAssertNil(store.createWallet())
        store.removeWallet()

        XCTAssertFalse(store.hasWallet)
        XCTAssertEqual(store.address, "")
        XCTAssertNil(try secureStore.string(for: WalletStore.SecureKey.mnemonic))
        XCTAssertNil(try secureStore.string(for: WalletStore.SecureKey.privateKey))
        XCTAssertNil(defaults.object(forKey: "unite.native.hasWallet"))
        XCTAssertNil(defaults.object(forKey: "unite.native.address"))
    }

    func testDerivedSolanaAddressValidates() throws {
        let material = try WalletCoreBridge.createWallet()
        XCTAssertTrue(WalletCoreBridge.validateAddress(material.primaryAddress))
        XCTAssertFalse(WalletCoreBridge.validateAddress("not-a-solana-address"))
    }

    func testUnlockAppClearsLockedStateWhenAuthenticationSucceeds() async {
        let store = WalletStore(
            defaults: defaults,
            secureStore: secureStore,
            authenticator: StubDeviceAuthenticator(result: true)
        )

        XCTAssertNil(store.createWallet())
        XCTAssertTrue(store.isAppLocked)

        let unlocked = await store.unlockApp()
        XCTAssertTrue(unlocked)
        XCTAssertFalse(store.isAppLocked)
    }
}
