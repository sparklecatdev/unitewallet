import Foundation
import Combine

#if canImport(GRDB)
import GRDB
#endif

struct WalletContact: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var address: String
    var chainID: String
    var assetID: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        address: String,
        chainID: String,
        assetID: String? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chainID = chainID
        self.assetID = assetID
    }

    var shortAddress: String {
        guard address.count > 14 else { return address }
        return "\(address.prefix(6))...\(address.suffix(6))"
    }
}

final class ContactBookManager {
    private let userDefaults: UserDefaultsStorage
    private let databaseManager: DatabaseManager
    private let contactsSubject = CurrentValueSubject<[WalletContact], Never>([])

    private static let storageKey = "unite.contacts"

    init(userDefaultsStorage: UserDefaultsStorage, databaseManager: DatabaseManager) {
        self.userDefaults = userDefaultsStorage
        self.databaseManager = databaseManager
        loadContacts()
    }

    var contacts: [WalletContact] {
        contactsSubject.value
    }

    var contactsPublisher: AnyPublisher<[WalletContact], Never> {
        contactsSubject.eraseToAnyPublisher()
    }

    func save(contact: WalletContact) {
        var current = contacts
        if let index = current.firstIndex(where: { $0.id == contact.id }) {
            current[index] = contact
        } else {
            current.append(contact)
        }
        persist(contacts: current)
    }

    func delete(contact: WalletContact) {
        var current = contacts
        current.removeAll { $0.id == contact.id }
        persist(contacts: current)
    }

    func contact(for address: String, chainID: String) -> WalletContact? {
        contacts.first { $0.address.lowercased() == address.lowercased() && $0.chainID == chainID }
    }

    private func loadContacts() {
        #if canImport(GRDB)
        do {
            let records = try databaseManager.read { db in
                try ContactRecord.fetchAll(db)
            }
            if !records.isEmpty {
                contactsSubject.send(records.map { $0.toContact() })
                return
            }
        } catch {
            print("[ContactBookManager] failed to load from db: \(error)")
        }
        #endif

        // Fallback: load from UserDefaults
        guard let data = userDefaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([WalletContact].self, from: data) else {
            contactsSubject.send([])
            return
        }
        contactsSubject.send(decoded)
    }

    private func persist(contacts: [WalletContact]) {
        // Always persist to UserDefaults as fallback
        guard let data = try? JSONEncoder().encode(contacts) else { return }
        userDefaults.set(data: data, forKey: Self.storageKey)

        // Persist to GRDB
        #if canImport(GRDB)
        do {
            let records = contacts.map { ContactRecord.from(contact: $0) }
            try databaseManager.write { db in
                try ContactRecord.deleteAll(db)
                for record in records {
                    try record.insert(db)
                }
            }
        } catch {
            print("[ContactBookManager] failed to persist contacts to db: \(error)")
        }
        #endif

        contactsSubject.send(contacts)
    }
}
