import Foundation

struct Account: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    let type: AccountType
    let origin: AccountOrigin
    var backedUp: Bool
    var level: Int
    var fileBackedUp: Bool

    var isActive: Bool { level <= 1 }

    init(
        id: String = UUID().uuidString,
        name: String,
        type: AccountType,
        origin: AccountOrigin,
        backedUp: Bool = false,
        level: Int = 0,
        fileBackedUp: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.origin = origin
        self.backedUp = backedUp
        self.level = level
        self.fileBackedUp = fileBackedUp
    }
}

enum AccountType: String, Codable {
    case mnemonic12
    case mnemonic24
    case privateKey
    case watchAddress
}

enum AccountOrigin: String, Codable {
    case created
    case restored
    case imported
}

struct AccountStorageKeys {
    static func wordsKey(accountId: String) -> String {
        "mnemonic_\(accountId)_words"
    }

    static func saltKey(accountId: String) -> String {
        "mnemonic_\(accountId)_salt"
    }

    static func dataKey(accountId: String) -> String {
        "account_\(accountId)_data"
    }

    static func privateKeyKey(accountId: String) -> String {
        "account_\(accountId)_private_key"
    }

    static func activeAccountIdKey(level: Int) -> String {
        "unite.active.account.level.\(level)"
    }
}
