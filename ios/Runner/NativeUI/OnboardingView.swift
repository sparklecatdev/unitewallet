import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var showingImport = false
    @State private var showingRestore = false
    @State private var errorMessage: String?
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white)
                    .frame(width: 86, height: 86)
                Text("U")
                    .roundedFont(42, weight: .black)
                    .foregroundStyle(.black)
            }

            UniteSectionHeader(
                eyebrow: "Private beta",
                title: "Unite",
                detail: "Create or import a wallet, keep recovery material on this device, and follow the market without extra noise."
            )
            .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    UniteButton(
                        title: isCreating ? "Creating wallet..." : "Create a new wallet",
                        systemImage: isCreating ? nil : "plus",
                        isLoading: isCreating,
                        action: {
                            isCreating = true
                            errorMessage = nil
                            Task {
                                errorMessage = store.createWallet()
                                isCreating = false
                            }
                        }
                    )
                    Text("Start fresh with a new recovery phrase. You will review and confirm it before entering the wallet.")
                        .roundedFont(13, weight: .medium)
                        .foregroundStyle(UniteTheme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 10) {
                    UniteButton(
                        title: "Import an existing wallet",
                        systemImage: "square.and.arrow.down",
                        tone: .secondary,
                        action: { showingImport = true }
                    )
                    Text("Use a 12 to 24 word recovery phrase or a supported private key from a wallet you already control.")
                        .roundedFont(13, weight: .medium)
                        .foregroundStyle(UniteTheme.secondaryText)
                }

                if store.hasSyncBackup {
                    VStack(alignment: .leading, spacing: 10) {
                        UniteButton(
                            title: "Restore encrypted iCloud backup",
                            systemImage: "icloud.and.arrow.down",
                            tone: .secondary,
                            action: { showingRestore = true }
                        )
                        Text("Use the same 6-digit Unite code from your other device to restore the encrypted wallet package.")
                            .roundedFont(13, weight: .medium)
                            .foregroundStyle(UniteTheme.secondaryText)
                    }
                }
            }
            .padding(.top, 8)

            if let errorMessage {
                UniteBanner(
                    title: "Couldn’t finish that step",
                    detail: errorMessage,
                    tone: .caution,
                    icon: "exclamationmark.triangle"
                )
            }

            UniteBanner(
                title: "Private by default",
                detail: "Recovery material stays on this device and sensitive views can sit behind device authentication.",
                tone: .neutral,
                icon: "lock.shield"
            )

            Spacer()
        }
        .padding(24)
        .background(UniteTheme.ink)
        .sheet(isPresented: $showingImport) {
            ImportWalletView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingRestore) {
            RestoreWalletView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct ImportWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WalletStore
    @State private var importPrivateKey = false
    @State private var privateKeyNetwork = WalletNetwork.solana
    @State private var secret = ""
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var successMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            UniteSectionHeader(
                eyebrow: "Bring your wallet in",
                title: "Import wallet",
                detail: "Paste a recovery phrase or private key from a wallet you already control."
            )

            Picker("Import type", selection: $importPrivateKey) {
                Text("Recovery phrase").tag(false)
                Text("Private key").tag(true)
            }
            .pickerStyle(.segmented)

            if importPrivateKey {
                Picker("Private key network", selection: $privateKeyNetwork) {
                    Text("Ethereum").tag(WalletNetwork.ethereum)
                    Text("Solana").tag(WalletNetwork.solana)
                }
                .pickerStyle(.segmented)
            }

            Text(importPrivateKey ? "Choose the network first, then paste the matching private key exactly as exported." : "Use a 12, 15, 18, 21, or 24 word recovery phrase with the original order intact. Phrase imports derive Bitcoin, Ethereum, and Solana accounts together.")
                .roundedFont(13, weight: .medium)
                .foregroundStyle(UniteTheme.secondaryText)

            TextEditor(text: $secret)
                .roundedFont(15, weight: .semibold)
                .frame(minHeight: 140)
                .padding(12)
                .scrollContentBackground(.hidden)
                .uniteField()

            if let errorMessage {
                UniteBanner(
                    title: "Import needs another look",
                    detail: errorMessage,
                    tone: .caution,
                    icon: "exclamationmark.triangle"
                )
            }

            if let successMessage {
                UniteBanner(
                    title: "Wallet imported",
                    detail: successMessage,
                    tone: .success,
                    icon: "checkmark.circle"
                )
            }

            UniteButton(
                title: isImporting ? "Importing wallet..." : "Import wallet",
                systemImage: isImporting ? nil : "checkmark",
                isLoading: isImporting,
                isEnabled: !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: {
                    isImporting = true
                    errorMessage = nil
                    successMessage = nil
                    Task {
                        if let message = await store.importWallet(secret: secret, asPrivateKey: importPrivateKey, privateKeyChainID: privateKeyNetwork.rawValue) {
                            errorMessage = message
                            isImporting = false
                        } else {
                            successMessage = "Your wallet is ready on this device."
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            isImporting = false
                            dismiss()
                        }
                    }
                }
            )

            Spacer()
        }
        .padding(22)
        .background(UniteTheme.ink)
    }
}

