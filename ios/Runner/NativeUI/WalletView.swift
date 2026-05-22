import SwiftUI
import UIKit

struct WalletView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var selectedList = WalletList.crypto
    @State private var showingReceive = false
    @State private var showingSearch = false
    @State private var showingSecurity = false
    @State private var showingGuide = false
    @State private var showingSecretReveal = false

    private var solAsset: MarketAsset {
        store.marketAssets.first(where: { $0.id == "solana" }) ?? MarketAsset.defaults[2]
    }

    private var portfolioValue: Double {
        store.balanceSOL * (solAsset.price ?? 0)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                WalletTopBar(
                    onSecurity: { showingSecurity = true },
                    onSearch: { showingSearch = true },
                    onReceive: { showingReceive = true },
                    onGuide: { showingGuide = true }
                )
                .padding(.top, 12)

                WalletHero(
                    portfolioValue: portfolioValue,
                    change: solAsset.change24h ?? 0,
                    address: store.shortAddress,
                    chainCount: store.chains.count
                )

                WalletPrimaryActions(
                    onReceive: { showingReceive = true },
                    onRecovery: { showingSecretReveal = true },
                    onSecurity: { showingSecurity = true }
                )

                WalletAssetSection(
                    selectedList: $selectedList,
                    solAsset: solAsset,
                    solAmount: store.balanceSOL,
                    chains: store.chains,
                    totalChainCount: store.chains.count
                )

                HistoryPreview(activities: store.activities)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 96)
        }
        .background(UniteTheme.ink)
        .sheet(isPresented: $showingReceive) {
            ReceiveSheet()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSearch) {
            WalletSearchView()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSecurity) {
            SecurityCenterView()
                .environmentObject(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingGuide) {
            NotificationsView()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSecretReveal) {
            SecretRevealView()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            if store.marketUpdatedAt == nil {
                await store.refreshMarket()
            }
        }
    }
}

private enum WalletList: String, CaseIterable {
    case crypto = "Crypto"
    case watchlist = "Watchlist"
}

private struct WalletTopBar: View {
    let onSecurity: () -> Void
    let onSearch: () -> Void
    let onReceive: () -> Void
    let onGuide: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onSecurity) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(UniteTheme.raised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Security")

            Button(action: onSearch) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .bold))
                    Text("Search")
                        .roundedFont(19, weight: .bold)
                    Spacer()
                }
                .foregroundStyle(UniteTheme.muted)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(UniteTheme.raised, in: Capsule())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button(action: onGuide) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(UniteTheme.raised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Beta guide")

                Button(action: onReceive) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(UniteTheme.raised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Receive address")
            }
        }
    }
}

private struct WalletHero: View {
    let portfolioValue: Double
    let change: Double
    let address: String
    let chainCount: Int

    var body: some View {
        VStack(spacing: 16) {
            Text("Solana beta")
                .roundedFont(14, weight: .black)
                .foregroundStyle(UniteTheme.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(UniteTheme.cardEmphasis, in: Capsule())

            Text(usd(portfolioValue))
                .roundedFont(52, weight: .black)
                .minimumScaleFactor(0.78)
                .lineLimit(1)

            Text("Wallet value on supported beta network")
                .roundedFont(14, weight: .medium)
                .foregroundStyle(UniteTheme.secondaryText)

            HStack(spacing: 7) {
                Image(systemName: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 12, weight: .black))
                Text("\(change >= 0 ? "+" : "")\(String(format: "%.2f", change))% today")
                    .roundedFont(17, weight: .black)
            }
            .foregroundStyle(change >= 0 ? .white : UniteTheme.red)

            HStack(spacing: 8) {
                Text(address)
                Text("\(chainCount) supported beta chain")
            }
            .roundedFont(13, weight: .bold)
            .foregroundStyle(UniteTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
    }
}

private struct WalletPrimaryActions: View {
    let onReceive: () -> Void
    let onRecovery: () -> Void
    let onSecurity: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            WalletActionButton(title: "Receive", subtitle: "Copy address", icon: "arrow.down", action: onReceive)
            WalletActionButton(title: "Reveal", subtitle: "Recovery access", icon: "key", action: onRecovery)
            WalletActionButton(title: "Security", subtitle: "Lock settings", icon: "shield.lefthalf.filled", action: onSecurity)
        }
    }
}

