import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var showingSecret = false
    @State private var showingChains = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Profile")
                        .roundedFont(32, weight: .black)

                    ProfileRow(label: "Address", value: store.shortAddress)
                    ProfileRow(label: "Key engine", value: store.visibleEngineName)
                    ProfileRow(label: "Supported chain", value: store.chains.first?.name ?? "Solana")
                    ProfileRow(label: "Imported by", value: store.importType)

                    Button {
                        showingChains = true
                    } label: {
                        Label("Supported chain details", systemImage: "square.grid.2x2")
                            .roundedFont(15, weight: .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .uniteCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Security")
                        .roundedFont(24, weight: .black)

                    Toggle("Biometric lock", isOn: Binding(
                        get: { store.biometricLockEnabled },
                        set: { store.setBiometricLockEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .tint(.white)

                    Toggle("Diagnostics logs", isOn: Binding(
                        get: { store.diagnosticsEnabled },
                        set: { store.setDiagnosticsEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .tint(.white)

                    ForEach(store.serviceStatuses) { status in
                        ServiceStatusRow(status: status)
                    }

                    Button {
                        showingSecret = true
                    } label: {
                        Label("Recovery material", systemImage: "lock")
                            .roundedFont(15, weight: .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .uniteCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Support")
                        .roundedFont(24, weight: .black)

                    Link(destination: URL(string: "mailto:\(WalletStore.SupportResource.email)")!) {
                        SupportRow(title: "Email support", detail: WalletStore.SupportResource.email, icon: "envelope")
                    }

                    Link(destination: WalletStore.SupportResource.feedbackURL) {
                        SupportRow(title: "Beta feedback", detail: WalletStore.SupportResource.feedbackURL.absoluteString, icon: "bubble.left.and.bubble.right")
                    }

                    Link(destination: WalletStore.SupportResource.privacyURL) {
                        SupportRow(title: "Privacy policy", detail: WalletStore.SupportResource.privacyURL.absoluteString, icon: "hand.raised")
                    }

                    Link(destination: WalletStore.SupportResource.termsURL) {
                        SupportRow(title: "Terms and risk disclosure", detail: WalletStore.SupportResource.termsURL.absoluteString, icon: "doc.text")
                    }
                }
                .uniteCard()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Beta limitations")
                        .roundedFont(24, weight: .black)
                    Text("This build does not support send, swap, buy, alerts, or custom RPC routing yet. The goal is secure create/import, backup, receive, and read-only markets.")
                        .roundedFont(14, weight: .medium)
                        .foregroundStyle(UniteTheme.muted)

                    Button(role: .destructive) {
                        store.removeWallet()
                    } label: {
                        Label("Remove wallet from device", systemImage: "trash")
                            .roundedFont(15, weight: .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .uniteCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 104)
        }
        .background(UniteTheme.ink)
        .sheet(isPresented: $showingSecret) {
            SecretRevealView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingChains) {
            ChainDirectoryView(chains: store.chains)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct ProfileRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .roundedFont(14, weight: .black)
                .foregroundStyle(UniteTheme.muted)
            Spacer()
            Text(value)
                .roundedFont(15, weight: .black)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct ChainDirectoryView: View {
    let chains: [WalletChain]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Supported chains")
                    .roundedFont(30, weight: .black)
                    .padding(.bottom, 4)

                ForEach(chains) { chain in
                    HStack(spacing: 12) {
                        Text(String(chain.symbol.prefix(1)))
                            .roundedFont(17, weight: .black)
                            .frame(width: 42, height: 42)
                            .background(UniteTheme.raised, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(chain.name)
                                .roundedFont(16, weight: .black)
                            Text(chain.standards)
                                .roundedFont(12, weight: .bold)
                                .foregroundStyle(UniteTheme.muted)
                        }
                        Spacer()
                        Text(chain.shortAddress)
                            .roundedFont(12, weight: .bold)
                            .foregroundStyle(UniteTheme.soft)
                    }
                    .padding(14)
                    .background(UniteTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(22)
        }
        .background(UniteTheme.ink)
    }
}

private struct ServiceStatusRow: View {
    let status: WalletServiceStatus

    var body: some View {
        HStack(spacing: 12) {
            Text(status.state)
                .roundedFont(12, weight: .black)
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white, in: Capsule())
            VStack(alignment: .leading, spacing: 3) {
                Text(status.name)
                    .roundedFont(15, weight: .black)
                Text(status.detail)
                    .roundedFont(12, weight: .bold)
                    .foregroundStyle(UniteTheme.muted)
            }
            Spacer()
        }
        .padding(14)
        .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SupportRow: View {
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .black))
                .frame(width: 38, height: 38)
                .background(UniteTheme.raised, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .roundedFont(15, weight: .black)
                Text(detail)
                    .roundedFont(12, weight: .bold)
                    .foregroundStyle(UniteTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .foregroundStyle(UniteTheme.soft)
        }
        .padding(14)
        .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SecretRevealView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var isUnlocking = false
    @State private var revealed = false

    private var secretLabel: String {
        store.mnemonic.isEmpty ? "Private key" : "Recovery phrase"
    }

    private var secretValue: String {
        store.mnemonic.isEmpty ? store.privateKey : store.mnemonic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Sensitive keys")
                .roundedFont(30, weight: .black)

            Text("Scammers may ask for these words or keys to drain your wallet. Unite support will never ask for them.")
                .roundedFont(15, weight: .bold)
                .foregroundStyle(UniteTheme.yellow)

            if let message = store.unlockErrorMessage, !revealed {
                Text(message)
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(UniteTheme.yellow)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(secretLabel)
                    .roundedFont(13, weight: .black)
                    .foregroundStyle(UniteTheme.muted)
                Group {
                    if revealed {
                        Text(secretValue)
                            .textSelection(.enabled)
                    } else {
                        Text("Authenticate on this device to reveal the stored recovery material.")
                    }
                }
                .roundedFont(15, weight: .bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                isUnlocking = true
                Task {
                    revealed = await store.unlockApp()
                    isUnlocking = false
                }
            } label: {
                Text(isUnlocking ? "Authenticating..." : (revealed ? "Authenticated" : "Reveal on this device"))
                    .roundedFont(16, weight: .black)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isUnlocking || revealed)

            Spacer()
        }
        .padding(22)
        .background(UniteTheme.ink)
    }
}
