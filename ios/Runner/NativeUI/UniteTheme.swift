import SwiftUI

enum UniteTheme {
    static let ink = Color.black
    static let panel = Color(red: 0.025, green: 0.025, blue: 0.025)
    static let raised = Color(red: 0.075, green: 0.075, blue: 0.075)
    static let line = Color.white.opacity(0.12)
    static let muted = Color.white.opacity(0.48)
    static let soft = Color.white.opacity(0.72)
    static let mint = Color(red: 0.45, green: 0.94, blue: 0.78)
    static let green = Color(red: 0.25, green: 0.85, blue: 0.55)
    static let red = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let yellow = Color(red: 1.0, green: 0.78, blue: 0.34)
    static let blue = Color(red: 0.38, green: 0.68, blue: 1.0)
    static let violet = Color(red: 0.62, green: 0.54, blue: 1.0)
    static let primaryAction = Color.white
    static let primaryActionText = Color.black
    static let caution = yellow
    static let success = mint
    static let secondaryText = muted
    static let cardEmphasis = Color.white.opacity(0.06)
}

extension View {
    func uniteCard(cornerRadius: CGFloat = 24) -> some View {
        padding(18)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(UniteTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(UniteTheme.line, lineWidth: 1)
                    )
            )
    }

    func uniteField() -> some View {
        background(UniteTheme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(UniteTheme.line, lineWidth: 1)
            )
    }

    func roundedFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        font(.system(size: size, weight: weight.sleekWeight, design: .default))
    }
}

private extension Font.Weight {
    var sleekWeight: Font.Weight {
        if self == .black || self == .heavy {
            return .bold
        }
        if self == .bold {
            return .semibold
        }
        return self
    }
}

struct UniteButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading = false
    var isEnabled = true
    var tone: Tone = .primary
    let action: () -> Void

    enum Tone {
        case primary
        case secondary
        case caution
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
            }
            .roundedFont(16, weight: .bold)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor, lineWidth: tone == .primary ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity((!isEnabled || isLoading) ? 0.72 : 1)
    }

    private var backgroundColor: Color {
        switch tone {
        case .primary:
            return UniteTheme.primaryAction
        case .secondary:
            return UniteTheme.raised
        case .caution:
            return UniteTheme.red.opacity(0.16)
        }
    }

    private var foregroundColor: Color {
        switch tone {
        case .primary:
            return UniteTheme.primaryActionText
        case .secondary:
            return .white
        case .caution:
            return UniteTheme.red
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary:
            return .clear
        case .secondary:
            return UniteTheme.line
        case .caution:
            return UniteTheme.red.opacity(0.3)
        }
    }
}

struct UniteBanner: View {
    let title: String
    let detail: String
    var tone: Tone = .neutral
    var icon: String = "info.circle"

    enum Tone {
        case neutral
        case success
        case caution
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .roundedFont(15, weight: .black)
                Text(detail)
                    .roundedFont(13, weight: .medium)
                    .foregroundStyle(UniteTheme.soft)
            }
            Spacer()
        }
        .padding(16)
        .background(background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }

    private var tint: Color {
        switch tone {
        case .neutral:
            return UniteTheme.blue
        case .success:
            return UniteTheme.success
        case .caution:
            return UniteTheme.caution
        }
    }

    private var background: Color {
        switch tone {
        case .neutral:
            return UniteTheme.cardEmphasis
        case .success:
            return UniteTheme.success.opacity(0.08)
        case .caution:
            return UniteTheme.caution.opacity(0.08)
        }
    }
}

struct UniteSectionHeader: View {
    let eyebrow: String?
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .roundedFont(11, weight: .black)
                    .foregroundStyle(UniteTheme.muted)
                    .tracking(1.2)
            }
            Text(title)
                .roundedFont(30, weight: .black)
            if let detail {
                Text(detail)
                    .roundedFont(14, weight: .medium)
                    .foregroundStyle(UniteTheme.soft)
            }
        }
    }
}

func usd(_ value: Double?) -> String {
    guard let value else { return "--" }
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.maximumFractionDigits = value >= 1000 ? 0 : 2
    formatter.minimumFractionDigits = value >= 1000 ? 0 : 2
    return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
}