private struct WalletActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text(title)
                    .roundedFont(15, weight: .black)
                Text(subtitle)
                    .roundedFont(12, weight: .bold)
                    .foregroundStyle(UniteTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct ReceiveSheet: View {
    @EnvironmentObject private var store: WalletStore
    @State private var copied = false

    private var selectedChain: WalletChain {
        store.chains.first ?? WalletChain(id: "solana", name: "Solana", symbol: "SOL", address: store.address, derivationPath: "", standards: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            UniteSectionHeader(
                eyebrow: "Receive",
                title: "Share this Solana address",
                detail: "Use this address for Solana transfers during the beta."
            )

            FakeQRCode(seed: selectedChain.address)
                .frame(width: 220, height: 220)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(selectedChain.name)
                    .roundedFont(17, weight: .black)
                Text(selectedChain.address)
                    .roundedFont(14, weight: .bold)
                    .foregroundStyle(UniteTheme.soft)
                    .textSelection(.enabled)
            }
            .padding(16)
            .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            UniteButton(
                title: copied ? "Address copied" : "Copy address",
                systemImage: copied ? "checkmark" : "doc.on.doc",
                tone: copied ? .secondary : .primary
            ) {
                UIPasteboard.general.string = selectedChain.address
                copied = true
            }

            UniteBanner(
                title: "Solana only",
                detail: "Only receive assets on Solana during this beta. Funds sent from another network can be lost permanently.",
                tone: .caution,
                icon: "exclamationmark.shield"
            )

            Spacer()
        }
        .padding(22)
        .background(UniteTheme.ink)
    }
}

private struct WalletSearchView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var query = ""

    private var results: [WalletChain] {
        guard !query.isEmpty else { return store.chains }
        return store.chains.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.symbol.localizedCaseInsensitiveContains(query) ||
            $0.address.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UniteSectionHeader(
                eyebrow: "Search",
                title: "Find supported chains",
                detail: "Search the beta address book by chain, symbol, or address."
            )
            UniteTextField(title: "Chain or address", text: $query, placeholder: "Solana, address")
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if query.isEmpty {
                        UniteBanner(
                            title: "Search stays narrow in beta",
                            detail: "Only supported wallet networks and stored addresses appear here right now.",
                            tone: .neutral,
                            icon: "scope"
                        )
                    } else if results.isEmpty {
                        UniteBanner(
                            title: "No matching chain",
                            detail: "Try a symbol, full chain name, or the address you expect to receive on.",
                            tone: .caution,
                            icon: "magnifyingglass"
                        )
                    } else {
                        ForEach(results) { chain in
                            WalletChainRow(chain: chain)
                                .padding(14)
                                .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(22)
        .background(UniteTheme.ink)
    }
}

private struct UniteTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .roundedFont(12, weight: .black)
                .foregroundStyle(UniteTheme.muted)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .roundedFont(17, weight: .bold)
                .padding(16)
                .uniteField()
        }
    }
}

private struct FakeQRCode: View {
    let seed: String

