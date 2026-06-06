import SwiftUI

// MARK: - Warm-dark "terminal" palette
//
// Neutral charcoal surfaces with a single red accent and earthy text.
// Status is intentionally collapsed to three signals — clean / attention /
// error — so a glance down the table reads cleanly.

enum Theme {
    // Backgrounds
    static let bg = Color(hex: 0x141414)          // window + table body
    static let bgSecondary = Color(hex: 0x1C1C1C) // header row, controls
    static let bgTertiary = Color(hex: 0x242424)  // raised surfaces
    static let bgCard = Color(hex: 0x1C1C1C)       // inputs, cards
    static let bgHover = Color(hex: 0x242424)      // row / control hover

    // Text
    static let textPrimary = Color(hex: 0xE8E6E3)
    static let textSecondary = Color(hex: 0x7A7672)
    static let textTertiary = Color(hex: 0x4A4845)

    // Accent
    static let accent = Color(hex: 0xC0392B)
    static let accentHover = Color(hex: 0xD95F50)
    static let accentSoft = Color(hex: 0xC0392B, opacity: 0.15)

    // Status colors — clean / attention / error
    static let statusClean = Color(hex: 0x7DAA6E)
    static let statusDirty = Color(hex: 0xC9963A)
    static let statusBehind = Color(hex: 0xC9963A)
    static let statusError = Color(hex: 0xD95F50)

    // Sync arrows
    static let syncAhead = Color(hex: 0xC9963A)
    static let syncBehind = Color(hex: 0xD95F50)

    // Border
    static let border = Color.white.opacity(0.07)
    static let borderFocused = Color.white.opacity(0.12)

    static func statusColor(for level: StatusLevel) -> Color {
        switch level {
        case .clean: return statusClean
        case .dirty: return statusDirty
        case .behind: return statusBehind
        case .error: return statusError
        }
    }

    // MARK: - Tag (group) colors
    //
    // A small, deliberately desaturated palette. Each distinct group folder
    // gets a stable tint via a hash, so badges are distinguishable without
    // turning into a rainbow.
    static let groupPalette: [Color] = [
        Color(hex: 0x8A8580), // warm gray
        Color(hex: 0x9A7B5A), // tan
        Color(hex: 0x6E8A7D), // sage
        Color(hex: 0xA06A6A), // dusty rose
        Color(hex: 0x7D7A9A), // muted periwinkle
        Color(hex: 0x9A8F5A)  // olive gold
    ]

    static func groupColor(for tag: String) -> Color {
        guard !groupPalette.isEmpty else { return textSecondary }
        var hash: UInt64 = 5381
        for byte in tag.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return groupPalette[Int(hash % UInt64(groupPalette.count))]
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
            .background(Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.borderFocused, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
