import XCTest
@testable import Runner

@MainActor
final class RunnerTests: XCTestCase {
    private final class URLProtocolStub: URLProtocol {
        static var handler: ((URLRequest) throws -> (Int, Data))?

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            do {
                let (statusCode, data) = try handler(request)
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private final class InMemoryUbiquitousStore: UbiquitousKeyValueStoring {
        private var values: [String: Any] = [:]

        func string(forKey aKey: String) -> String? {
            values[aKey] as? String
        }

        func set(_ aValue: Any?, forKey aKey: String) {
            values[aKey] = aValue
        }

        func removeObject(forKey aKey: String) {
            values.removeValue(forKey: aKey)
        }

        func synchronize() -> Bool {
            true
        }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var secureStore: InMemorySecureStore!

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(URLProtocolStub.self)
        suiteName = "RunnerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        secureStore = InMemorySecureStore()
    }

    override func tearDown() {
        URLProtocolStub.handler = nil
        URLProtocol.unregisterClass(URLProtocolStub.self)
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

    func testImportRejectsInvalidMnemonic() async {
        let store = WalletStore(
            defaults: defaults,
            secureStore: secureStore,
            authenticator: StubDeviceAuthenticator(result: true)
        )

        let result = await store.importWallet(secret: "one two three", asPrivateKey: false)
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
        let ubiquitousStore = InMemoryUbiquitousStore()
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

    func testBitcoinAndSolanaPrivateKeyImportCreateMatchingChains() throws {
        let hexKey = "4c0883a69102937d6231471b5dbb6204fe5129617082791ef39b4e2f2f6f1f36"
        let bitcoin = try WalletCoreBridge.importPrivateKey(hexKey, chainID: WalletNetwork.bitcoin.rawValue)
        XCTAssertEqual(bitcoin.chains.map(\.id), [WalletNetwork.bitcoin.rawValue])
        XCTAssertTrue(WalletCoreBridge.validateAddress(bitcoin.primaryAddress, chainID: WalletNetwork.bitcoin.rawValue))

        let generated = try WalletCoreBridge.createWallet()
        let solanaChain = try XCTUnwrap(generated.chains.first(where: { $0.id == WalletNetwork.solana.rawValue }))
        let solanaKey = try WalletCoreBridge.privateKeyData(
            for: WalletCoreBridge.signingContext(
                mnemonic: generated.mnemonic,
                privateKey: "",
                chain: solanaChain
            )
        ).hexString
        let solana = try WalletCoreBridge.importPrivateKey(solanaKey, chainID: WalletNetwork.solana.rawValue)
        XCTAssertEqual(solana.chains.map(\.id), [WalletNetwork.solana.rawValue])
        XCTAssertTrue(WalletCoreBridge.validateAddress(solana.primaryAddress, chainID: WalletNetwork.solana.rawValue))
    }

    func testMnemonicAndImportedKeySigningContextsResolveAcrossFamilies() throws {
        let generated = try WalletCoreBridge.createWallet()
        let mnemonicBitcoin = try XCTUnwrap(generated.chains.first(where: { $0.id == WalletNetwork.bitcoin.rawValue }))
        let mnemonicEthereum = try XCTUnwrap(generated.chains.first(where: { $0.id == WalletNetwork.ethereum.rawValue }))

        let mnemonicBitcoinKey = try WalletCoreBridge.privateKeyData(
            for: WalletCoreBridge.signingContext(mnemonic: generated.mnemonic, privateKey: "", chain: mnemonicBitcoin)
        )
        let mnemonicEthereumKey = try WalletCoreBridge.privateKeyData(
            for: WalletCoreBridge.signingContext(mnemonic: generated.mnemonic, privateKey: "", chain: mnemonicEthereum)
        )
        XCTAssertFalse(mnemonicBitcoinKey.isEmpty)
        XCTAssertFalse(mnemonicEthereumKey.isEmpty)
        XCTAssertNotEqual(mnemonicBitcoinKey, mnemonicEthereumKey)

        let importedHexKey = "4c0883a69102937d6231471b5dbb6204fe5129617082791ef39b4e2f2f6f1f36"
        let importedBitcoin = try XCTUnwrap(
            WalletCoreBridge.importPrivateKey(importedHexKey, chainID: WalletNetwork.bitcoin.rawValue).chains.first
        )
        let importedEthereum = try XCTUnwrap(
            WalletCoreBridge.importPrivateKey(importedHexKey, chainID: WalletNetwork.ethereum.rawValue).chains.first
        )

        XCTAssertEqual(
            try WalletCoreBridge.privateKeyData(
                for: WalletCoreBridge.signingContext(mnemonic: "", privateKey: importedHexKey, chain: importedBitcoin)
            ),
            Data(hexString: importedHexKey)
        )
        XCTAssertEqual(
            try WalletCoreBridge.privateKeyData(
                for: WalletCoreBridge.signingContext(mnemonic: "", privateKey: importedHexKey, chain: importedEthereum)
            ),
            Data(hexString: importedHexKey)
        )
    }

    func testEthereumNativeQuoteUsesCoreSendPath() async throws {
        URLProtocolStub.handler = { request in
            let method = try Self.rpcMethod(from: request)
            switch method {
            case "eth_gasPrice":
                return (200, #"{"result":"0x3b9aca00"}"#.data(using: .utf8)!)
            case "eth_getBlockByNumber":
                return (200, #"{"result":{"baseFeePerGas":"0x3b9aca00"}}"#.data(using: .utf8)!)
            case "eth_maxPriorityFeePerGas":
                return (200, #"{"result":"0x77359400"}"#.data(using: .utf8)!)
            default:
                throw URLError(.badServerResponse)
            }
        }

        let source = try XCTUnwrap(
            WalletCoreBridge.importPrivateKey(
                "4c0883a69102937d6231471b5dbb6204fe5129617082791ef39b4e2f2f6f1f36",
                chainID: WalletNetwork.ethereum.rawValue
            ).chains.first
        )
        let recipient = try WalletCoreBridge.importPrivateKey(
            "8f2a5594908f5f417f0ff205f4f919b9f48f9d89d050f2445f6f7a8d7df3a4f1",
            chainID: WalletNetwork.ethereum.rawValue
        ).primaryAddress
        let asset = WalletAssetBalance(
            chainID: WalletNetwork.ethereum.rawValue,
            symbol: "ETH",
            name: "Ethereum",
            decimals: 18,
            balance: Decimal(string: "0.2")!,
            isNative: true,
            contractAddress: nil,
            tokenStandard: .native,
            accountAddress: source.address
        )
        let draft = TransferDraft(chainID: source.id, assetID: asset.id, recipient: recipient, amount: Decimal(string: "0.1")!)

        let quote = try await EvmTransactionService(network: .ethereum).quote(
            draft: draft,
            asset: asset,
            sourceChain: source,
            signing: WalletCoreBridge.signingContext(mnemonic: "", privateKey: "unused", chain: source)
        )

        XCTAssertEqual(quote.asset.symbol, "ETH")
        XCTAssertEqual(quote.feeSymbol, "ETH")
        XCTAssertEqual(quote.networkDetail, "max 4 gwei")
        XCTAssertEqual(quote.fee, Decimal(string: "0.000084")!)
        XCTAssertEqual(quote.totalDebit, Decimal(string: "0.100084")!)
    }

    func testBaseERC20QuoteUsesCoreSendPath() async throws {
        URLProtocolStub.handler = { request in
            let method = try Self.rpcMethod(from: request)
            switch method {
            case "eth_gasPrice":
                return (200, #"{"result":"0x3b9aca00"}"#.data(using: .utf8)!)
            case "eth_getBlockByNumber":
                return (200, #"{"result":{"baseFeePerGas":"0x3b9aca00"}}"#.data(using: .utf8)!)
            case "eth_maxPriorityFeePerGas":
                return (200, #"{"result":"0x3b9aca00"}"#.data(using: .utf8)!)
            default:
                throw URLError(.badServerResponse)
            }
        }

        let source = try XCTUnwrap(
            WalletCoreBridge.importPrivateKey(
                "4c0883a69102937d6231471b5dbb6204fe5129617082791ef39b4e2f2f6f1f36",
                chainID: WalletNetwork.base.rawValue
            ).chains.first
        )
        let recipient = try WalletCoreBridge.importPrivateKey(
            "8f2a5594908f5f417f0ff205f4f919b9f48f9d89d050f2445f6f7a8d7df3a4f1",
            chainID: WalletNetwork.base.rawValue
        ).primaryAddress
        let asset = WalletAssetBalance(
            chainID: WalletNetwork.base.rawValue,
            symbol: "USDC",
            name: "USD Coin",
            decimals: 6,
            balance: Decimal(string: "250")!,
            isNative: false,
            contractAddress: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
            tokenStandard: .erc20,
            accountAddress: source.address
        )
        let draft = TransferDraft(chainID: source.id, assetID: asset.id, recipient: recipient, amount: Decimal(string: "10")!)

        let quote = try await EvmTransactionService(network: .base).quote(
            draft: draft,
            asset: asset,
            sourceChain: source,
            signing: WalletCoreBridge.signingContext(mnemonic: "", privateKey: "unused", chain: source)
        )

        XCTAssertEqual(quote.asset.symbol, "USDC")
        XCTAssertEqual(quote.feeSymbol, "ETH")
        XCTAssertEqual(quote.networkDetail, "max 3 gwei")
        XCTAssertEqual(quote.fee, Decimal(string: "0.000195")!)
        XCTAssertEqual(quote.totalDebit, Decimal(string: "10")!)
    }

    func testBitcoinQuoteUsesCoreSendPath() async throws {
        URLProtocolStub.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.absoluteString.contains("/utxo") {
                return (200, #"[{"txid":"00f06787cfca25279c834f4d6414c0118d6f0c63e5d15a8d2d8a15bca6f1a2bc","vout":0,"value":5000000,"status":{"confirmed":true,"block_height":1,"block_hash":"abc","block_time":1}}]"#.data(using: .utf8)!)
            }
            if url.absoluteString.contains("mempool.space") {
                return (200, #"{"fastestFee":5}"#.data(using: .utf8)!)
            }
            throw URLError(.badServerResponse)
        }

        let source = try XCTUnwrap(
            WalletCoreBridge.importPrivateKey(
                "4c0883a69102937d6231471b5dbb6204fe5129617082791ef39b4e2f2f6f1f36",
                chainID: WalletNetwork.bitcoin.rawValue
            ).chains.first
        )
        let recipient = try WalletCoreBridge.importPrivateKey(
            "8f2a5594908f5f417f0ff205f4f919b9f48f9d89d050f2445f6f7a8d7df3a4f1",
            chainID: WalletNetwork.bitcoin.rawValue
        ).primaryAddress
        let asset = WalletAssetBalance(
            chainID: WalletNetwork.bitcoin.rawValue,
            symbol: "BTC",
            name: "Bitcoin",
            decimals: 8,
            balance: Decimal(string: "0.05")!,
            isNative: true,
            contractAddress: nil,
            tokenStandard: .native,
            accountAddress: source.address
        )
        let draft = TransferDraft(chainID: source.id, assetID: asset.id, recipient: recipient, amount: Decimal(string: "0.01")!)

        let quote = try await UtxoTransactionService(network: .bitcoin).quote(
            draft: draft,
            asset: asset,
            sourceChain: source,
            signing: WalletCoreBridge.signingContext(mnemonic: "", privateKey: "unused", chain: source)
        )

        XCTAssertEqual(quote.asset.symbol, "BTC")
        XCTAssertEqual(quote.feeSymbol, "BTC")
        XCTAssertEqual(quote.networkDetail, "5 sat/vB")
        XCTAssertEqual(quote.fee, Decimal(string: "0.00001125")!)
        XCTAssertEqual(quote.totalDebit, Decimal(string: "0.01001125")!)
    }

    private static func rpcMethod(from request: URLRequest) throws -> String {
        let body = try XCTUnwrap(request.httpBody ?? data(from: request.httpBodyStream))
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        return try XCTUnwrap(payload?["method"] as? String)
    }

    private static func data(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        let bufferSize = 1024
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }

        return data.isEmpty ? nil : data
    }
}
