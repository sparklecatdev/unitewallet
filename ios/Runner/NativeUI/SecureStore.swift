// ... existing code ...
protocol SecureStoring {
    func string(for key: String) throws -> String?
    func set(_ value: String, for key: String) throws
    func removeValue(for key: String) throws
    func data(for key: String) throws -> Data?
    func set(data: Data, for key: String) throws
}
// ... existing code ...import Foundation
import Security

protocol SecureStoring {
    func string(for key: String) throws -> String?
    func set(_ value: String, for key: String) throws
    func removeValue(for key: String) throws
}

enum SecureStoreError: LocalizedError {
    case unexpectedData
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "Secure storage returned unreadable data."
        case .unhandled(let status):
            return "Secure storage failed with status \(status)."
        }
    }
}

final class KeychainSecureStore: SecureStoring {
    static let shared = KeychainSecureStore()

    private let service = "com.unite.wallet.secure-store"

    func string(for key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecureStoreError.unhandled(status)
        }
        guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
            throw SecureStoreError.unexpectedData
        }
        return string
    }

    func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw SecureStoreError.unhandled(updateStatus)
        }

        var createQuery = query
        createQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(createQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureStoreError.unhandled(addStatus)
        }
    }

    func removeValue(for key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.unhandled(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

final class InMemorySecureStore: SecureStoring {
    private var values: [String: String] = [:]

    func string(for key: String) throws -> String? {
        values[key]
    }

    func set(_ value: String, for key: String) throws {
        values[key] = value
    }

    func removeValue(for key: String) throws {
        values.removeValue(forKey: key)
    }
}
