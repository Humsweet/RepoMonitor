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
    var fetchBeforeCompare: Bool = true
    var fetchTimeoutSeconds: Int = 30
    var hostCredentials: [GitHostCredential] = []

    init(
        fetchBeforeCompare: Bool = true,
        fetchTimeoutSeconds: Int = 30,
        hostCredentials: [GitHostCredential] = []
    ) {
        self.fetchBeforeCompare = fetchBeforeCompare
        self.fetchTimeoutSeconds = fetchTimeoutSeconds
        self.hostCredentials = hostCredentials
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fetchBeforeCompare = try container.decodeIfPresent(Bool.self, forKey: .fetchBeforeCompare) ?? true
        fetchTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .fetchTimeoutSeconds) ?? 30
        hostCredentials = try container.decodeIfPresent([GitHostCredential].self, forKey: .hostCredentials) ?? []
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
}

struct StateConfig: Codable {
    var filePath: String = "state.json"
}

struct LoggingConfig: Codable {
    var filePath: String = "repo-monitor-runtime.log"
}