struct BackupView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()

            UniteSectionHeader(
                eyebrow: "Recovery step",
                title: "Back up your wallet",
                detail: "Take a minute to store your recovery phrase before entering the wallet."
            )

            UniteBanner(
                title: "This phrase is the only backup",
                detail: "If you lose this phrase, you cannot recover the wallet on a new device. If someone else sees it, they can take the funds.",
                tone: .caution,
                icon: "exclamationmark.shield"
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Recovery phrase")
                    .roundedFont(13, weight: .black)
                    .foregroundStyle(UniteTheme.secondaryText)
                Text(store.mnemonic)
                    .roundedFont(15, weight: .bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(UniteTheme.line, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Before you continue")
                    .roundedFont(16, weight: .black)
                Text("Write the phrase down offline, keep the order exactly as shown, and avoid screenshots, cloud notes, or shared devices.")
                    .roundedFont(14, weight: .medium)
                    .foregroundStyle(UniteTheme.soft)
            }
            .padding(18)
            .background(UniteTheme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Toggle("I saved this recovery phrase somewhere safe.", isOn: $saved)
                .roundedFont(15, weight: .semibold)
                .tint(.white)

            UniteButton(
                title: "Continue to wallet",
                systemImage: "checkmark",
                isEnabled: saved,
                action: { store.confirmBackup() }
            )

            Spacer()
        }
        .padding(24)
        .background(UniteTheme.ink)
    }
}

private struct RestoreWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WalletStore
    @State private var passcode = ""
    @State private var restoreMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            UniteSectionHeader(
                eyebrow: "Encrypted restore",
                title: "Open your iCloud wallet backup",
                detail: "Enter the same 6-digit Unite code you used on the device that created the encrypted backup."
            )

            UniteTextField(title: "6-digit code", text: $passcode, placeholder: "123456", keyboard: .numberPad)

            if let restoreMessage {
                UniteBanner(
                    title: restoreMessage == "Restored" ? "Wallet restored" : "Restore failed",
                    detail: restoreMessage == "Restored" ? "Your encrypted wallet package is now available on this device." : restoreMessage,
                    tone: restoreMessage == "Restored" ? .success : .caution,
                    icon: restoreMessage == "Restored" ? "checkmark.circle" : "exclamationmark.triangle"
                )
            }

            UniteButton(title: "Restore wallet", systemImage: "icloud.and.arrow.down") {
                if let error = store.restoreWalletFromSync(passcode: passcode) {
                    restoreMessage = error
                } else {
                    restoreMessage = "Restored"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        dismiss()
                    }
                }
            }

            Spacer()
        }
        .padding(22)
        .background(UniteTheme.ink)
    }
}
