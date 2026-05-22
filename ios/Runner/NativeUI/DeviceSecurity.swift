import Foundation
import LocalAuthentication

protocol DeviceAuthenticating {
    func authenticate(reason: String) async throws -> Bool
}

final class DeviceSecurity: DeviceAuthenticating {
    static let shared = DeviceSecurity()

    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? LAError(.biometryNotAvailable)
        }

        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evaluationError in
                if let evaluationError {
                    continuation.resume(throwing: evaluationError)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

final class StubDeviceAuthenticator: DeviceAuthenticating {
    private let result: Bool

    init(result: Bool) {
        self.result = result
    }

    func authenticate(reason: String) async throws -> Bool {
        result
    }
}
