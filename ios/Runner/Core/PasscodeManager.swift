import Foundation
import CryptoKit
import LocalAuthentication

final class PasscodeManager {
    enum Keys {
        static let passcodeHash = "unite.passcode.hash"
        static let passcodeSalt = "unite.passcode.salt"
        static let biometryEnabled = "unite.biometry.enabled"
        static let duressPasscodeHash = "unite.duress.hash"
    }

    private let keychainStorage: KeychainStorage
    private let userDefaults: UserDefaultsStorage
    private let context = LAContext()

    @Published private(set) var isPasscodeSet: Bool = false
    @Published private(set) var isDuressPasscodeSet: Bool = false
    @Published private(set) var biometryEnabled: Bool = false
    @Published private(set) var currentPasscodeLevel: Int = 0

    private var salt: Data?
    private var passcodeHash: Data?
    private var duressPasscodeHash: Data?

    init(keychainStorage: KeychainStorage, userDefaults: UserDefaultsStorage) {
        self.keychainStorage = keychainStorage
        self.userDefaults = userDefaults
        loadState()
    }

    var availableBiometryType: LABiometryType {
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return canEvaluate ? context.biometryType : .none
    }

    func setPasscode(_ passcode: String) -> String? {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else {
            return "Passcode must be at least 4 digits."
        }

        let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let hash = hashPasscode(trimmed, salt: salt)

        do {
            try keychainStorage.store(data: hash, key: Keys.passcodeHash)
            try keychainStorage.store(data: salt, key: Keys.passcodeSalt)
        } catch {
            return "Failed to securely store passcode."
        }

        self.salt = salt
        passcodeHash = hash
        isPasscodeSet = true
        return nil
    }

    func verifyPasscode(_ passcode: String) -> Bool {
        if isDuressPasscodeSet,
           let duressHash = duressPasscodeHash,
           let salt = salt {
            let hash = hashPasscode(passcode, salt: salt)
            if hash == duressHash {
                currentPasscodeLevel += 1
                return true
            }
        }

        guard let storedHash = passcodeHash,
              let salt = salt else {
            return false
        }
        return hashPasscode(passcode, salt: salt) == storedHash
    }

    func setDuressPasscode(_ passcode: String) -> String? {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else {
            return "Duress passcode must be at least 4 digits."
        }
        guard let salt = salt else {
            return "Set a main passcode first."
        }
        let hash = hashPasscode(trimmed, salt: salt)
        if let passcodeHash, hash == passcodeHash {
            return "Duress passcode must be different from main passcode."
        }

        do {
            try keychainStorage.store(data: hash, key: Keys.duressPasscodeHash)
        } catch {
            return "Failed to store duress passcode."
        }

        duressPasscodeHash = hash
        isDuressPasscodeSet = true
        return nil
    }

    func disableDuressPasscode() {
        try? keychainStorage.remove(key: Keys.duressPasscodeHash)
        duressPasscodeHash = nil
        isDuressPasscodeSet = false
        currentPasscodeLevel = 0
    }

    func authenticateWithBiometrics(reason: String = "Unlock your wallet") async -> Bool {
        guard biometryEnabled else { return false }
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }

    func setBiometryEnabled(_ enabled: Bool) {
        biometryEnabled = enabled
        userDefaults.set(bool: enabled, forKey: Keys.biometryEnabled)
    }

    private func loadState() {
        do {
            passcodeHash = try keychainStorage.dataValue(for: Keys.passcodeHash)
            salt = try keychainStorage.dataValue(for: Keys.passcodeSalt)
            duressPasscodeHash = try keychainStorage.dataValue(for: Keys.duressPasscodeHash)
        } catch {
            passcodeHash = nil
            salt = nil
            duressPasscodeHash = nil
        }

        isPasscodeSet = passcodeHash != nil
        isDuressPasscodeSet = duressPasscodeHash != nil
        biometryEnabled = userDefaults.bool(forKey: Keys.biometryEnabled)
    }

    private func hashPasscode(_ passcode: String, salt: Data) -> Data {
        var hasher = SHA256()
        hasher.update(data: Data(passcode.utf8))
        hasher.update(data: salt)
        return Data(hasher.finalize())
    }
}
