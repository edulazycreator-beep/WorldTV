import SwiftUI

/// World TV design tokens: a near-black, charcoal palette with a cool
/// cyan-to-violet signature gradient.
enum Theme {
    static let background = Color(red: 0.035, green: 0.039, blue: 0.047)
    static let surface = Color(red: 0.086, green: 0.090, blue: 0.106)
    static let surfaceRaised = Color(red: 0.122, green: 0.129, blue: 0.149)
    static let stroke = Color.white.opacity(0.07)
    static let logoBackground = Color(red: 0.16, green: 0.17, blue: 0.20)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let accent = Color(red: 0.208, green: 0.784, blue: 0.976)
    static let accentSecondary = Color(red: 0.545, green: 0.420, blue: 0.996)
    static let live = Color(red: 1.0, green: 0.27, blue: 0.33)

    static let brandGradient = LinearGradient(colors: [accent, accentSecondary],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)

    static let backdrop = LinearGradient(
        colors: [Color(red: 0.07, green: 0.08, blue: 0.11), background],
        startPoint: .top, endPoint: .center)

    static let cardRadius: CGFloat = 14
    static let gridSpacing: CGFloat = 18

    /// Deterministic per-channel tint used behind logos on hero cards.
    static func tint(for key: String) -> Color {
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let hue = Double(hash % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.45)
    }
}

struct CardBackground: ViewModifier {
    var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(isHovered ? Theme.surfaceRaised : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(isHovered ? Theme.accent.opacity(0.45) : Theme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(isHovered ? 0.45 : 0.2), radius: isHovered ? 16 : 6, y: isHovered ? 8 : 3)
    }
}

extension View {
    func card(hovered: Bool = false) -> some View { modifier(CardBackground(isHovered: hovered)) }
}

/// Small rounded label, e.g. "HD", "LIVE", "Geo-blocked".
struct Pill: View {
    let text: String
    var color: Color = .white.opacity(0.12)
    var foreground: Color = .primary

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
            .foregroundStyle(foreground)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.bold))
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
            }
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.brandGradient)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
