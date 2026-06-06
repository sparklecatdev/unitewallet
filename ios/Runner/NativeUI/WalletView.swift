import SwiftUI
import UIKit

struct WalletView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var selectedList = WalletList.crypto
    @State private var route: WalletRoute?

    private var activeChain: WalletChain? {
        store.currentChain
    }

    private var activeAsset: MarketAsset? {
        guard let network = activeChain?.network else { return nil }
        return store.marketAssets.first(where: { $0.id == network.coinGeckoID })
    }

    private var visibleChains: [WalletChain] {
        store.chains.filter { chain in
            guard !store.hideSmallBalances else { return true }
            return abs(store.nativeBalance(for: chain.id)) >= 0.0000001
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                WalletTopBar(
                    onSettings: { route = .settings },
                    onSearch: { route = .search },
                    onWalletConnect: { route = .walletConnect }
                )
                .padding(.top, 12)

                WalletHero(
                    portfolioValue: store.portfolioValue,
                    change: activeAsset?.change24h ?? 0,
                    address: store.shortAddress,
                    chainCount: store.chains.count,
                    syncMessage: store.syncMessage
                )

                WalletPrimaryActions(
                    onSend: { route = .send },
                    onReceive: { route = .receive },
                    onSecurity: { route = .settings },
                    onRecovery: { route = .secret }
                )

                WalletAssetSection(
                    selectedList: $selectedList,
                    chains: visibleChains,
                    layout: store.assetLayout
                )

                HistoryPreview(activities: store.activities)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 96)
        }
        .background(UniteTheme.ink)
        .fullScreenCover(item: $route) { route in
            switch route {
            case .receive:
                ReceiveScreen()
                    .environmentObject(store)
            case .search:
                WalletSearchView()
                    .environmentObject(store)
            case .settings:
                WalletSettingsView()
                    .environmentObject(store)
            case .send:
                SendScreen()
                    .environmentObject(store)
            case .walletConnect:
                WalletConnectHubView()
                    .environmentObject(store)
            case .secret:
                SecretRevealView()
                    .environmentObject(store)
            }
        }
        .task {
            if store.marketUpdatedAt == nil {
                await store.refreshMarket()
            }
            await store.refreshChains()
        }
    }
}

private enum WalletRoute: String, Identifiable {
    case receive
    case search
    case settings
    case send
    case walletConnect
    case secret

    var id: String { rawValue }
}

private enum WalletList: String, CaseIterable {
    case crypto = "Crypto"
    case watchlist = "Watchlist"
}

private struct WalletTopBar: View {
    let onSettings: () -> Void
    let onSearch: () -> Void
    let onWalletConnect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            IconCircleButton(systemImage: "gearshape", action: onSettings, label: "Wallet settings")

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

            IconCircleButton(systemImage: "qrcode.viewfinder", action: onWalletConnect, label: "WalletConnect")
        }
    }
}

private struct WalletHero: View {
    let portfolioValue: Double
    let change: Double
    let address: String
    let chainCount: Int
    let syncMessage: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Text("Wallet")
                    .roundedFont(19, weight: .black)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(UniteTheme.raised, in: Capsule())

                Button {
                    UIPasteboard.general.string = address
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()
            }

            Text(usd(portfolioValue))
                .roundedFont(58, weight: .black)
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            HStack(spacing: 8) {
                Image(systemName: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 12, weight: .black))
                Text("\(change >= 0 ? "+" : "")\(String(format: "%.2f", change))% today")
                    .roundedFont(17, weight: .black)
            }
            .foregroundStyle(change >= 0 ? UniteTheme.green : UniteTheme.red)

            Text("\(address)  •  \(chainCount) networks")
                .roundedFont(13, weight: .bold)
                .foregroundStyle(UniteTheme.muted)

            UniteBanner(
                title: "Encrypted sync status",
                detail: syncMessage,
                tone: .neutral,
                icon: "icloud"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

private struct WalletPrimaryActions: View {
    let onSend: () -> Void
    let onReceive: () -> Void
    let onSecurity: () -> Void
    let onRecovery: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            WalletActionButton(title: "Send", icon: "arrow.up.right", action: onSend)
            WalletActionButton(title: "Receive", icon: "arrow.down", action: onReceive)
            WalletActionButton(title: "Protect", icon: "lock.shield", action: onSecurity)
            WalletActionButton(title: "Backup", icon: "key", action: onRecovery)
        }
    }
}

