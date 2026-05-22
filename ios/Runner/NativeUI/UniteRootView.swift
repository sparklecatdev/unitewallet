import SwiftUI

enum UniteTab: String, CaseIterable, Identifiable {
    case wallet = "Home"
    case market = "Markets"
    case profile = "Profile"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .wallet: "house"
        case .market: "chart.line.uptrend.xyaxis"
        case .profile: "person.crop.circle"
        }
    }
}

struct UniteRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = WalletStore()
    @State private var tab: UniteTab = .wallet

    var body: some View {
        ZStack(alignment: .bottom) {
            UniteTheme.ink.ignoresSafeArea()

            Group {
                if !store.hasWallet {
                    OnboardingView()
                } else if !store.backupConfirmed {
                    BackupView()
                } else if store.isAppLocked {
                    LockedWalletView()
                } else {
                    appContent
                }
            }
            .environmentObject(store)
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active {
                store.lockApp()
            }
        }
    }

    private var appContent: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                WalletView().tag(UniteTab.wallet)
                MarketView().tag(UniteTab.market)
                ProfileView().tag(UniteTab.profile)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.keyboard)
            .ignoresSafeArea(.container, edges: .bottom)

            UniteTabBar(selection: $tab)
        }
    }
}

struct UniteTabBar: View {
    @Binding var selection: UniteTab

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(UniteTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 19, weight: .black))
                        Text(tab.rawValue)
                            .roundedFont(11, weight: .black)
                    }
                    .foregroundStyle(selection == tab ? .white : UniteTheme.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        Capsule()
                            .fill(selection == tab ? UniteTheme.raised : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tab.rawValue) tab")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(UniteTheme.line, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

private struct LockedWalletView: View {
    @EnvironmentObject private var store: WalletStore
    @State private var isUnlocking = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 44, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(spacing: 8) {
                Text("Wallet locked")
                    .roundedFont(32, weight: .black)
                Text("Unite requires device authentication before showing wallet details or recovery material.")
                    .roundedFont(15, weight: .semibold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(UniteTheme.soft)
            }

            if let message = store.unlockErrorMessage {
                Text(message)
                    .roundedFont(13, weight: .bold)
                    .foregroundStyle(UniteTheme.yellow)
                    .multilineTextAlignment(.center)
            }

            Button {
                isUnlocking = true
                Task {
                    _ = await store.unlockApp()
                    isUnlocking = false
                }
            } label: {
                Text(isUnlocking ? "Unlocking..." : "Unlock wallet")
                    .roundedFont(16, weight: .black)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isUnlocking)

            Spacer()
        }
        .padding(24)
        .background(UniteTheme.ink)
    }
}
