import Foundation
import UIKit

enum AppConfig {
    static let label = "com.unite.wallet.core"
    static let dbFileName = "unite.sqlite"
    static let keychainService = "com.unite.wallet.keychain"
    static let appName = "Unite"
    static let appWebPageLink = "https://unitewallet.app"
    static let reportEmail = "support@unitewallet.app"
    static let companyName = "Unite Wallet"

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var appId: String? {
        UIDevice.current.identifierForVendor?.uuidString
    }
}