private struct WalletActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(title == "Receive" ? UniteTheme.primaryActionText : .white)
                    .frame(width: 68, height: 68)
                    .background(title == "Receive" ? UniteTheme.mint : UniteTheme.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text(title)
                    .roundedFont(15, weight: .black)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct WalletAssetSection: View {
    @EnvironmentObject private var store: WalletStore
    @Binding var selectedList: WalletList
    let chains: [WalletChain]
    let layout: AssetLayoutPreset

    var body: some View {
        VStack(spacing: 16) {
            SectionTitle(title: "Assets", trailing: "Live networks")
            HStack(spacing: 22) {
                ForEach(WalletList.allCases, id: \.self) { list in
                    Button {
                        selectedList = list
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(list.rawValue)
                                .roundedFont(23, weight: .black)
                                .foregroundStyle(selectedList == list ? .white : UniteTheme.muted.opacity(0.55))
                            Capsule()
                                .fill(selectedList == list ? UniteTheme.mint : Color.clear)
                                .frame(width: 76, height: 5)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            if selectedList == .crypto {
                ForEach(chains) { chain in
                    Button {
                        store.setPrimaryChain(chain.id)
                    } label: {
                        WalletChainRow(
                            chain: chain,
                            balance: store.formattedBalance(for: chain),
                            fiatValue: store.fiatValue(for: chain),
                            snapshot: store.balanceSnapshot(for: chain),
                            isSelected: chain.id == store.primaryChainID,
                            layout: layout
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                WatchlistPreview()
            }
        }
    }
}

private struct WalletChainRow: View {
    let chain: WalletChain
    let balance: String
    let fiatValue: Double?
    let snapshot: ChainBalanceSnapshot
    let isSelected: Bool
    let layout: AssetLayoutPreset

    private var cardPadding: CGFloat {
        switch layout {
        case .compact: 13
        case .balanced: 16
        case .spacious: 20
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ChainIcon(symbol: chain.symbol)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(chain.symbol)
                        .roundedFont(22, weight: .black)
                    Text(chain.name)
                        .roundedFont(12, weight: .black)
                        .foregroundStyle(UniteTheme.soft)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(UniteTheme.raised, in: Capsule())
                }

                Text(chain.shortAddress)
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(UniteTheme.muted)

                Text(snapshot.message ?? "Live network")
                    .roundedFont(12, weight: .medium)
                    .foregroundStyle(snapshot.status == .failed ? UniteTheme.red : UniteTheme.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(balance)
                    .roundedFont(21, weight: .black)
                Text(usd(fiatValue))
                    .roundedFont(14, weight: .bold)
                    .foregroundStyle(snapshot.status == .failed ? UniteTheme.red : UniteTheme.soft)
                if let updatedAt = snapshot.updatedAt {
                    Text(updatedAt.formatted(date: .omitted, time: .shortened))
                        .roundedFont(11, weight: .bold)
                        .foregroundStyle(UniteTheme.muted)
                }
            }
        }
        .padding(cardPadding)
        .background((isSelected ? UniteTheme.raised : UniteTheme.panel), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ReceiveScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WalletStore
    @State private var query = ""
    @State private var copiedID = ""

    private var filteredChains: [WalletChain] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return store.chains }
        return store.chains.filter {
            $0.name.lowercased().contains(needle) ||
            $0.symbol.lowercased().contains(needle) ||
            $0.address.lowercased().contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    UniteTextField(title: "Search", text: $query, placeholder: "Search networks")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            FilterChip(title: "All", isSelected: true)
                            ForEach(store.chains) { chain in
                                FilterChip(title: chain.symbol, isSelected: false)
                            }
                        }
                    }

                    SectionTitle(title: "Popular", trailing: "")
                    ForEach(filteredChains.prefix(3)) { chain in
                        ReceiveChainRow(chain: chain, copiedID: $copiedID)
                    }

                    SectionTitle(title: "All crypto", trailing: "")
                    ForEach(filteredChains) { chain in
                        ReceiveChainRow(chain: chain, copiedID: $copiedID)
                    }
                }
                .padding(18)
                .padding(.bottom, 40)
            }
            .background(UniteTheme.ink)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Receive")
                        .roundedFont(24, weight: .black)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ReceiveChainRow: View {
    let chain: WalletChain
    @Binding var copiedID: String

    var body: some View {
        HStack(spacing: 14) {
            ChainIcon(symbol: chain.symbol)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(chain.symbol)
                        .roundedFont(18, weight: .black)
                    Text(chain.name)
                        .roundedFont(12, weight: .black)
                        .foregroundStyle(UniteTheme.soft)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(UniteTheme.raised, in: Capsule())
                }

                Text(chain.shortAddress)
                    .roundedFont(14, weight: .bold)
                    .foregroundStyle(UniteTheme.muted)
            }

            Spacer()

            NavigationLink {
                ReceiveAddressDetailView(chain: chain)
            } label: {
                Image(systemName: "qrcode")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(UniteTheme.raised, in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                UIPasteboard.general.string = chain.address
                copiedID = chain.id
            } label: {
                Image(systemName: copiedID == chain.id ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(UniteTheme.raised, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(UniteTheme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ReceiveAddressDetailView: View {
    let chain: WalletChain
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            UniteSectionHeader(
                eyebrow: "Receive \(chain.symbol)",
                title: chain.name,
                detail: "Only send assets on the exact matching network to this address."
            )

            FakeQRCode(seed: chain.address)
                .frame(width: 240, height: 240)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Address")
                    .roundedFont(13, weight: .black)
                    .foregroundStyle(UniteTheme.muted)
                Text(chain.address)
                    .roundedFont(15, weight: .bold)
                    .textSelection(.enabled)
            }
            .padding(18)
            .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            UniteButton(
                title: copied ? "Address copied" : "Copy address",
                systemImage: copied ? "checkmark" : "doc.on.doc",
                tone: copied ? .secondary : .primary
            ) {
                UIPasteboard.general.string = chain.address
                copied = true
            }

            UniteBanner(
                title: "Match the network exactly",
                detail: "Cross-network transfers can be lost permanently. Double-check the asset and network before sharing this address.",
                tone: .caution,
                icon: "exclamationmark.shield"
            )

            Spacer()
        }
        .padding(22)
        .background(UniteTheme.ink)
    }
}

private struct SendScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WalletStore
    @State private var recipient = ""
    @State private var amount = ""
    @State private var name = ""
    @State private var selectedAssetID = ""
    @State private var localMessage: String?

    private var currentChain: WalletChain? {
        store.currentChain
    }

    private var currentAssets: [WalletAssetBalance] {
        store.currentAssets
    }

    private var selectedAsset: WalletAssetBalance? {
        currentAssets.first(where: { $0.id == selectedAssetID }) ?? store.currentAsset
    }

    private var matchingContacts: [WalletStoreContact] {
        guard let chain = currentChain else { return [] }
        return store.contacts.filter {
            $0.chain == chain.name && ($0.assetID == nil || $0.assetID == selectedAsset?.id)
        }
    }

    private var addressValidation: (title: String, detail: String, tone: UniteBanner.Tone, icon: String) {
        guard let chain = currentChain else {
            return ("No active network", "Choose a network before preparing a transfer.", .caution, "exclamationmark.triangle")
        }
        let trimmed = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ("Destination check", "Paste an address to validate it against \(chain.name).", .neutral, "scope")
        }
        if WalletCoreBridge.validateAddress(trimmed, chainID: chain.id) {
            let shortRecipient: String
            if trimmed.count > 14 {
                shortRecipient = "\(trimmed.prefix(6))...\(trimmed.suffix(6))"
            } else {
                shortRecipient = trimmed
            }
            return ("Address format looks valid", shortRecipient, .success, "checkmark.shield")
        }
        return ("Address format does not match \(chain.name)", "This destination does not validate for the selected network.", .caution, "shield.lefthalf.filled")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    UniteSectionHeader(
                        eyebrow: "Send",
                        title: "Prepare a transfer",
                        detail: "Choose the network, confirm the destination format, and save trusted recipients from one place."
                    )

                    if store.chains.count > 1 {
                        Picker("Send network", selection: Binding(
                            get: { store.primaryChainID },
                            set: { store.setPrimaryChain($0) }
                        )) {
                            ForEach(store.chains) { chain in
                                Text(chain.name).tag(chain.id)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if currentAssets.count > 1 {
                        Picker("Asset", selection: $selectedAssetID) {
                            ForEach(currentAssets) { asset in
                                Text(asset.symbol).tag(asset.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    UniteTextField(title: "Recipient address", text: $recipient, placeholder: "Paste the destination address")
                    UniteTextField(title: "Amount", text: $amount, placeholder: "0.00", keyboard: .decimalPad)
                    UniteTextField(title: "Save contact name", text: $name, placeholder: "Optional")

                    if !matchingContacts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "Trusted recipients", trailing: "")
                            ForEach(matchingContacts.prefix(3)) { contact in
                                Button {
                                    recipient = contact.address
                                    if name.isEmpty {
                                        name = contact.name
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(contact.name)
                                                .roundedFont(15, weight: .black)
                                            Text(contact.shortAddress)
                                                .roundedFont(13, weight: .bold)
                                                .foregroundStyle(UniteTheme.muted)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right.circle")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(UniteTheme.soft)
                                    }
                                    .padding(14)
                                    .background(UniteTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let asset = selectedAsset {
                        UniteBanner(
                            title: "\(asset.symbol) available",
                            detail: "\(asset.balance.formattedString(maxFractionDigits: min(asset.decimals, 8))) \(asset.symbol) on \(asset.accountAddress)",
                            tone: .neutral,
                            icon: "wallet.bifold"
                        )
                    }

                    UniteBanner(
                        title: addressValidation.title,
                        detail: addressValidation.detail,
                        tone: addressValidation.tone,
                        icon: addressValidation.icon
                    )

                    if let review = store.pendingTransferReview {
                        TransferReviewCard(review: review)
                    }

                    if let receipt = store.lastBroadcastReceipt {
                        UniteBanner(
                            title: "Transfer submitted",
                            detail: receipt.txHash,
                            tone: .success,
                            icon: "paperplane"
                        )
                    }

                    if let message = store.sendMessage ?? localMessage {
                        UniteBanner(
                            title: "Transfer update",
                            detail: message,
                            tone: .success,
                            icon: "checkmark.circle"
                        )
                    }

                    if let error = store.sendErrorMessage {
                        UniteBanner(
                            title: "Transfer blocked",
                            detail: error,
                            tone: .caution,
                            icon: "exclamationmark.triangle"
                        )
                    }

                    UniteButton(
                        title: store.pendingTransferReview == nil ? "Prepare transfer" : "Refresh quote",
                        systemImage: "arrow.up.right",
                        isLoading: store.isPreparingTransfer
                    ) {
                        Task {
                            localMessage = await store.prepareTransfer(
                                recipient: recipient,
                                amount: amount,
                                assetID: selectedAsset?.id,
                                contactName: name
                            )
                        }
                    }

                    if store.pendingTransferReview != nil {
                        UniteButton(
                            title: "Sign and broadcast",
                            systemImage: "faceid",
                            isLoading: store.isSendingTransfer
                        ) {
                            Task {
                                localMessage = await store.confirmPreparedTransfer()
                            }
                        }

                        UniteButton(title: "Clear draft", systemImage: "xmark", tone: .secondary) {
                            store.clearTransferComposer()
                            localMessage = nil
                        }
                    }
                }
                .padding(18)
            }
            .background(UniteTheme.ink)
            .onAppear {
                if selectedAssetID.isEmpty {
                    selectedAssetID = store.currentAsset?.id ?? ""
                }
            }
            .onChange(of: store.primaryChainID) { _ in
                selectedAssetID = store.currentAsset?.id ?? ""
            }
            .onChange(of: currentAssets.map(\.id)) { _ in
                if currentAssets.contains(where: { $0.id == selectedAssetID }) == false {
                    selectedAssetID = store.currentAsset?.id ?? ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct WalletSearchView: View {
    @Environment(\.dismiss) private var dismiss
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
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                UniteSectionHeader(
                    eyebrow: "Search",
                    title: "Find supported networks",
                    detail: "Search by symbol, network name, or the address you expect to use."
                )
                UniteTextField(title: "Network or address", text: $query, placeholder: "Solana, Ethereum, BTC")
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        if query.isEmpty {
                            UniteBanner(
                                title: "Search stays narrow in this build",
                                detail: "Only the networks already active in your wallet appear here.",
                                tone: .neutral,
                                icon: "scope"
                            )
                        } else if results.isEmpty {
                            UniteBanner(
                                title: "No matching network",
                                detail: "Try the full chain name, symbol, or address.",
                                tone: .caution,
                                icon: "magnifyingglass"
                            )
                        } else {
                            ForEach(results) { chain in
                                WalletChainRow(
                                    chain: chain,
                                    balance: store.formattedBalance(for: chain),
                                    fiatValue: store.fiatValue(for: chain),
                                    snapshot: store.balanceSnapshot(for: chain),
                                    isSelected: chain.id == store.primaryChainID,
                                    layout: .balanced
                                )
                            }
                        }
                    }
                }
            }
            .padding(22)
            .background(UniteTheme.ink)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct WalletSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WalletStore
    @State private var syncCode = ""
    @State private var syncResult: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Asset layout")
                            .roundedFont(16, weight: .black)

                        LayoutPreviewCard(layout: store.assetLayout)

                        HStack(spacing: 12) {
                            ForEach(AssetLayoutPreset.allCases) { preset in
                                Button {
                                    store.setAssetLayout(preset)
                                } label: {
                                    Text("\(preset.rawValue)")
                                        .roundedFont(20, weight: .black)
                                        .foregroundStyle(store.assetLayout == preset ? UniteTheme.mint : .white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 54)
                                        .background(UniteTheme.panel, in: Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(store.assetLayout == preset ? UniteTheme.mint : Color.clear, lineWidth: 3)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .uniteCard()

                    VStack(alignment: .leading, spacing: 16) {
                        SettingsRow(title: "Manage crypto", detail: "Search, copy, and switch the networks already in this wallet.")
                        Toggle("Hide assets < $0.01 USD", isOn: Binding(
                            get: { store.hideSmallBalances },
                            set: { store.setHideSmallBalances($0) }
                        ))
                        .tint(UniteTheme.mint)
                        .roundedFont(16, weight: .bold)

                        Toggle("Hide NFTs", isOn: Binding(
                            get: { store.hideNFTs },
                            set: { store.setHideNFTs($0) }
                        ))
                        .tint(UniteTheme.mint)
                        .roundedFont(16, weight: .bold)

                        Toggle("Use Face ID", isOn: Binding(
                            get: { store.faceIDEnabled },
                            set: { store.setBiometricLockEnabled($0) }
                        ))
                        .tint(UniteTheme.mint)
                        .roundedFont(16, weight: .bold)
                    }
                    .uniteCard()

                    VStack(alignment: .leading, spacing: 16) {
                        UniteSectionHeader(
                            eyebrow: "Encrypted sync",
                            title: "iCloud wallet backup",
                            detail: "The wallet package is encrypted with your 6-digit Unite code before it leaves this device."
                        )

                        UniteTextField(title: "Confirm 6-digit code", text: $syncCode, placeholder: "123456", keyboard: .numberPad)

                        if let syncResult {
                            UniteBanner(
                                title: syncResult == "Synced" ? "Encrypted backup updated" : "Sync needs another look",
                                detail: syncResult == "Synced" ? store.syncMessage : syncResult,
                                tone: syncResult == "Synced" ? .success : .caution,
                                icon: syncResult == "Synced" ? "icloud.and.arrow.up" : "exclamationmark.triangle"
                            )
                        }

                        UniteButton(title: "Sync encrypted wallet", systemImage: "icloud.and.arrow.up") {
                            if let error = store.syncEncryptedWallet(passcode: syncCode) {
                                syncResult = error
                            } else {
                                syncResult = "Synced"
                            }
                        }

                        if store.hasSyncBackup {
                            UniteButton(title: "Remove encrypted backup", systemImage: "trash", tone: .caution) {
                                store.clearSyncBackup()
                                syncResult = nil
                            }
                        }
                    }
                    .uniteCard()
                }
                .padding(18)
                .padding(.bottom, 40)
            }
            .background(UniteTheme.ink)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct LayoutPreviewCard: View {
    let layout: AssetLayoutPreset

    private var amount: String {
        switch layout {
        case .compact: "0.5"
        case .balanced: "1.25"
        case .spacious: "3.88"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ChainIcon(symbol: "BTC")
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("BTC")
                            .roundedFont(20, weight: .black)
                        Text("Bitcoin")
                            .roundedFont(12, weight: .black)
                            .foregroundStyle(UniteTheme.soft)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(UniteTheme.raised, in: Capsule())
                    }
                    HStack(spacing: 6) {
                        Text("$108,200.00")
                            .roundedFont(14, weight: .bold)
                            .foregroundStyle(UniteTheme.soft)
                        Text("+12.00%")
                            .roundedFont(14, weight: .bold)
                            .foregroundStyle(UniteTheme.green)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(amount)
                        .roundedFont(21, weight: .black)
                    Text("$54,100.00")
                        .roundedFont(15, weight: .bold)
                        .foregroundStyle(UniteTheme.soft)
                }
            }
            .padding(layout == .compact ? 12 : layout == .balanced ? 15 : 18)
            .background(UniteTheme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(14)
        .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct WalletConnectHubView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WalletStore
    @State private var uri = ""
    @State private var localMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    UniteSectionHeader(
                        eyebrow: "WalletConnect",
                        title: "Connection center",
                        detail: "Paste a `wc:` URI, review requested chains and methods, and approve signatures behind device authentication."
                    )

                    UniteTextField(title: "Pair URI", text: $uri, placeholder: "wc:...")

                    UniteButton(
                        title: "Pair session",
                        systemImage: "link",
                        isLoading: store.isPairingWalletConnect
                    ) {
                        Task {
                            localMessage = await store.pairWalletConnect(uri: uri)
                        }
                    }

                    if let message = store.walletConnectMessage ?? localMessage {
                        UniteBanner(
                            title: "WalletConnect update",
                            detail: message,
                            tone: localMessage == nil ? .success : .caution,
                            icon: "link.badge.plus"
                        )
                    }

                    if let proposal = store.pendingWalletConnectProposal {
                        WalletConnectProposalCard(proposal: proposal)

                        UniteButton(title: "Approve proposal", systemImage: "checkmark.shield") {
                            Task {
                                localMessage = await store.approvePendingWalletConnectProposal()
                            }
                        }

                        UniteButton(title: "Reject proposal", systemImage: "xmark", tone: .caution) {
                            Task {
                                await store.rejectPendingWalletConnectProposal()
                            }
                        }
                    }

                    if let request = store.pendingWalletConnectRequest {
                        WalletConnectRequestCard(request: request)

                        UniteButton(title: "Approve request", systemImage: "faceid") {
                            Task {
                                localMessage = await store.approvePendingWalletConnectRequest()
                            }
                        }

                        UniteButton(title: "Reject request", systemImage: "xmark", tone: .caution) {
                            Task {
                                await store.rejectPendingWalletConnectRequest()
                            }
                        }
                    }

                    SectionTitle(title: "Active sessions", trailing: "")

                    if store.walletConnectSessions.isEmpty {
                        UniteBanner(
                            title: "No active sessions",
                            detail: "Paste a WalletConnect URI to start pairing.",
                            tone: .neutral,
                            icon: "link"
                        )
                    } else {
                        ForEach(store.walletConnectSessions) { session in
                            WalletConnectSessionRow(session: session) {
                                Task {
                                    await store.disconnectWalletConnectSession(session)
                                }
                            }
                        }
                    }
                }
                .padding(22)
            }
            .background(UniteTheme.ink)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .walletConnectPairURI)) { notification in
            if let value = notification.object as? String {
                uri = value
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct TransferReviewCard: View {
    let review: TransferReview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Review", trailing: "")
            TransferReviewRow(label: "Send", value: "\(review.draft.amount.formattedString(maxFractionDigits: min(review.quote.asset.decimals, 8))) \(review.quote.asset.symbol)")
            TransferReviewRow(label: "To", value: review.draft.recipient)
            TransferReviewRow(label: "From", value: review.sourceAddress)
            TransferReviewRow(label: "Fee", value: "\(review.quote.fee.formattedString(maxFractionDigits: 8)) \(review.quote.feeSymbol)")
            TransferReviewRow(label: "Network", value: review.quote.networkDetail)
            TransferReviewRow(label: "Total debit", value: "\(review.quote.totalDebit.formattedString(maxFractionDigits: min(review.quote.asset.decimals, 8))) \(review.quote.asset.symbol)")
        }
        .uniteCard()
    }
}

private struct TransferReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .roundedFont(12, weight: .black)
                .foregroundStyle(UniteTheme.muted)
            Text(value)
                .roundedFont(14, weight: .bold)
                .textSelection(.enabled)
        }
    }
}

private struct WalletConnectProposalCard: View {
    let proposal: WalletConnectProposalState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: proposal.name, trailing: "Proposal")
            TransferReviewRow(label: "URL", value: proposal.url)
            TransferReviewRow(label: "Chains", value: proposal.requiredChains.joined(separator: ", "))
            TransferReviewRow(label: "Methods", value: proposal.methods.joined(separator: ", "))
            if proposal.events.isEmpty == false {
                TransferReviewRow(label: "Events", value: proposal.events.joined(separator: ", "))
            }
        }
        .uniteCard()
    }
}

private struct WalletConnectRequestCard: View {
    let request: WalletConnectRequestState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: request.dappName, trailing: request.method)
            TransferReviewRow(label: "Chain", value: request.chainID)
            TransferReviewRow(label: "Payload", value: request.paramsPreview)
        }
        .uniteCard()
    }
}

private struct WalletConnectSessionRow: View {
    let session: WalletConnectSessionState
    let disconnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .roundedFont(15, weight: .black)
                Text(session.chains.joined(separator: ", "))
                    .roundedFont(12, weight: .bold)
                    .foregroundStyle(UniteTheme.muted)
                Text(session.url)
                    .roundedFont(12, weight: .medium)
                    .foregroundStyle(UniteTheme.soft)
            }
            Spacer()
            Button("Disconnect", action: disconnect)
                .roundedFont(13, weight: .black)
                .foregroundStyle(UniteTheme.red)
        }
        .padding(14)
        .background(UniteTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WatchlistPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Watchlist lives in Markets")
                .roundedFont(18, weight: .black)
            Text("Star assets in the Markets tab to keep them in your watchlist.")
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

struct UniteTextField: View {
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

struct FakeQRCode: View {
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

struct ChainIcon: View {
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

private struct IconCircleButton: View {
    let systemImage: String
    let action: () -> Void
    let label: String

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(UniteTheme.raised, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .roundedFont(14, weight: .bold)
            .foregroundStyle(isSelected ? UniteTheme.mint : .white)
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? UniteTheme.mint : Color.clear, lineWidth: 2)
            )
    }
}

private struct SettingsRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .roundedFont(16, weight: .black)
                Text(detail)
                    .roundedFont(12, weight: .medium)
                    .foregroundStyle(UniteTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(UniteTheme.soft)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct SectionTitle: View {
    let title: String
    let trailing: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .roundedFont(24, weight: .black)
            if !trailing.isEmpty {
                Spacer()
                Text(trailing)
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(UniteTheme.muted)
            }
        }
    }
}
