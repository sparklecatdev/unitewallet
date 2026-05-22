import SwiftUI

struct MarketView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var selectedAsset: MarketAsset?
    @State private var query = ""
    @State private var filter: MarketFilter = .all
    @State private var sort: MarketSort = .rank

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Market")
                            .roundedFont(32, weight: .black)
                        Spacer()
                        Button {
                            Task { await store.refreshMarket() }
                        } label: {
                            Image(systemName: store.isRefreshingMarket ? "hourglass" : "arrow.clockwise")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 48, height: 48)
                                .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Text(store.marketUpdatedAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Public CoinGecko market data")
                        .roundedFont(13, weight: .medium)
                        .foregroundStyle(UniteTheme.muted)

                    let sol = store.marketAssets.first
                    Text(usd(sol?.price))
                        .roundedFont(52, weight: .black)
                    Text("\((sol?.change24h ?? 0) >= 0 ? "+" : "")\(String(format: "%.2f", sol?.change24h ?? 0))% 24h")
                        .roundedFont(15, weight: .black)
                        .foregroundStyle((sol?.change24h ?? 0) >= 0 ? UniteTheme.green : UniteTheme.red)
                    Text(store.marketMessage)
                        .roundedFont(15, weight: .bold)
                        .foregroundStyle(store.marketMessage.contains("unavailable") ? UniteTheme.red : UniteTheme.green)

                    HStack(spacing: 10) {
                        Button {
                            store.setMarketAutoRefreshEnabled(!store.marketAutoRefreshEnabled)
                        } label: {
                            Label(store.marketAutoRefreshEnabled ? "Auto live" : "Manual", systemImage: store.marketAutoRefreshEnabled ? "bolt.fill" : "pause.fill")
                                .roundedFont(13, weight: .bold)
                                .foregroundStyle(store.marketAutoRefreshEnabled ? .black : .white)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(store.marketAutoRefreshEnabled ? .white : UniteTheme.raised, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Menu {
                            ForEach(MarketSort.allCases) { option in
                                Button(option.rawValue) { sort = option }
                            }
                        } label: {
                            Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                                .roundedFont(13, weight: .bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(UniteTheme.raised, in: Capsule())
                        }
                    }
                }
                .uniteCard()

                MarketSearchField(text: $query)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(MarketFilter.allCases) { option in
                            Button {
                                filter = option
                            } label: {
                                Text(option.rawValue)
                                    .roundedFont(13, weight: .bold)
                                    .foregroundStyle(filter == option ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                                    .background(filter == option ? .white : UniteTheme.raised, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }

                if visibleAssets.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(emptyTitle)
                            .roundedFont(18, weight: .black)
                        Text(emptyDetail)
                            .roundedFont(14, weight: .medium)
                            .foregroundStyle(UniteTheme.muted)
                    }
                    .uniteCard()
                } else {
                    ForEach(visibleAssets) { asset in
                        MarketRow(
                            asset: asset,
                            isWatching: store.isWatchingMarketAsset(asset),
                            onOpen: { selectedAsset = asset },
                            onToggleWatch: { store.toggleMarketWatch(asset) }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 104)
        }
        .background(UniteTheme.ink)
        .refreshable {
            await store.refreshMarket()
        }
        .task {
            await runMarketLoop()
        }
        .sheet(item: $selectedAsset) { asset in
            MarketDetailView(asset: asset)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var visibleAssets: [MarketAsset] {
        var assets = store.marketAssets

        switch filter {
        case .all:
            break
        case .watchlist:
            assets = assets.filter { store.isWatchingMarketAsset($0) }
        case .gainers:
            assets = assets.filter { ($0.change24h ?? 0) > 0 }
        case .losers:
            assets = assets.filter { ($0.change24h ?? 0) < 0 }
        }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !needle.isEmpty {
            assets = assets.filter {
                $0.name.lowercased().contains(needle) ||
                $0.symbol.lowercased().contains(needle)
            }
        }

        switch sort {
        case .rank:
            assets.sort { ($0.rank ?? Int.max) < ($1.rank ?? Int.max) }
        case .price:
            assets.sort { ($0.price ?? 0) > ($1.price ?? 0) }
        case .change:
            assets.sort { ($0.change24h ?? -Double.greatestFiniteMagnitude) > ($1.change24h ?? -Double.greatestFiniteMagnitude) }
        case .volume:
            assets.sort { ($0.volume ?? 0) > ($1.volume ?? 0) }
        }

        return assets
    }

    private var emptyTitle: String {
        filter == .watchlist ? "No watched assets" : "No markets found"
    }

    private var emptyDetail: String {
        filter == .watchlist ? "Tap the star on an asset to keep it here." : "Try a different search or filter."
    }

    private func runMarketLoop() async {
        if store.marketUpdatedAt == nil {
            await store.refreshMarket()
        }

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard store.marketAutoRefreshEnabled else { continue }
            await store.refreshMarket()
        }
    }
}

struct MarketRow: View {
    let asset: MarketAsset
    let isWatching: Bool
    let onOpen: () -> Void
    let onToggleWatch: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    TokenIcon(asset: asset, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(asset.name)
                            .roundedFont(15, weight: .black)
                        Text(asset.rank.map { "\(asset.symbol)  #\($0)" } ?? asset.symbol)
                            .roundedFont(13, weight: .medium)
                            .foregroundStyle(UniteTheme.muted)
                    }
                    Spacer()
                    Sparkline(points: asset.sparkline, tint: asset.isPositive ? UniteTheme.green : UniteTheme.red)
                        .frame(width: 78, height: 40)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(usd(asset.price))
                            .roundedFont(15, weight: .black)
                        Text("\(asset.isPositive ? "+" : "")\(String(format: "%.2f", asset.change24h ?? 0))%")
                            .roundedFont(13, weight: .black)
                            .foregroundStyle(asset.isPositive ? UniteTheme.green : UniteTheme.red)
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: onToggleWatch) {
                Image(systemName: isWatching ? "star.fill" : "star")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isWatching ? UniteTheme.yellow : UniteTheme.muted)
                    .frame(width: 38, height: 38)
                    .background(UniteTheme.raised, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .uniteCard()
    }
}

struct MarketDetailView: View {
    @EnvironmentObject private var store: WalletStore
    let asset: MarketAsset
    @State private var showingBuy = false
    @State private var selectedRange: MarketRange = .day
    @State private var alertPrice = ""
    @State private var alertSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                TokenIcon(asset: asset, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(asset.name)
                        .roundedFont(24, weight: .black)
                    Text(asset.rank.map { "\(asset.symbol) rank #\($0)" } ?? asset.symbol)
                        .roundedFont(13, weight: .bold)
                        .foregroundStyle(UniteTheme.muted)
                }
                Spacer()
            }

            Text(usd(asset.price))
                .roundedFont(48, weight: .black)

            HStack(spacing: 8) {
                ForEach(MarketRange.allCases) { range in
                    Button {
                        selectedRange = range
                    } label: {
                        Text(range.rawValue)
                            .roundedFont(12, weight: .black)
                            .foregroundStyle(selectedRange == range ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(selectedRange == range ? .white : UniteTheme.raised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Sparkline(points: chartPoints, tint: selectedRangeChange >= 0 ? UniteTheme.green : UniteTheme.red)
                .frame(height: 180)
                .padding(14)
                .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "24h", value: "\(asset.isPositive ? "+" : "")\(String(format: "%.2f", asset.change24h ?? 0))%")
                StatTile(title: "7d", value: "\((asset.change7d ?? 0) >= 0 ? "+" : "")\(String(format: "%.2f", asset.change7d ?? 0))%")
                StatTile(title: "Market cap", value: usd(asset.marketCap))
                StatTile(title: "Volume", value: usd(asset.volume))
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Price alert")
                            .roundedFont(15, weight: .black)
                        Text(existingAlertText)
                            .roundedFont(12, weight: .medium)
                            .foregroundStyle(UniteTheme.muted)
                    }
                    Spacer()
                    if store.priceAlert(for: asset) != nil {
                        Button("Remove") {
                            store.removePriceAlert(for: asset)
                            alertSaved = false
                        }
                        .roundedFont(13, weight: .bold)
                        .foregroundStyle(UniteTheme.red)
                    }
                }

                HStack(spacing: 10) {
                    TextField("Target price", text: $alertPrice)
                        .keyboardType(.decimalPad)
                        .roundedFont(15, weight: .semibold)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        guard let target = Double(alertPrice.replacingOccurrences(of: "$", with: "")), target > 0 else { return }
                        store.setPriceAlert(asset: asset, targetPrice: target)
                        alertPrice = ""
                        alertSaved = true
                    } label: {
                        Image(systemName: alertSaved ? "checkmark" : "bell")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 50, height: 48)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .uniteCard(cornerRadius: 20)

            HStack(spacing: 12) {
                Button {
                    showingBuy = true
                } label: {
                    Label("Buy", systemImage: "plus")
                        .roundedFont(15, weight: .black)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    store.toggleMarketWatch(asset)
                } label: {
                    Label(store.isWatchingMarketAsset(asset) ? "Watching" : "Watch", systemImage: store.isWatchingMarketAsset(asset) ? "star.fill" : "star")
                        .roundedFont(15, weight: .black)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(22)
        .background(UniteTheme.ink)
        .sheet(isPresented: $showingBuy) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Buy \(asset.symbol)")
                    .roundedFont(32, weight: .black)
                Text("Quotes require a connected ramp provider. Fees and limits will be shown before checkout.")
                    .roundedFont(15, weight: .bold)
                    .foregroundStyle(UniteTheme.soft)
                StatTile(title: "Indicative price", value: usd(asset.price))
                StatTile(title: "Network", value: asset.name)
                Button {} label: {
                    Text("Get quote")
                        .roundedFont(16, weight: .black)
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
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var chartPoints: [Double] {
        guard !asset.sparkline.isEmpty else { return asset.sparkline }
        switch selectedRange {
        case .hour:
            return Array(asset.sparkline.suffix(3))
        case .day:
            return Array(asset.sparkline.suffix(24))
        case .week:
            return asset.sparkline
        }
    }

    private var selectedRangeChange: Double {
        switch selectedRange {
        case .hour:
            return asset.change1h ?? asset.change24h ?? 0
        case .day:
            return asset.change24h ?? 0
        case .week:
            return asset.change7d ?? asset.change24h ?? 0
        }
    }

    private var existingAlertText: String {
        guard let alert = store.priceAlert(for: asset) else {
            return "Get notified when \(asset.symbol) crosses your target."
        }
        return "Target set at \(usd(alert.targetPrice))."
    }
}

private enum MarketFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case watchlist = "Watchlist"
    case gainers = "Gainers"
    case losers = "Losers"

    var id: String { rawValue }
}

private enum MarketSort: String, CaseIterable, Identifiable {
    case rank = "Rank"
    case price = "Price"
    case change = "24h"
    case volume = "Volume"

    var id: String { rawValue }
}

private enum MarketRange: String, CaseIterable, Identifiable {
    case hour = "1H"
    case day = "24H"
    case week = "7D"

    var id: String { rawValue }
}

private struct MarketSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(UniteTheme.muted)
            TextField("Search tokens", text: $text)
                .roundedFont(15, weight: .semibold)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(UniteTheme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 52)
        .background(UniteTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(UniteTheme.line, lineWidth: 1)
        )
    }
}

struct TokenIcon: View {
    let asset: MarketAsset
    let size: CGFloat

    var body: some View {
        AsyncImage(url: asset.imageURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Text(String(asset.symbol.prefix(1)))
                .roundedFont(size * 0.36, weight: .black)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(color(for: asset.colorName))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func color(for name: String) -> Color {
        switch name {
        case "blue": UniteTheme.blue
        case "violet": UniteTheme.violet
        case "yellow": UniteTheme.yellow
        default: .white
        }
    }
}

struct Sparkline: View {
    let points: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard points.count > 1 else { return }
                let minValue = points.min() ?? 0
                let maxValue = points.max() ?? 1
                let range = max(maxValue - minValue, 0.000001)

                for index in points.indices {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(points.count - 1)
                    let y = proxy.size.height - (proxy.size.height * CGFloat((points[index] - minValue) / range))
                    if index == points.startIndex {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .roundedFont(12, weight: .bold)
                .foregroundStyle(UniteTheme.muted)
            Text(value)
                .roundedFont(16, weight: .black)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
