import AppKit

/// A terminal emulator the app knows how to open at a specific directory.
struct TerminalApp: Identifiable, Equatable {
    let id: String   // bundle identifier
    let name: String
    let launch: LaunchStrategy

    static func == (lhs: TerminalApp, rhs: TerminalApp) -> Bool { lhs.id == rhs.id }

    /// How to open a brand-new window already changed into a directory. Each
    /// terminal exposes a different mechanism, so the strategy is per-app.
    enum LaunchStrategy {
        /// `open -a <appName> <dir>` — the app opens a new window at the path.
        case openDir(appName: String)
        case wezterm(appName: String)
        case kitty(appName: String)
        case alacritty(appName: String)
        case iterm
    }

    /// Opens a new window of this terminal at `path`. Returns whether the
    /// launch command was dispatched successfully.
    @discardableResult
    func open(at path: String) -> Bool {
        switch launch {
        case .openDir(let appName):
            return Self.runOpen(["-a", appName, path])
        case .wezterm(let appName):
            return Self.runOpen(["-na", appName, "--args", "start", "--cwd", path])
        case .kitty(let appName):
            return Self.runOpen(["-na", appName, "--args", "--directory", path])
        case .alacritty(let appName):
            return Self.runOpen(["-na", appName, "--args", "--working-directory", path])
        case .iterm:
            return Self.runAppleScript("""
            tell application "iTerm"
                activate
                create window with default profile
                tell current session of current window to write text "cd '\(path)'"
            end tell
            """)
        }
    }

    private static func runOpen(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        return (try? process.run()) != nil
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> Bool {
        guard let appleScript = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        return error == nil
    }
}

/// Detects which known terminal emulators are installed and resolves the
/// user's chosen one. Replaces the old fixed Ghostty/iTerm enum.
enum TerminalCatalog {
    /// All terminals the app can drive, in a sensible preference order. macOS
    /// Terminal.app is always present, so it guarantees a non-empty install set.
    static let known: [TerminalApp] = [
        TerminalApp(id: "com.mitchellh.ghostty", name: "Ghostty", launch: .openDir(appName: "Ghostty")),
        TerminalApp(id: "com.googlecode.iterm2", name: "iTerm", launch: .iterm),
        TerminalApp(id: "dev.warp.Warp-Stable", name: "Warp", launch: .openDir(appName: "Warp")),
        TerminalApp(id: "com.github.wez.wezterm", name: "WezTerm", launch: .wezterm(appName: "WezTerm")),
        TerminalApp(id: "net.kovidgoyal.kitty", name: "kitty", launch: .kitty(appName: "kitty")),
        TerminalApp(id: "org.alacritty", name: "Alacritty", launch: .alacritty(appName: "Alacritty")),
        TerminalApp(id: "co.zeit.hyper", name: "Hyper", launch: .openDir(appName: "Hyper")),
        TerminalApp(id: "com.apple.Terminal", name: "Terminal", launch: .openDir(appName: "Terminal")),
    ]

    /// Known terminals that are actually installed on this machine.
    static func installed() -> [TerminalApp] {
        known.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }

    static func isInstalled(_ id: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    static func app(for id: String) -> TerminalApp? {
        known.first { $0.id == id }
    }

    /// Maps the old config enum cases to the new bundle ids for migration.
    static func legacyBundleID(for legacy: String) -> String? {
        switch legacy {
        case "ghostty": return "com.mitchellh.ghostty"
        case "iterm": return "com.googlecode.iterm2"
        default: return nil
        }
    }
}
