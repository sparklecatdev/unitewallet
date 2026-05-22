import Foundation

#if canImport(WalletCore)
import WalletCore
#endif

struct WalletChain: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let address: String
    let derivationPath: String
    let standards: String

    var shortAddress: String {
        guard address.count > 14 else { return address }
        return "\(address.prefix(6))...\(address.suffix(6))"
    }

    var family: String { "Ed25519" }
}

struct WalletMaterial {
    let mnemonic: String
    let privateKey: String
    let primaryAddress: String
    let chains: [WalletChain]
    let engine: String
}

enum WalletCoreBridge {
    enum ImportError: LocalizedError {
        case engineUnavailable
        case invalidMnemonic
        case invalidPrivateKey
        case noAddress

        var errorDescription: String? {
            switch self {
            case .engineUnavailable:
                return "The wallet engine is unavailable. This beta cannot create or open wallets on this build."
            case .invalidMnemonic:
                return "That recovery phrase could not be opened. Check the words and spacing, then try again."
            case .invalidPrivateKey:
                return "That private key could not be opened. Use a Solana base58 key or a 64-character hex key."
            case .noAddress:
                return "The wallet opened, but no supported Solana address could be created."
            }
        }
    }

    static let supportedChainID = "solana"

    static func createWallet() throws -> WalletMaterial {
        #if canImport(WalletCore)
        guard let wallet = HDWallet(strength: 128, passphrase: "") else {
            throw ImportError.invalidMnemonic
        }
        return try material(from: wallet)
        #else
        throw ImportError.engineUnavailable
        #endif
    }

    static func importMnemonic(_ mnemonic: String) throws -> WalletMaterial {
        #if canImport(WalletCore)
        guard let wallet = HDWallet(mnemonic: mnemonic, passphrase: "") else {
            throw ImportError.invalidMnemonic
        }
        return try material(from: wallet)
        #else
        throw ImportError.engineUnavailable
        #endif
    }

    static func importPrivateKey(_ privateKey: String) throws -> WalletMaterial {
        #if canImport(WalletCore)
        guard let keyData = decodedPrivateKey(privateKey), let key = PrivateKey(data: keyData) else {
            throw ImportError.invalidPrivateKey
        }

        let address = CoinType.solana.deriveAddress(privateKey: key)
        guard !address.isEmpty else {
            throw ImportError.noAddress
        }

        return WalletMaterial(
            mnemonic: "",
            privateKey: privateKey,
            primaryAddress: address,
            chains: [solanaChain(address: address, derivationPath: "Imported private key")],
            engine: "Unite Core"
        )
        #else
        throw ImportError.engineUnavailable
        #endif
    }

    static func validateAddress(_ address: String, chainID: String = supportedChainID) -> Bool {
        guard chainID == supportedChainID else { return false }
        #if canImport(WalletCore)
        return CoinType.solana.validate(address: address)
        #else
        return false
        #endif
    }

    #if canImport(WalletCore)
    private static func material(from wallet: HDWallet) throws -> WalletMaterial {
        let address = wallet.getAddressForCoin(coin: .solana)
        guard !address.isEmpty else {
            throw ImportError.noAddress
        }

        let solanaKey = wallet.getKeyForCoin(coin: .solana).data.hexString
        return WalletMaterial(
            mnemonic: wallet.mnemonic,
            privateKey: solanaKey,
            primaryAddress: address,
            chains: [solanaChain(address: address, derivationPath: CoinType.solana.derivationPath())],
            engine: "Unite Core"
        )
    }

    private static func decodedPrivateKey(_ privateKey: String) -> Data? {
        let cleaned = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if let hex = Data(hexString: cleaned) {
            if hex.count == 32 { return hex }
            if hex.count > 32 { return Data(hex.prefix(32)) }
        }

        if let base58 = Base58.decodeNoCheck(string: cleaned) ?? Base58.decode(string: cleaned) {
            if base58.count == 32 { return base58 }
            if base58.count > 32 { return Data(base58.prefix(32)) }
        }

        return nil
    }
    #endif

    private static func solanaChain(address: String, derivationPath: String) -> WalletChain {
        WalletChain(
            id: supportedChainID,
            name: "Solana",
            symbol: "SOL",
            address: address,
            derivationPath: derivationPath,
            standards: "SLIP-0010 / Ed25519"
        )
    }
}
