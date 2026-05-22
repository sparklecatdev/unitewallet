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

    var network: WalletNetwork? {
        WalletNetwork(rawValue: id)
    }
}

struct WalletMaterial {
    let mnemonic: String
    let privateKey: String
    let primaryAddress: String
    let chains: [WalletChain]
    let engine: String
}

enum WalletNetwork: String, CaseIterable, Codable, Identifiable {
    case bitcoin
    case ethereum
    case solana

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bitcoin: "Bitcoin"
        case .ethereum: "Ethereum"
        case .solana: "Solana"
        }
    }

    var symbol: String {
        switch self {
        case .bitcoin: "BTC"
        case .ethereum: "ETH"
        case .solana: "SOL"
        }
    }

    var derivationStandard: String {
        switch self {
        case .bitcoin: "BIP44 / secp256k1"
        case .ethereum: "BIP44 / secp256k1"
        case .solana: "SLIP-0010 / Ed25519"
        }
    }

    var coinGeckoID: String {
        rawValue
    }

    var fractionDigits: Int {
        switch self {
        case .bitcoin: 8
        case .ethereum: 6
        case .solana: 6
        }
    }
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

    static let supportedChainID = WalletNetwork.solana.rawValue

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

    static func importPrivateKey(_ privateKey: String, chainID: String = supportedChainID) throws -> WalletMaterial {
        #if canImport(WalletCore)
        guard let keyData = decodedPrivateKey(privateKey), let key = PrivateKey(data: keyData) else {
            throw ImportError.invalidPrivateKey
        }

        guard let network = WalletNetwork(rawValue: chainID) else {
            throw ImportError.invalidPrivateKey
        }

        let address: String
        switch network {
        case .bitcoin:
            address = CoinType.bitcoin.deriveAddress(privateKey: key)
        case .ethereum:
            address = CoinType.ethereum.deriveAddress(privateKey: key)
        case .solana:
            address = CoinType.solana.deriveAddress(privateKey: key)
        }
        guard !address.isEmpty else {
            throw ImportError.noAddress
        }

        return WalletMaterial(
            mnemonic: "",
            privateKey: privateKey,
            primaryAddress: address,
            chains: [chain(network: network, address: address, derivationPath: "Imported private key")],
            engine: "Unite Core"
        )
        #else
        throw ImportError.engineUnavailable
        #endif
    }

    static func validateAddress(_ address: String, chainID: String = supportedChainID) -> Bool {
        #if canImport(WalletCore)
        guard let network = WalletNetwork(rawValue: chainID) else { return false }
        switch network {
        case .bitcoin:
            return CoinType.bitcoin.validate(address: address)
        case .ethereum:
            return CoinType.ethereum.validate(address: address)
        case .solana:
            return CoinType.solana.validate(address: address)
        }
        #else
        return false
        #endif
    }

    #if canImport(WalletCore)
    private static func material(from wallet: HDWallet) throws -> WalletMaterial {
        let chains = WalletNetwork.allCases.compactMap { network -> WalletChain? in
            let coinType: CoinType
            switch network {
            case .bitcoin: coinType = .bitcoin
            case .ethereum: coinType = .ethereum
            case .solana: coinType = .solana
            }

            let address = wallet.getAddressForCoin(coin: coinType)
            guard !address.isEmpty else { return nil }
            return chain(network: network, address: address, derivationPath: coinType.derivationPath())
        }

        guard let primaryChain = chains.first(where: { $0.id == WalletNetwork.solana.rawValue }) ?? chains.first else {
            throw ImportError.noAddress
        }

        let walletPrivateKey = wallet.getKeyForCoin(coin: .ethereum).data.hexString
        return WalletMaterial(
            mnemonic: wallet.mnemonic,
            privateKey: walletPrivateKey,
            primaryAddress: primaryChain.address,
            chains: chains,
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

    private static func chain(network: WalletNetwork, address: String, derivationPath: String) -> WalletChain {
        WalletChain(
            id: network.rawValue,
            name: network.displayName,
            symbol: network.symbol,
            address: address,
            derivationPath: derivationPath,
            standards: network.derivationStandard
        )
    }
}
