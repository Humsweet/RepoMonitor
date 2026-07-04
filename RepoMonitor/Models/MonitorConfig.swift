import Foundation

// MARK: - Root Config

struct MonitorConfig: Codable {
    var roots: [RootEntry]
    var unwatchedPaths: [String]
    var git: GitConfig
    var notifications: NotificationConfig
    var desktop: DesktopConfig
    var state: StateConfig
    var logging: LoggingConfig

    static let defaultConfig = MonitorConfig(
        roots: [],
        unwatchedPaths: [],
        git: GitConfig(),
        notifications: NotificationConfig(),
        desktop: DesktopConfig(),
        state: StateConfig(),
        logging: LoggingConfig()
    )

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roots = try container.decodeIfPresent([RootEntry].self, forKey: .roots) ?? []
        unwatchedPaths = try container.decodeIfPresent([String].self, forKey: .unwatchedPaths) ?? []
        git = try container.decodeIfPresent(GitConfig.self, forKey: .git) ?? GitConfig()
        notifications = try container.decodeIfPresent(NotificationConfig.self, forKey: .notifications) ?? NotificationConfig()
        desktop = try container.decodeIfPresent(DesktopConfig.self, forKey: .desktop) ?? DesktopConfig()
        state = try container.decodeIfPresent(StateConfig.self, forKey: .state) ?? StateConfig()
        logging = try container.decodeIfPresent(LoggingConfig.self, forKey: .logging) ?? LoggingConfig()
    }

    init(roots: [RootEntry], unwatchedPaths: [String] = [], git: GitConfig, notifications: NotificationConfig, desktop: DesktopConfig, state: StateConfig, logging: LoggingConfig) {
        self.roots = roots
        self.unwatchedPaths = unwatchedPaths
        self.git = git
        self.notifications = notifications
        self.desktop = desktop
        self.state = state
        self.logging = logging
    }
}

// MARK: - Sub Configs

struct RootEntry: Codable, Identifiable {
    var id: String { path }
    var path: String
    var mode: ScanMode

    enum ScanMode: String, Codable {
        case `self`
        case children
    }
}

struct GitConfig: Codable {
    var autoPullEnabled: Bool = false
    /// When on, dirty repos (or repos with unpushed commits) that are not behind
    /// remote are committed with an AI-generated English message and pushed
    /// automatically after each scan. Skips repos behind remote and aborts if the
    /// staged changes trip the sensitive-content guard. Defaults off — push is a
    /// manual, per-repo action unless the user opts in.
    var autoPushEnabled: Bool = false
    /// When on, a pull that advances RepoMonitor's own source with build-affecting
    /// changes rebuilds and relaunches the app automatically. Only ever acts on
    /// RepoMonitor itself. Defaults on; an escape hatch for users who want manual
    /// control over restarts.
    var selfUpdateEnabled: Bool = true
    var hostCredentials: [GitHostCredential] = []
    /// Canonical ids ("host/owner/name") of remote repos the user chose not to
    /// clone. Stored so the new-repo review never asks about them again.
    var ignoredRemoteRepos: [String] = []

    init(
        autoPullEnabled: Bool = false,
        autoPushEnabled: Bool = false,
        selfUpdateEnabled: Bool = true,
        hostCredentials: [GitHostCredential] = [],
        ignoredRemoteRepos: [String] = []
    ) {
        self.autoPullEnabled = autoPullEnabled
        self.autoPushEnabled = autoPushEnabled
        self.selfUpdateEnabled = selfUpdateEnabled
        self.hostCredentials = hostCredentials
        self.ignoredRemoteRepos = ignoredRemoteRepos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoPullEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoPullEnabled) ?? false
        autoPushEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoPushEnabled) ?? false
        selfUpdateEnabled = try container.decodeIfPresent(Bool.self, forKey: .selfUpdateEnabled) ?? true
        hostCredentials = try container.decodeIfPresent([GitHostCredential].self, forKey: .hostCredentials) ?? []
        ignoredRemoteRepos = try container.decodeIfPresent([String].self, forKey: .ignoredRemoteRepos) ?? []
    }
}

struct GitHostCredential: Codable, Identifiable, Equatable {
    var host: String
    var username: String

    var id: String { normalizedHost }
    var normalizedHost: String { Self.normalizeHost(host) }

    init(host: String, username: String) {
        self.host = Self.normalizeHost(host)
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct NotificationConfig: Codable {
    var enabled: Bool = true
    var mode: NotifyMode = .behindAndDirty
    var minimumIntervalMinutes: Int = 30

    enum NotifyMode: String, Codable, CaseIterable {
        case errors
        case behind
        case behindAndDirty
    }
}

struct DesktopConfig: Codable {
    var scanIntervalMinutes: Int = 10
    /// Bundle id of the user's chosen terminal emulator (see `TerminalCatalog`).
    /// Empty means "not yet chosen" — the first terminal launch prompts for one.
    var terminalAppID: String = ""

    enum CodingKeys: String, CodingKey {
        case scanIntervalMinutes
        case terminalAppID
        case terminalApp // legacy key: stored the old enum case ("ghostty"/"iterm")
    }

    init(scanIntervalMinutes: Int = 10, terminalAppID: String = "") {
        self.scanIntervalMinutes = scanIntervalMinutes
        self.terminalAppID = terminalAppID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scanIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .scanIntervalMinutes) ?? 10
        if let id = try container.decodeIfPresent(String.self, forKey: .terminalAppID) {
            terminalAppID = id
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .terminalApp) {
            // Migrate the old fixed enum into the new bundle-id form.
            terminalAppID = TerminalCatalog.legacyBundleID(for: legacy) ?? ""
        } else {
            terminalAppID = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scanIntervalMinutes, forKey: .scanIntervalMinutes)
        try container.encode(terminalAppID, forKey: .terminalAppID)
    }
}

struct StateConfig: Codable {
    var filePath: String = "state.json"
}

struct LoggingConfig: Codable {
    var filePath: String = "repo-monitor-runtime.log"
}
