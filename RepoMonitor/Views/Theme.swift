import SwiftUI

// MARK: - Linear-inspired color palette

enum Theme {
    // Backgrounds
    static let bg = Color(hex: 0x1A1A2E)
    static let bgSecondary = Color(hex: 0x16213E)
    static let bgTertiary = Color(hex: 0x0F3460)
    static let bgCard = Color(hex: 0x1E1E3A)
    static let bgHover = Color.white.opacity(0.05)

    // Text
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)

    // Accent
    static let accent = Color(hex: 0x5B6EF5)
    static let accentHover = Color(hex: 0x7B8AF7)

    // Status colors
    static let statusClean = Color(hex: 0x4ADE80)
    static let statusDirty = Color(hex: 0xFBBF24)
    static let statusBehind = Color(hex: 0xF97316)
    static let statusError = Color(hex: 0xEF4444)

    // Border
    static let border = Color.white.opacity(0.08)
    static let borderFocused = Color.white.opacity(0.15)

    static func statusColor(for level: StatusLevel) -> Color {
        switch level {
        case .clean: return statusClean
        case .dirty: return statusDirty
        case .behind: return statusBehind
        case .error: return statusError
        }
    }

    // Corner radius
    static let cornerRadius: CGFloat = 8
    static let cornerRadiusLarge: CGFloat = 12
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
