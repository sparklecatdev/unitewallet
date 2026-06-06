import Foundation
import Combine

#if canImport(GRDB)
import GRDB
#endif

// MARK: - Transaction Data Model

struct TransactionModel: Identifiable, Codable, Equatable {
    let id: String
    let hash: String
    let chainID: String
    let accountID: String
    let walletID: String?
    let type: TransactionType
    let status: TransactionStatus
    let fromAddress: String
    let toAddress: String
    let amount: Decimal
    let assetSymbol: String
    let assetDecimals: Int
    let fee: Decimal?
    let feeSymbol: String?
    let timestamp: Date
    let blockNumber: Int?
    let explorerURL: URL?
    let metadata: [String: String]?

    enum TransactionType: String, Codable {
        case send
        case receive
        case swap
        case approve
        case contractCall
        case stake
        case unstake
        case claim
    }

    enum TransactionStatus: String, Codable {
        case pending
        case confirmed
        case failed
        case dropped
    }

    init(
        id: String = UUID().uuidString,
        hash: String,
        chainID: String,
        accountID: String,
        walletID: String? = nil,
        type: TransactionType,
        status: TransactionStatus,
        fromAddress: String,
        toAddress: String,
        amount: Decimal,
        assetSymbol: String,
        assetDecimals: Int,
        fee: Decimal? = nil,
        feeSymbol: String? = nil,
        timestamp: Date = Date(),
        blockNumber: Int? = nil,
        explorerURL: URL? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.hash = hash
        self.chainID = chainID
        self.accountID = accountID
        self.walletID = walletID
        self.type = type
        self.status = status
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.amount = amount
        self.assetSymbol = assetSymbol
        self.assetDecimals = assetDecimals
        self.fee = fee
        self.feeSymbol = feeSymbol
        self.timestamp = timestamp
        self.blockNumber = blockNumber
        self.explorerURL = explorerURL
        self.metadata = metadata
    }
}

// MARK: - Transaction Storage Manager

final class TransactionStorage {
    private let databaseManager: DatabaseManager
    private let userDefaults: UserDefaultsStorage

    private let transactionsSubject = CurrentValueSubject<[TransactionModel], Never>([])
    private var cancellables = Set<AnyCancellable>()

    init(databaseManager: DatabaseManager, userDefaults: UserDefaultsStorage) {
        self.databaseManager = databaseManager
        self.userDefaults = userDefaults
    }

    var transactionsPublisher: AnyPublisher<[TransactionModel], Never> {
        transactionsSubject.eraseToAnyPublisher()
    }

    // MARK: - Fetch

    func fetchTransactions(for accountID: String) throws -> [TransactionModel] {
        #if canImport(GRDB)
        return try databaseManager.read { db in
            try TransactionRecord
                .filter(TransactionRecord.Columns.accountID == accountID)
                .order(TransactionRecord.Columns.sortIndex.desc)
                .fetchAll(db)
                .map { $0.toTransactionModel() }
        }
        #else
        return userDefaults.codable(forKey: "unite.transactions.\(accountID)") ?? []
        #endif
    }

    func fetchTransactions(for accountID: String, chainID: String) throws -> [TransactionModel] {
        #if canImport(GRDB)
        return try databaseManager.read { db in
            try TransactionRecord
                .filter(TransactionRecord.Columns.accountID == accountID && TransactionRecord.Columns.chainID == chainID)
                .order(TransactionRecord.Columns.sortIndex.desc)
                .fetchAll(db)
                .map { $0.toTransactionModel() }
        }
        #else
        let all: [TransactionModel] = userDefaults.codable(forKey: "unite.transactions.\(accountID)") ?? []
        return all.filter { $0.chainID == chainID }
        #endif
    }

    func fetchTransaction(byHash hash: String, chainID: String) throws -> TransactionModel? {
        #if canImport(GRDB)
        return try databaseManager.read { db in
            try TransactionRecord
                .filter(TransactionRecord.Columns.hash == hash && TransactionRecord.Columns.chainID == chainID)
                .fetchOne(db)?
                .toTransactionModel()
        }
        #else
        return nil
        #endif
    }

    // MARK: - Save

