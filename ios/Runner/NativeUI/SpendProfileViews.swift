import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var showingSecret = false
    @State private var showingChains = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    UniteSectionHeader(
                        eyebrow: "Profile",
                        title: "Wallet settings",
                        detail: "Review your account, device security, and beta support details."
                    )

                    ProfileRow(label: "Address", value: store.shortAddress)
                    ProfileRow(label: "Key engine", value: store.visibleEngineName)
                    ProfileRow(label: "Primary network", value: store.chains.first?.name ?? "Solana")
                    ProfileRow(label: "Setup method", value: store.importType)

                    UniteButton(title: "Supported network details", systemImage: "square.grid.2x2", tone: .secondary) {
                        showingChains = true
                    }
                }
                .uniteCard()

                VStack(alignment: .leading, spacing: 16) {
                    UniteSectionHeader(
                        eyebrow: "Security",
                        title: "Device protection",
                        detail: "Choose how this wallet unlocks and what support can never see."
                    )

                    Toggle("Face ID unlock", isOn: Binding(
                        get: { store.faceIDEnabled },
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

                    UniteButton(title: "Reveal recovery material", systemImage: "lock", tone: .secondary) {
                        store.lockApp(reason: .securityAction)
                        showingSecret = true
                    }
                }
                .uniteCard()

                VStack(alignment: .leading, spacing: 16) {
                    UniteSectionHeader(
                        eyebrow: "Support",
                        title: "Help and policies",
                        detail: "Use these links for feedback, support, and beta policy details."
                    )

                    Link(destination: URL(string: "mailto:\(WalletStore.SupportResource.email)")!) {
                        SupportRow(title: "Email support", detail: "Direct support inbox", icon: "envelope")
                    }

                    Link(destination: WalletStore.SupportResource.feedbackURL) {
                        SupportRow(title: "Beta feedback", detail: "Share a bug or product note", icon: "bubble.left.and.bubble.right")
                    }

                    Link(destination: WalletStore.SupportResource.privacyURL) {
                        SupportRow(title: "Privacy policy", detail: "How wallet data is handled", icon: "hand.raised")
                    }

                    Link(destination: WalletStore.SupportResource.termsURL) {
                        SupportRow(title: "Terms and risk disclosure", detail: "Beta rules and wallet risk basics", icon: "doc.text")
                    }
                }
                .uniteCard()

                VStack(alignment: .leading, spacing: 14) {
                    UniteSectionHeader(
                        eyebrow: "Beta expectations",
                        title: "What this build is for",
                        detail: "This release is focused on setup, backup, secure access, encrypted sync, receive, and read-only markets. Network send services and WalletConnect session handling still need runtime work."
                    )

                    UniteButton(title: "Remove wallet from device", systemImage: "trash", tone: .caution) {
                        store.removeWallet()
                    }
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
                UniteSectionHeader(
                    eyebrow: "Networks",
                    title: "Supported beta chains",
                    detail: "These are the networks currently exposed in this wallet build."
                )

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
            UniteSectionHeader(
                eyebrow: "Recovery access",
                title: "Reveal sensitive material",
                detail: "Use Face ID on this device after your Unite app code has unlocked the wallet."
            )

            UniteBanner(
                title: "Never share this with anyone",
                detail: "Scammers use recovery words and private keys to empty wallets. Support will never ask for them.",
                tone: .caution,
                icon: "hand.raised.fill"
            )

            if let message = store.unlockErrorMessage, !revealed {
                UniteBanner(
                    title: "Authentication didn’t finish",
                    detail: message,
                    tone: .caution,
                    icon: "exclamationmark.triangle"
                )
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
                        Text("Locked until you complete Face ID on this device.")
                    }
                }
                .roundedFont(15, weight: .bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if revealed {
                UniteBanner(
                    title: "Visible only for this session",
                    detail: "Move carefully. Do not screenshot, share, or paste this into messages or websites.",
                    tone: .success,
                    icon: "eye.slash"
                )
            }

            UniteButton(
                title: isUnlocking ? "Authenticating..." : (revealed ? "Revealed on this device" : "Reveal on this device"),
                systemImage: isUnlocking ? "hourglass" : (revealed ? "checkmark.shield" : "faceid"),
                isLoading: isUnlocking,
                isEnabled: !revealed,
                tone: revealed ? .secondary : .primary
            ) {
                isUnlocking = true
                Task {
                    store.lockApp(reason: .securityAction)
                    revealed = await store.unlockWithFaceID()
                    isUnlocking = false
                }
            }

            Spacer()
        }
        .padding(22)
        .background(UniteTheme.ink)
    }
}