    var body: some View {
        let bytes = Array(seed.utf8)
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<13, id: \.self) { row in
                GridRow {
                    ForEach(0..<13, id: \.self) { column in
                        let index = (row * 13 + column) % max(bytes.count, 1)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(((Int(bytes[safe: index] ?? 0) + row + column) % 3 == 0) ? .black : .white)
                            .frame(width: 12, height: 12)
                    }
                }
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct WalletAssetSection: View {
    @Binding var selectedList: WalletList
    let solAsset: MarketAsset
    let solAmount: Double
    let chains: [WalletChain]
    let totalChainCount: Int

    var body: some View {
        VStack(spacing: 16) {
            SectionTitle(title: "Assets", trailing: "Wallet beta")
            HStack(spacing: 22) {
                ForEach(WalletList.allCases, id: \.self) { list in
                    Button {
                        selectedList = list
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(list == .crypto ? "Crypto" : "Watchlist")
                                .roundedFont(23, weight: .black)
                                .foregroundStyle(selectedList == list ? .white : UniteTheme.muted.opacity(0.55))
                            Capsule()
                                .fill(selectedList == list ? .white : Color.clear)
                                .frame(width: 76, height: 5)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            if selectedList == .crypto {
                WalletTokenRow(asset: solAsset, amount: solAmount)
                ForEach(chains) { chain in
                    WalletChainRow(chain: chain)
                }
                if totalChainCount == 1 {
                    BetaInfoCard()
                }
            } else {
                WatchlistPreview()
            }
        }
    }
}

private struct WalletChainRow: View {
    let chain: WalletChain

    var body: some View {
        HStack(spacing: 14) {
            ChainIcon(symbol: chain.symbol)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(chain.symbol)
                        .roundedFont(20, weight: .black)
                    Text(chain.name)
                        .roundedFont(12, weight: .black)
                        .foregroundStyle(UniteTheme.soft)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(UniteTheme.raised, in: Capsule())
                }

                Text(chain.standards)
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(UniteTheme.muted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text("0.0000")
                    .roundedFont(19, weight: .black)
                Text(chain.shortAddress)
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(UniteTheme.muted)
            }
        }
        .padding(16)
        .background(UniteTheme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ChainIcon: View {
    let symbol: String

    var body: some View {
        Text(String(symbol.prefix(1)))
            .roundedFont(20, weight: .black)
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
            .background(UniteTheme.mint, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.08)))
    }
}

private struct WalletTokenRow: View {
    let asset: MarketAsset
    let amount: Double

    private var value: Double {
        amount * (asset.price ?? 0)
    }

    var body: some View {
        HStack(spacing: 14) {
            TokenIcon(asset: asset, size: 54)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(asset.symbol)
                        .roundedFont(20, weight: .black)
                    Text(asset.name)
                        .roundedFont(12, weight: .black)
                        .foregroundStyle(UniteTheme.soft)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(UniteTheme.raised, in: Capsule())
                }

                HStack(spacing: 6) {
                    Text(usd(asset.price))
                        .roundedFont(15, weight: .bold)
                        .foregroundStyle(UniteTheme.muted)
                    Text("\((asset.change24h ?? 0) >= 0 ? "+" : "")\(String(format: "%.2f", asset.change24h ?? 0))%")
                        .roundedFont(15, weight: .bold)
                        .foregroundStyle(asset.isPositive ? UniteTheme.soft : UniteTheme.red)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(String(format: "%.4f", amount))
                    .roundedFont(19, weight: .black)
                Text(usd(value))
                    .roundedFont(15, weight: .bold)
                    .foregroundStyle(UniteTheme.muted)
            }
        }
        .padding(16)
        .background(UniteTheme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct BetaInfoCard: View {
    var body: some View {
        UniteBanner(
            title: "Current beta scope",
            detail: "This wallet currently focuses on secure setup, backup, receive, and read-only market tracking.",
            tone: .neutral,
            icon: "checkmark.shield"
        )
    }
}

private struct WatchlistPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Watchlist lives in Markets")
                .roundedFont(18, weight: .black)
            Text("Star assets in the Markets tab to keep them in your beta watchlist.")
                .roundedFont(14, weight: .medium)
                .foregroundStyle(UniteTheme.muted)
        }
        .uniteCard()
    }
}

private struct HistoryPreview: View {
    let activities: [WalletActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "At a glance", trailing: "")
            ForEach(activities) { activity in
                HStack(spacing: 12) {
                    Image(systemName: activity.icon)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 42, height: 42)
                        .background(.white, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.title)
                            .roundedFont(16, weight: .black)
                        Text(activity.detail)
                            .roundedFont(13, weight: .bold)
                            .foregroundStyle(UniteTheme.muted)
                    }
                    Spacer()
                    Text(activity.status)
                        .roundedFont(12, weight: .black)
                        .foregroundStyle(UniteTheme.soft)
                }
                .padding(16)
                .background(UniteTheme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }
}

private struct SecurityCenterView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var isUnlocking = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                UniteSectionHeader(
                    eyebrow: "Security",
                    title: "Device lock and access",
                    detail: "Control how this beta wallet unlocks on this device."
                )
                SecurityScoreCard(score: store.biometricLockEnabled ? "Strong" : "Needs review")
                SecurityToggle(title: "Biometric lock", detail: "Require device authentication before wallet access and recovery reveal", isOn: Binding(get: { store.biometricLockEnabled }, set: { store.setBiometricLockEnabled($0) }))
                SecurityToggle(title: "Diagnostics logs", detail: "Minimal device-side logs without recovery material or private keys", isOn: Binding(get: { store.diagnosticsEnabled }, set: { store.setDiagnosticsEnabled($0) }))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backup health")
                        .roundedFont(18, weight: .black)
                    Text(store.backupConfirmed ? "Recovery access is available behind device authentication." : "Backup confirmation is incomplete.")
                        .roundedFont(13, weight: .bold)
                        .foregroundStyle(store.backupConfirmed ? UniteTheme.soft : UniteTheme.yellow)
                }
                .padding(16)
                .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                UniteButton(
                    title: isUnlocking ? "Authenticating..." : "Check device unlock",
                    systemImage: isUnlocking ? "hourglass" : "faceid",
                    isEnabled: !isUnlocking,
                    tone: .primary
                ) {
                    isUnlocking = true
                    Task {
                        _ = await store.unlockApp()
                        isUnlocking = false
                    }
                }
            }
            .padding(22)
        }
        .background(UniteTheme.ink)
    }
}

