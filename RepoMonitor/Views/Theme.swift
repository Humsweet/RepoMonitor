import SwiftUI
import AppKit

// MARK: - Theme mode (light / dark / follow system)

/// The user-facing appearance choice. `system` defers to macOS; `light` and
/// `dark` force a fixed appearance for the whole app.
enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The AppKit appearance to force, or `nil` to follow the system.
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// The SwiftUI environment scheme, mirroring `appearance`, so views resolve
    /// dynamic colors deterministically alongside the global `NSApp.appearance`.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Single source of truth for the active appearance. Persists the choice and is
/// applied globally via `NSApp.appearance` so every window, popover, and system
/// control flips from one switch.
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let storageKey = "RepoMonitor.themeMode"

    @Published var mode: ThemeMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey)
            apply()
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey)
        mode = raw.flatMap(ThemeMode.init(rawValue:)) ?? .system
    }

    /// Push the current mode onto AppKit. Safe to call only once `NSApp` exists
    /// (i.e. from `applicationDidFinishLaunching` onward).
    func apply() {
        NSApp.appearance = mode.appearance
    }
}

// MARK: - Warm "terminal" palette (light + dark)
//
// Two appearances share one identity: neutral surfaces, a single red accent,
// and earthy text, with status collapsed to three signals — clean / attention /
// error — so a glance down the table reads cleanly. The dark side is the
// original warm-charcoal terminal look; the light side is a warm "paper" tone
// (ivory surfaces, espresso text) tuned for readability on bright screens.

enum Theme {
    // Backgrounds                       light       dark
    static let bg          = Color.themed(0xF7F3EC, 0x141414) // window + table body
    static let bgSecondary = Color.themed(0xEFEAE0, 0x1C1C1C) // header row, controls
    static let bgTertiary  = Color.themed(0xE7E1D4, 0x242424) // raised surfaces
    static let bgCard      = Color.themed(0xFFFDF9, 0x1C1C1C) // inputs, cards
    static let bgHover     = Color.themed(0xEBE4D6, 0x242424) // row / control hover

    // Text
    static let textPrimary   = Color.themed(0x2B2723, 0xE8E6E3)
    static let textSecondary = Color.themed(0x6E6760, 0x7A7672)
    static let textTertiary  = Color.themed(0x968D80, 0x4A4845)

    // Accent (single red — shared identity across both modes)
    static let accent      = Color.themed(0xC0392B, 0xC0392B)
    static let accentHover = Color.themed(0x9E2E22, 0xD95F50)
    static let accentSoft  = Color.themed(0xC0392B, 0xC0392B, lightOpacity: 0.12, darkOpacity: 0.15)

    // Status colors — clean / attention / error (deepened on light for contrast)
    static let statusClean  = Color.themed(0x3F7A35, 0x7DAA6E)
    static let statusDirty  = Color.themed(0x9A6B16, 0xC9963A)
    static let statusBehind = Color.themed(0x9A6B16, 0xC9963A)
    static let statusError  = Color.themed(0xBE3B2C, 0xD95F50)

    // Sync arrows
    static let syncAhead  = Color.themed(0x9A6B16, 0xC9963A)
    static let syncBehind = Color.themed(0xBE3B2C, 0xD95F50)

    // Border (black-based on light, white-based on dark)
    static let border        = Color.themed(0x000000, 0xFFFFFF, lightOpacity: 0.10, darkOpacity: 0.07)
    static let borderFocused = Color.themed(0x000000, 0xFFFFFF, lightOpacity: 0.16, darkOpacity: 0.12)

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
    // turning into a rainbow. Light tints are deepened so colored text stays
    // legible on the ivory surface.
    static let groupPalette: [Color] = [
        Color.themed(0x6B655D, 0x8A8580), // warm gray
        Color.themed(0x8A6536, 0x9A7B5A), // tan
        Color.themed(0x43705B, 0x6E8A7D), // sage
        Color.themed(0x8F4B4B, 0xA06A6A), // dusty rose
        Color.themed(0x565380, 0x7D7A9A), // muted periwinkle
        Color.themed(0x756A2C, 0x9A8F5A)  // olive gold
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

// MARK: - Color helpers

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

    /// A color that resolves to `light` or `dark` against the current
    /// appearance. Backed by a dynamic `NSColor` so it re-resolves whenever the
    /// effective appearance changes (system flip or a forced `ThemeMode`).
    static func themed(
        _ light: UInt,
        _ dark: UInt,
        lightOpacity: Double = 1.0,
        darkOpacity: Double = 1.0
    ) -> Color {
        let dynamic = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, opacity: isDark ? darkOpacity : lightOpacity)
        }
        return Color(nsColor: dynamic)
    }
}

extension NSColor {
    convenience init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: CGFloat(opacity)
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
