import Foundation
import Combine

#if canImport(GRDB)
import GRDB

// MARK: - Database Schema

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?
    private let setupLock = NSLock()
    private var isSetup = false

    private init() {}

    // MARK: - Setup

    func setup() throws {
        setupLock.lock()
        defer { setupLock.unlock() }

        guard !isSetup else { return }

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            db.trace { event in
                #if DEBUG
                if case .statement(let statement) = event {
                    print("[GRDB] \(statement.sql.prefix(200))")
                }
                #endif
            }
        }
        configuration.label = AppConfig.label

        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbURL = appSupport.appendingPathComponent(AppConfig.dbFileName)

        let queue = try DatabaseQueue(path: dbURL.path, configuration: configuration)
        self.dbQueue = queue

        try migrate(queue: queue)
        try migrateFromUserDefaultsIfNeeded(queue: queue)

        isSetup = true
    }

    var queue: DatabaseQueue? {
        dbQueue
    }

    func read<T>(_ block: @escaping (Database) throws -> T) throws -> T {
        guard let queue = dbQueue else {
            throw DatabaseError.notConfigured
        }
        return try queue.read(block)
    }

    func write<T>(_ block: @escaping (Database) throws -> T) throws -> T {
        guard let queue = dbQueue else {
            throw DatabaseError.notConfigured
        }
        return try queue.write(block)
    }

    func writeAsync(_ block: @escaping (Database) throws -> Void) {
        guard let queue = dbQueue else { return }
        queue.asyncWrite({ db in
            try block(db)
        }, completion: { _, result in
            if case .failure(let error) = result {
                print("[DatabaseManager] async write error: \(error)")
            }
        })
    }

    // MARK: - Migrations

    private func migrate(queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "account") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("origin", .text).notNull()
                t.column("backedUp", .boolean).notNull().defaults(to: false)
                t.column("level", .integer).notNull().defaults(to: 0)
                t.column("fileBackedUp", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "wallet") { t in
                t.column("id", .text).primaryKey()
                t.column("tokenQueryID", .text).notNull()
                t.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                t.column("coinName", .text)
                t.column("coinCode", .text)
                t.column("tokenDecimals", .integer)
                t.column("coinImage", .text)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }

            try db.create(index: "wallet_on_account", on: "wallet", columns: ["accountID"])

            try db.create(table: "transaction_record") { t in
                t.column("id", .text).primaryKey()
                t.column("hash", .text).notNull()
                t.column("chainID", .text).notNull()
                t.column("accountID", .text).notNull().references("account", onDelete: .cascade)
                t.column("walletID", .text)
                t.column("type", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("fromAddress", .text).notNull()
                t.column("toAddress", .text).notNull()
                t.column("amount", .text).notNull()
                t.column("assetSymbol", .text).notNull()
                t.column("assetDecimals", .integer).notNull()
                t.column("fee", .text)
                t.column("feeSymbol", .text)
                t.column("timestamp", .datetime).notNull()
                t.column("blockNumber", .integer)
                t.column("explorerURL", .text)
                t.column("metadataJSON", .text)
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
            }

            try db.create(index: "tx_on_account_chain", on: "transaction_record", columns: ["accountID", "chainID"])
            try db.create(index: "tx_on_hash", on: "transaction_record", columns: ["hash", "chainID"])
        }

        migrator.registerMigration("v2_contacts") { db in
            try db.create(table: "contact") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("address", .text).notNull()
                t.column("chainID", .text).notNull()
                t.column("assetID", .text)
            }
        }

        migrator.registerMigration("v3_blockchain_settings") { db in
            try db.create(table: "blockchain_setting") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text)
                t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
        }

        try migrator.migrate(queue)
    }

    // MARK: - One-Time UserDefaults Migration

    private func migrateFromUserDefaultsIfNeeded(queue: DatabaseQueue) throws {
        let defaults = UserDefaults.standard
        let migrationKey = "unite.grdb.migration.v1.complete"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        try queue.write { db in
            // Migrate accounts
            if let indexData = defaults.data(forKey: "unite.accounts.index"),
               let ids = try? decoder.decode([String].self, from: indexData) {
                for accountID in ids {
                    if let data = defaults.data(forKey: "unite.account.\(accountID)"),
                       let account = try? decoder.decode(Account.self, from: data) {
                        var record = AccountRecord.from(account: account)
                        try record.save(db)
                    }
                }
            }

            // Migrate wallets
            let walletKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("unite.wallets.") }
            for key in walletKeys {
                let accountID = String(key.dropFirst("unite.wallets.".count))
                if let data = defaults.data(forKey: key),
                   let wallets = try? decoder.decode([Wallet].self, from: data) {
                    for (idx, var wallet) in wallets.enumerated() {
                        var record = WalletRecord.from(wallet: wallet, sortOrder: idx)
                        try record.save(db)
                    }
                }
            }

            // Migrate contacts
            if let data = defaults.data(forKey: "unite.contacts"),
               let contacts = try? decoder.decode([WalletContact].self, from: data) {
                for contact in contacts {
                    var record = ContactRecord.from(contact: contact)
                    try record.save(db)
                }
            }

            // Migrate active account ID
            if let activeID = defaults.string(forKey: "unite.active.account.level.0") {
                var setting = BlockchainSetting(
                    key: "active_account_id",
                    value: activeID,
                    updatedAt: Date()
                )
                try setting.save(db)
            }
        }

        defaults.set(true, forKey: migrationKey)
    }
}

// MARK: - Errors

enum DatabaseError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Database not configured. Call setup() first."
        }
    }
}

// MARK: - Account Record