private struct SecurityScoreCard: View {
    let score: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Protection")
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(UniteTheme.muted)
                Text(score)
                    .roundedFont(34, weight: .black)
            }
            Spacer()
            Image(systemName: "shield.checkered")
                .font(.system(size: 34, weight: .black))
        }
        .padding(18)
        .background(UniteTheme.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct SecurityToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .roundedFont(16, weight: .black)
                Text(detail)
                    .roundedFont(12, weight: .bold)
                    .foregroundStyle(UniteTheme.muted)
            }
        }
        .tint(.white)
        .padding(16)
        .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct NotificationsView: View {
    @EnvironmentObject private var store: WalletStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UniteSectionHeader(
                eyebrow: "Guide",
                title: "What this beta includes",
                detail: "Use these notes to understand what is ready now and what is still intentionally missing."
            )
            ForEach(store.notifications) { notification in
                HStack(spacing: 12) {
                    Text(notification.severity)
                        .roundedFont(12, weight: .black)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.white, in: Capsule())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(notification.title)
                            .roundedFont(16, weight: .black)
                        Text(notification.detail)
                            .roundedFont(12, weight: .bold)
                            .foregroundStyle(UniteTheme.muted)
                    }
                    Spacer()
                }
                .padding(14)
                .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Spacer()
        }
        .padding(22)
        .background(UniteTheme.ink)
    }
}

struct SectionTitle: View {
    let title: String
    let trailing: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .roundedFont(24, weight: .black)
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(UniteTheme.soft)
            Spacer()
            if !trailing.isEmpty {
                Text(trailing)
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(UniteTheme.muted)
            }
        }
    }
}
