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
    @State private var setupCode = ""
    @State private var confirmCode = ""
    @State private var setupMessage: String?
    @State private var lockCode = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            UniteTheme.ink.ignoresSafeArea()

            Group {
                if !store.hasWallet {
                    OnboardingView()
                } else if !store.backupConfirmed {
                    BackupView()
                } else if !store.passcodeConfigured {
                    PasscodeSetupView(
                        setupCode: $setupCode,
                        confirmCode: $confirmCode,
                        message: setupMessage,
                        onSave: configurePasscode
                    )
                } else if store.isAppLocked {
                    LockedWalletView(
                        code: $lockCode,
                        onSubmit: unlockWithPasscode
                    )
                } else {
                    appContent
                }
            }
            .environmentObject(store)
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active {
                store.lockApp(reason: .background)
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
    @Binding var code: String
    let onSubmit: () -> Void
    @State private var isUnlockingFaceID = false

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
                Text("Enter your 6-digit Unite code. Face ID can unlock this wallet when it is enabled on the device.")
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

            PasscodeDotsView(code: code)

            NumericPad(code: $code) {
                onSubmit()
            }

            if store.faceIDEnabled {
                Button {
                    isUnlockingFaceID = true
                    Task {
                        _ = await store.unlockWithFaceID()
                        isUnlockingFaceID = false
                    }
                } label: {
                    Label(isUnlockingFaceID ? "Checking Face ID..." : "Unlock with Face ID", systemImage: "faceid")
                        .roundedFont(16, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(24)
        .background(UniteTheme.ink)
    }
}

private struct PasscodeSetupView: View {
    @Binding var setupCode: String
    @Binding var confirmCode: String
    let message: String?
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "number.circle")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

            UniteSectionHeader(
                eyebrow: "Security",
                title: "Create your Unite code",
                detail: "Choose a 6-digit app code. This unlocks the wallet on this device, and the same code protects your encrypted iCloud backup."
            )
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                Text("New 6-digit code")
                    .roundedFont(13, weight: .black)
                    .foregroundStyle(UniteTheme.muted)
                PasscodeDotsView(code: setupCode)
                NumericPad(code: $setupCode, maximumLength: 6) {}

                Text("Confirm code")
                    .roundedFont(13, weight: .black)
                    .foregroundStyle(UniteTheme.muted)
                PasscodeDotsView(code: confirmCode)
                NumericPad(code: $confirmCode, maximumLength: 6) {}
            }
            .padding(18)
            .background(UniteTheme.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            if let message {
                UniteBanner(
                    title: "Passcode needs a second look",
                    detail: message,
                    tone: .caution,
                    icon: "exclamationmark.triangle"
                )
            }

            UniteButton(title: "Save app code", systemImage: "checkmark") {
                onSave()
            }

            Spacer()
        }
        .padding(24)
        .background(UniteTheme.ink)
    }
}

private struct PasscodeDotsView: View {
    let code: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(index < code.count ? .white : UniteTheme.raised)
                    .overlay(Circle().stroke(UniteTheme.line, lineWidth: 1))
                    .frame(width: 16, height: 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

private struct NumericPad: View {
    @Binding var code: String
    var maximumLength = 6
    let onSubmit: () -> Void

    private let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "delete.left"]
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { item in
                        Button {
                            handle(item)
                        } label: {
                            Group {
                                if item == "delete.left" {
                                    Image(systemName: item)
                                        .font(.system(size: 20, weight: .bold))
                                } else if item.isEmpty {
                                    Color.clear
                                } else {
                                    Text(item)
                                        .roundedFont(22, weight: .black)
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(item.isEmpty ? Color.clear : UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(item.isEmpty)
                    }
                }
            }
        }
    }

    private func handle(_ item: String) {
        switch item {
        case "delete.left":
            guard !code.isEmpty else { return }
            code.removeLast()
        default:
            guard code.count < maximumLength else { return }
            code.append(item)
            if code.count == maximumLength {
                onSubmit()
            }
        }
    }
}

private extension UniteRootView {
    func configurePasscode() {
        guard setupCode == confirmCode else {
            setupMessage = "The two codes did not match."
            return
        }

        setupMessage = store.setPasscode(setupCode)
        guard setupMessage == nil else { return }

        setupCode = ""
        confirmCode = ""
        lockCode = ""
        store.lockApp(reason: .securityAction)
    }

    func unlockWithPasscode() {
        guard store.verifyPasscode(lockCode) else {
            lockCode = ""
            return
        }
        lockCode = ""
    }
}