struct AccountRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var name: String
    var type: String
    var origin: String
    var backedUp: Bool
    var level: Int
    var fileBackedUp: Bool

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let type = Column(CodingKeys.type)
        static let origin = Column(CodingKeys.origin)
        static let backedUp = Column(CodingKeys.backedUp)
        static let level = Column(CodingKeys.level)
        static let fileBackedUp = Column(CodingKeys.fileBackedUp)
    }

    func toAccount() -> Account {
        Account(
            id: id,
            name: name,
            type: AccountType(rawValue: type) ?? .mnemonic12,
            origin: AccountOrigin(rawValue: origin) ?? .created,
            backedUp: backedUp,
            level: level,
            fileBackedUp: fileBackedUp
        )
    }

    static func from(account: Account) -> AccountRecord {
        AccountRecord(
            id: account.id,
            name: account.name,
            type: account.type.rawValue,
            origin: account.origin.rawValue,
            backedUp: account.backedUp,
            level: account.level,
            fileBackedUp: account.fileBackedUp
        )
    }
}

// MARK: - Wallet Record

struct WalletRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var tokenQueryID: String
    var accountID: String
    var coinName: String?
    var coinCode: String?
    var tokenDecimals: Int?
    var coinImage: String?
    var sortOrder: Int

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let tokenQueryID = Column(CodingKeys.tokenQueryID)
        static let accountID = Column(CodingKeys.accountID)
        static let coinName = Column(CodingKeys.coinName)
        static let coinCode = Column(CodingKeys.coinCode)
        static let tokenDecimals = Column(CodingKeys.tokenDecimals)
        static let coinImage = Column(CodingKeys.coinImage)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }

    func toWallet() -> Wallet {
        Wallet(
            id: id,
            tokenQueryID: tokenQueryID,
            accountID: accountID,
            coinName: coinName,
            coinCode: coinCode,
            tokenDecimals: tokenDecimals,
            coinImage: coinImage
        )
    }

    static func from(wallet: Wallet, sortOrder: Int) -> WalletRecord {
        WalletRecord(
            id: wallet.id,
            tokenQueryID: wallet.tokenQueryID,
            accountID: wallet.accountID,
            coinName: wallet.coinName,
            coinCode: wallet.coinCode,
            tokenDecimals: wallet.tokenDecimals,
            coinImage: wallet.coinImage,
            sortOrder: sortOrder
        )
    }
}

// MARK: - Transaction Record

struct TransactionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var hash: String
    var chainID: String
    var accountID: String
    var walletID: String?
    var type: String
    var status: String
    var fromAddress: String
    var toAddress: String
    var amount: String
    var assetSymbol: String
    var assetDecimals: Int
    var fee: String?
    var feeSymbol: String?
    var timestamp: Date
    var blockNumber: Int?
    var explorerURL: String?
    var metadataJSON: String?
    var sortIndex: Int

    enum TransactionType: String {
        case send
        case receive
        case swap
        case approve
        case contractCall
        case stake
        case unstake
        case claim
    }

    enum TransactionStatus: String {
        case pending
        case confirmed
        case failed
        case dropped
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let hash = Column(CodingKeys.hash)
        static let chainID = Column(CodingKeys.chainID)
        static let accountID = Column(CodingKeys.accountID)
        static let walletID = Column(CodingKeys.walletID)
        static let type = Column(CodingKeys.type)
        static let status = Column(CodingKeys.status)
        static let fromAddress = Column(CodingKeys.fromAddress)
        static let toAddress = Column(CodingKeys.toAddress)
        static let amount = Column(CodingKeys.amount)
        static let assetSymbol = Column(CodingKeys.assetSymbol)
        static let assetDecimals = Column(CodingKeys.assetDecimals)
        static let fee = Column(CodingKeys.fee)
        static let feeSymbol = Column(CodingKeys.feeSymbol)
        static let timestamp = Column(CodingKeys.timestamp)
        static let blockNumber = Column(CodingKeys.blockNumber)
        static let explorerURL = Column(CodingKeys.explorerURL)
        static let metadataJSON = Column(CodingKeys.metadataJSON)
        static let sortIndex = Column(CodingKeys.sortIndex)
    }
}

// MARK: - Contact Record

struct ContactRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var name: String
    var address: String
    var chainID: String
    var assetID: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let address = Column(CodingKeys.address)
        static let chainID = Column(CodingKeys.chainID)
        static let assetID = Column(CodingKeys.assetID)
    }

    func toContact() -> WalletContact {
        WalletContact(
            id: id,
            name: name,
            address: address,
            chainID: chainID,
            assetID: assetID
        )
    }

    static func from(contact: WalletContact) -> ContactRecord {
        ContactRecord(
            id: contact.id,
            name: contact.name,
            address: contact.address,
            chainID: contact.chainID,
            assetID: contact.assetID
        )
    }
}

// MARK: - Blockchain Setting Record

struct BlockchainSetting: Codable, FetchableRecord, MutablePersistableRecord {
    var key: String
    var value: String?
    var updatedAt: Date

    enum Columns {
        static let key = Column(CodingKeys.key)
        static let value = Column(CodingKeys.value)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

#else

// MARK: - Stub when GRDB is unavailable

final class DatabaseManager {
    static let shared = DatabaseManager()

    private init() {}

    func setup() throws {
        // No-op when GRDB is not linked
    }

    func read<T>(_ block: @escaping (Any) throws -> T) throws -> T {
        throw DatabaseError.notConfigured
    }

    func write<T>(_ block: @escaping (Any) throws -> T) throws -> T {
        throw DatabaseError.notConfigured
    }

    func writeAsync(_ block: @escaping (Any) throws -> Void) {}
}

enum DatabaseError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        "Database not available. GRDB is not linked."
    }
}

// Forward-declare record types as stubs
struct AccountRecord {}
struct WalletRecord {}
struct TransactionRecord {}
struct ContactRecord {}
struct BlockchainSetting {}

#endif