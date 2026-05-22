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

func usd(_ value: Double?) -> String {
    guard let value else { return "--" }
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.maximumFractionDigits = value >= 1000 ? 0 : 2
    formatter.minimumFractionDigits = value >= 1000 ? 0 : 2
    return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
}
