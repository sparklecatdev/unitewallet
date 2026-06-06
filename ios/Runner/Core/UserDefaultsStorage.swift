import Foundation

final class UserDefaultsStorage {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func bool(forKey key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    func set(bool: Bool, forKey key: String) {
        defaults.set(bool, forKey: key)
    }

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func set(string: String?, forKey key: String) {
        defaults.set(string, forKey: key)
    }

    func integer(forKey key: String) -> Int {
        defaults.integer(forKey: key)
    }

    func set(integer: Int, forKey key: String) {
        defaults.set(integer, forKey: key)
    }

    func double(forKey key: String) -> Double {
        defaults.double(forKey: key)
    }

    func set(double: Double, forKey key: String) {
        defaults.set(double, forKey: key)
    }

    func date(forKey key: String) -> Date? {
        defaults.object(forKey: key) as? Date
    }

    func set(date: Date?, forKey key: String) {
        defaults.set(date, forKey: key)
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }

    func stringArray(forKey key: String) -> [String]? {
        defaults.stringArray(forKey: key)
    }

    func set(stringArray: [String]?, forKey key: String) {
        defaults.set(stringArray, forKey: key)
    }

    func codable<T: Codable>(forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func set<T: Codable>(codable: T?, forKey key: String) {
        guard let codable else {
            defaults.removeObject(forKey: key)
            return
        }
        let data = try? JSONEncoder().encode(codable)
        defaults.set(data, forKey: key)
    }

    func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }

    func synchronize() {
        defaults.synchronize()
    }
}
