import Foundation

#if canImport(WalletCore)
import WalletCore
#endif

final class AccountFactory {
    private let accountManager: AccountManager

    init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }

    func createAccount(name: String) throws -> Account {
        #if canImport(WalletCore)
        guard let wallet = HDWallet(strength: 128, passphrase: "") else {
            throw AccountFactoryError.hdWalletCreationFailed
        }
        let mnemonic = wallet.mnemonic
        return try createAccount(name: name, mnemonic: mnemonic, origin: .created)
        #else
        throw AccountFactoryError.engineUnavailable
        #endif
    }

    func createAccount(name: String, mnemonic: String, origin: AccountOrigin) throws -> Account {
        let trimmedMnemonic = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let words = trimmedMnemonic.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard (words.count == 12 || words.count == 24) else {
            throw AccountFactoryError.invalidMnemonic
        }

        #if canImport(WalletCore)
        guard HDWallet(mnemonic: trimmedMnemonic, passphrase: "") != nil else {
            throw AccountFactoryError.invalidMnemonic
        }
        #endif

        let accountType: AccountType = words.count == 12 ? .mnemonic12 : .mnemonic24
        let account = Account(
            name: name,
            type: accountType,
            origin: origin,
            backedUp: origin == .created
        )

        try accountManager.storeWords(trimmedMnemonic, for: account.id)
        accountManager.save(account: account)
        accountManager.set(activeAccountId: account.id)
        accountManager.set(lastCreatedAccount: account)

        return account
    }

    func createPrivateKeyAccount(name: String, privateKey: String, chainID: String) throws -> Account {
        let trimmedKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw AccountFactoryError.invalidPrivateKey
        }

        let account = Account(
            name: name,
            type: .privateKey,
            origin: .imported
        )

        try accountManager.storePrivateKey(trimmedKey, for: account.id)
        accountManager.save(account: account)
        accountManager.set(activeAccountId: account.id)
        accountManager.set(lastCreatedAccount: account)

        return account
    }

    func createWatchAccount(name: String) throws -> Account {
        let account = Account(
            name: name,
            type: .watchAddress,
            origin: .imported
        )

        accountManager.save(account: account)
        accountManager.set(activeAccountId: account.id)
        accountManager.set(lastCreatedAccount: account)

        return account
    }

    func deriveAddresses(for account: Account, chains: [WalletNetwork]) throws -> [WalletChain] {
        switch account.type {
        case .mnemonic12, .mnemonic24:
            guard let mnemonic = accountManager.loadWords(for: account.id),
                  !mnemonic.isEmpty else {
                throw AccountFactoryError.missingMnemonic
            }
            return try WalletCoreBridge.deriveChains(mnemonic: mnemonic, chains: chains)

        case .privateKey:
            guard let privateKey = accountManager.loadPrivateKey(for: account.id),
                  !privateKey.isEmpty else {
                throw AccountFactoryError.missingPrivateKey
            }
            return chains.compactMap { chain in
                try? WalletCoreBridge.privateKeyChain(
                    privateKey: privateKey,
                    chainID: chain.rawValue
                )
            }

        case .watchAddress:
            return []
        }
    }

    func defaultWallets(for account: Account, chains: [WalletChain]) -> [Wallet] {
        chains.map { chain in
            Wallet(
                tokenQueryID: "\(chain.id)|native",
                accountID: account.id,
                coinName: chain.name,
                coinCode: chain.symbol
            )
        }
    }
}

enum AccountFactoryError: LocalizedError {
    case engineUnavailable
    case hdWalletCreationFailed
    case invalidMnemonic
    case invalidPrivateKey
    case missingMnemonic
    case missingPrivateKey

    var errorDescription: String? {
        switch self {
        case .engineUnavailable:
            return "The wallet engine is unavailable on this build."
        case .hdWalletCreationFailed:
            return "Failed to create a new HD wallet."
        case .invalidMnemonic:
            return "That recovery phrase could not be opened. Check the words and spacing."
        case .invalidPrivateKey:
            return "That private key could not be opened."
        case .missingMnemonic:
            return "The recovery phrase is missing from secure storage."
        case .missingPrivateKey:
            return "The private key is missing from secure storage."
        }
    }
}
