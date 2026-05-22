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
        XCTAssertEqual(Set(store.chains.map(\.id)), Set(WalletNetwork.allCases.map(\.rawValue)))
        XCTAssertFalse(store.passcodeConfigured)
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

    func testCreateWalletDerivesMultichainAddresses() throws {
        let material = try WalletCoreBridge.createWallet()

        XCTAssertEqual(Set(material.chains.map(\.id)), Set(WalletNetwork.allCases.map(\.rawValue)))
        XCTAssertTrue(material.chains.allSatisfy { WalletCoreBridge.validateAddress($0.address, chainID: $0.id) })
    }

    func testEthereumPrivateKeyImportCreatesEthereumChain() throws {
        let material = try WalletCoreBridge.importPrivateKey(
            "4c0883a69102937d6231471b5dbb6204fe5129617082791ef39b4e2f2f6f1f36",
            chainID: WalletNetwork.ethereum.rawValue
        )

        XCTAssertEqual(material.chains.map(\.id), [WalletNetwork.ethereum.rawValue])
        XCTAssertTrue(WalletCoreBridge.validateAddress(material.primaryAddress, chainID: WalletNetwork.ethereum.rawValue))
    }

    func testUnlockAppClearsLockedStateWhenAuthenticationSucceeds() async {
        let store = WalletStore(
            defaults: defaults,
            secureStore: secureStore,
            authenticator: StubDeviceAuthenticator(result: true)
        )

        XCTAssertNil(store.createWallet())
        XCTAssertNil(store.setPasscode("123456"))
        store.lockApp(reason: .launch)
        XCTAssertTrue(store.isAppLocked)

        let unlocked = await store.unlockWithFaceID()
        XCTAssertTrue(unlocked)
        XCTAssertFalse(store.isAppLocked)
    }

    func testPasscodeVerificationUnlocksWallet() {
        let store = WalletStore(
            defaults: defaults,
            secureStore: secureStore,
            authenticator: StubDeviceAuthenticator(result: true)
        )

        XCTAssertNil(store.createWallet())
        XCTAssertNil(store.setPasscode("123456"))
        store.lockApp(reason: .background)

        XCTAssertFalse(store.verifyPasscode("000000"))
        XCTAssertTrue(store.isAppLocked)
        XCTAssertTrue(store.verifyPasscode("123456"))
        XCTAssertFalse(store.isAppLocked)
    }

    func testEncryptedSyncRestoreRoundTrip() {
        let ubiquitousStore = NSUbiquitousKeyValueStore.default
        ubiquitousStore.removeObject(forKey: "unite.sync.wallet")

        let sourceStore = WalletStore(
            defaults: defaults,
            secureStore: secureStore,
            authenticator: StubDeviceAuthenticator(result: true),
            ubiquitousStore: ubiquitousStore
        )

        XCTAssertNil(sourceStore.createWallet())
        XCTAssertNil(sourceStore.setPasscode("123456"))
        XCTAssertNil(sourceStore.syncEncryptedWallet(passcode: "123456"))
        XCTAssertTrue(sourceStore.hasSyncBackup)

        let restoreSuiteName = "RunnerTests.Restore.\(UUID().uuidString)"
        let restoreDefaults = UserDefaults(suiteName: restoreSuiteName)!
        restoreDefaults.removePersistentDomain(forName: restoreSuiteName)
        let restoreSecureStore = InMemorySecureStore()
        let restoredStore = WalletStore(
            defaults: restoreDefaults,
            secureStore: restoreSecureStore,
            authenticator: StubDeviceAuthenticator(result: true),
            ubiquitousStore: ubiquitousStore
        )

        XCTAssertNil(restoredStore.restoreWalletFromSync(passcode: "123456"))
        XCTAssertTrue(restoredStore.hasWallet)
        XCTAssertTrue(restoredStore.passcodeConfigured)
        XCTAssertEqual(restoredStore.chains.map(\.id), sourceStore.chains.map(\.id))
        XCTAssertEqual(restoredStore.mnemonic, sourceStore.mnemonic)

        ubiquitousStore.removeObject(forKey: "unite.sync.wallet")
    }
}