    func save(transaction: TransactionModel) throws {
        let sortIndex = Int(transaction.timestamp.timeIntervalSince1970 * 1000)

        #if canImport(GRDB)
        let record = TransactionRecord(
            id: transaction.id,
            hash: transaction.hash,
            chainID: transaction.chainID,
            accountID: transaction.accountID,
            walletID: transaction.walletID,
            type: transaction.type.rawValue,
            status: transaction.status.rawValue,
            fromAddress: transaction.fromAddress,
            toAddress: transaction.toAddress,
            amount: transaction.amount.description,
            assetSymbol: transaction.assetSymbol,
            assetDecimals: transaction.assetDecimals,
            fee: transaction.fee?.description,
            feeSymbol: transaction.feeSymbol,
            timestamp: transaction.timestamp,
            blockNumber: transaction.blockNumber,
            explorerURL: transaction.explorerURL?.absoluteString,
            metadataJSON: transaction.metadata.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) },
            sortIndex: sortIndex
        )

        try databaseManager.write { db in
            try record.upsert(db)
        }
        #else
        var all: [TransactionModel] = userDefaults.codable(forKey: "unite.transactions.\(transaction.accountID)") ?? []
        if let idx = all.firstIndex(where: { $0.hash == transaction.hash && $0.chainID == transaction.chainID }) {
            all[idx] = transaction
        } else {
            all.append(transaction)
        }
        userDefaults.set(codable: all, forKey: "unite.transactions.\(transaction.accountID)")
        #endif

        notifyChange(for: transaction.accountID)
    }

    func save(transactions: [TransactionModel], for accountID: String) throws {
        #if canImport(GRDB)
        try databaseManager.write { db in
            for tx in transactions {
                var record = TransactionRecord(
                    id: tx.id,
                    hash: tx.hash,
                    chainID: tx.chainID,
                    accountID: tx.accountID,
                    walletID: tx.walletID,
                    type: tx.type.rawValue,
                    status: tx.status.rawValue,
                    fromAddress: tx.fromAddress,
                    toAddress: tx.toAddress,
                    amount: tx.amount.description,
                    assetSymbol: tx.assetSymbol,
                    assetDecimals: tx.assetDecimals,
                    fee: tx.fee?.description,
                    feeSymbol: tx.feeSymbol,
                    timestamp: tx.timestamp,
                    blockNumber: tx.blockNumber,
                    explorerURL: tx.explorerURL?.absoluteString,
                    metadataJSON: tx.metadata.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) },
                    sortIndex: Int(tx.timestamp.timeIntervalSince1970 * 1000)
                )
                try record.upsert(db)
            }
        }
        #else
        var all: [TransactionModel] = userDefaults.codable(forKey: "unite.transactions.\(accountID)") ?? []
        let existingHashes = Set(all.map { "\($0.hash):\($0.chainID)" })
        for tx in transactions {
            let key = "\(tx.hash):\(tx.chainID)"
            if !existingHashes.contains(key) {
                all.append(tx)
            }
        }
        userDefaults.set(codable: all, forKey: "unite.transactions.\(accountID)")
        #endif

        notifyChange(for: accountID)
    }

    // MARK: - Update Status

    func updateStatus(_ status: TransactionModel.TransactionStatus, for hash: String, chainID: String) throws {
        #if canImport(GRDB)
        try databaseManager.write { db in
            try TransactionRecord
                .filter(TransactionRecord.Columns.hash == hash && TransactionRecord.Columns.chainID == chainID)
                .updateAll(db, TransactionRecord.Columns.status.set(to: status.rawValue))
        }
        #endif
    }

    // MARK: - Delete

    func delete(transaction: TransactionModel) throws {
        #if canImport(GRDB)
        try databaseManager.write { db in
            try TransactionRecord
                .filter(TransactionRecord.Columns.id == transaction.id)
                .deleteAll(db)
        }
        #else
        var all: [TransactionModel] = userDefaults.codable(forKey: "unite.transactions.\(transaction.accountID)") ?? []
        all.removeAll { $0.id == transaction.id }
        userDefaults.set(codable: all, forKey: "unite.transactions.\(transaction.accountID)")
        #endif

        notifyChange(for: transaction.accountID)
    }

    func clearTransactions(for accountID: String) throws {
        #if canImport(GRDB)
        try databaseManager.write { db in
            try TransactionRecord
                .filter(TransactionRecord.Columns.accountID == accountID)
                .deleteAll(db)
        }
        #else
        userDefaults.removeValue(forKey: "unite.transactions.\(accountID)")
        #endif

        transactionsSubject.send([])
    }

    // MARK: - Blockchain Settings

    func blockchainSetting(forKey key: String) throws -> String? {
        #if canImport(GRDB)
        return try databaseManager.read { db in
            try BlockchainSetting
                .filter(BlockchainSetting.Columns.key == key)
                .fetchOne(db)?
                .value
        }
        #else
        return userDefaults.string(forKey: key)
        #endif
    }

    func setBlockchainSetting(value: String?, forKey key: String) throws {
        #if canImport(GRDB)
        let record = BlockchainSetting(key: key, value: value, updatedAt: Date())
        try databaseManager.write { db in
            try record.upsert(db)
        }
        #else
        userDefaults.set(string: value, forKey: key)
        #endif
    }

    // MARK: - Private

    private func notifyChange(for accountID: String) {
        do {
            let transactions = try fetchTransactions(for: accountID)
            transactionsSubject.send(transactions)
        } catch {
            print("[TransactionStorage] failed to reload: \(error)")
        }
    }
}

#if canImport(GRDB)
private extension TransactionRecord {
    func toTransactionModel() -> TransactionModel {
        var metadata: [String: String]?
        if let json = metadataJSON, let data = json.data(using: .utf8) {
            metadata = try? JSONDecoder().decode([String: String].self, from: data)
        }

        return TransactionModel(
            id: id,
            hash: hash,
            chainID: chainID,
            accountID: accountID,
            walletID: walletID,
            type: TransactionModel.TransactionType(rawValue: type) ?? .send,
            status: TransactionModel.TransactionStatus(rawValue: status) ?? .pending,
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: Decimal(string: amount) ?? 0,
            assetSymbol: assetSymbol,
            assetDecimals: assetDecimals,
            fee: fee.flatMap { Decimal(string: $0) },
            feeSymbol: feeSymbol,
            timestamp: timestamp,
            blockNumber: blockNumber,
            explorerURL: explorerURL.flatMap { URL(string: $0) },
            metadata: metadata
        )
    }
}
#endif
