import Foundation

/// Higher-level wrapper around `SecureStoring` that delegates to any
/// `SecureStoring` implementation and adds convenience helpers for
/// base64-encoded Data.
final class KeychainStorage {
    private let secureStore: SecureStoring

    init(secureStore: SecureStoring) {
        self.secureStore = secureStore
    }

    // MARK: - String

    func store(_ value: String, key: String) throws {
        try secureStore.set(value, for: key)
    }

    func value(for key: String) throws -> String? {
        try secureStore.string(for: key)
    }

    // MARK: - Data

    func store(data: Data, key: String) throws {
        try secureStore.set(data.base64EncodedString(), for: key)
    }

    func dataValue(for key: String) throws -> Data? {
        guard let value = try secureStore.string(for: key) else {
            return nil
        }
        return Data(base64Encoded: value)
    }

    // MARK: - Removal

    func remove(key: String) throws {
        try secureStore.removeValue(for: key)
    }

    func remove(keys: [String]) {
        for key in keys {
            try? secureStore.removeValue(for: key)
        }
    }
}
