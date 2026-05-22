import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var showingImport = false
    @State private var errorMessage: String?

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

            VStack(spacing: 8) {
                Text("Unite")
                    .roundedFont(42, weight: .black)
                Text("One place to manage crypto.")
                    .roundedFont(17, weight: .medium)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(UniteTheme.soft)
            }

            VStack(spacing: 12) {
                Button {
                    errorMessage = store.createWallet()
                } label: {
                    Label("Create wallet", systemImage: "plus")
                        .roundedFont(16, weight: .bold)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Button {
                    showingImport = true
                } label: {
                    Label("Import wallet", systemImage: "square.and.arrow.down")
                        .roundedFont(16, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UniteTheme.line))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            if let errorMessage {
                Text(errorMessage)
                    .roundedFont(14, weight: .bold)
                    .foregroundStyle(UniteTheme.yellow)
                    .multilineTextAlignment(.center)
            }

            Text("Keys stay on this device.")
                .roundedFont(12, weight: .medium)
                .foregroundStyle(UniteTheme.muted)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(24)
        .background(UniteTheme.ink)
        .sheet(isPresented: $showingImport) {
            ImportWalletView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct ImportWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WalletStore
    @State private var importPrivateKey = false
    @State private var secret = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Import wallet")
                .roundedFont(30, weight: .black)

            Picker("Import type", selection: $importPrivateKey) {
                Text("Seed").tag(false)
                Text("Private key").tag(true)
            }
            .pickerStyle(.segmented)

            TextEditor(text: $secret)
                .roundedFont(15, weight: .semibold)
                .frame(minHeight: 140)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(UniteTheme.line))

            if let errorMessage {
                Text(errorMessage)
                    .roundedFont(14, weight: .bold)
                    .foregroundStyle(UniteTheme.yellow)
            }

            Button {
                if let message = store.importWallet(secret: secret, asPrivateKey: importPrivateKey) {
                    errorMessage = message
                } else {
                    dismiss()
                }
            } label: {
                Label("Import", systemImage: "checkmark")
                    .roundedFont(16, weight: .bold)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

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

            Text("Back up your wallet")
                .roundedFont(30, weight: .black)

            Text("This recovery phrase is the only way to recover this wallet on a new device. Store it offline and never share it.")
                .roundedFont(15, weight: .semibold)
                .foregroundStyle(UniteTheme.yellow)

            Text(store.mnemonic)
                .roundedFont(15, weight: .bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Toggle("I saved this recovery phrase somewhere safe.", isOn: $saved)
                .roundedFont(15, weight: .semibold)
                .tint(.white)

            Button {
                store.confirmBackup()
            } label: {
                Label("Continue to wallet", systemImage: "checkmark")
                    .roundedFont(16, weight: .bold)
                    .foregroundStyle(saved ? .black : UniteTheme.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(saved ? .white : UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(!saved)
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(24)
        .background(UniteTheme.ink)
    }
}
