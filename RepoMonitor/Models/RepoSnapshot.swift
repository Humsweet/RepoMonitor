import Foundation

// MARK: - Repo Snapshot

struct RepoSnapshot: Identifiable, Codable, Equatable {
    var id: String { path }
    let name: String
    let path: String
    var branch: String = ""
    var upstream: String = ""
    var remoteUrl: String = ""
    var ahead: Int = 0
    var behind: Int = 0
    var isDirty: Bool = false
    var fetchSuccess: Bool = true
    var fetchError: String = ""
    var isSkipped: Bool = false
    var lastScanned: Date = .now

    init(
        name: String,
        path: String,
        branch: String = "",
        upstream: String = "",
        remoteUrl: String = "",
        ahead: Int = 0,
        behind: Int = 0,
        isDirty: Bool = false,
        fetchSuccess: Bool = true,
        fetchError: String = "",
        isSkipped: Bool = false,
        lastScanned: Date = .now
    ) {
        self.name = name
        self.path = path
        self.branch = branch
        self.upstream = upstream
        self.remoteUrl = remoteUrl
        self.ahead = ahead
        self.behind = behind
        self.isDirty = isDirty
        self.fetchSuccess = fetchSuccess
        self.fetchError = fetchError
        self.isSkipped = isSkipped
        self.lastScanned = lastScanned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        branch = try container.decodeIfPresent(String.self, forKey: .branch) ?? ""
        upstream = try container.decodeIfPresent(String.self, forKey: .upstream) ?? ""
        remoteUrl = try container.decodeIfPresent(String.self, forKey: .remoteUrl) ?? ""
        ahead = try container.decodeIfPresent(Int.self, forKey: .ahead) ?? 0
        behind = try container.decodeIfPresent(Int.self, forKey: .behind) ?? 0
        isDirty = try container.decodeIfPresent(Bool.self, forKey: .isDirty) ?? false
        fetchSuccess = try container.decodeIfPresent(Bool.self, forKey: .fetchSuccess) ?? true
        fetchError = try container.decodeIfPresent(String.self, forKey: .fetchError) ?? ""
        isSkipped = try container.decodeIfPresent(Bool.self, forKey: .isSkipped) ?? false
        lastScanned = try container.decodeIfPresent(Date.self, forKey: .lastScanned) ?? .now
    }

    var isBehind: Bool { behind > 0 }
    var isAhead: Bool { ahead > 0 }
    var hasWarning: Bool { !fetchSuccess }
    var remoteDisplay: String { remoteUrl.isEmpty ? "—" : remoteUrl }
    var scannedDisplay: String { lastScanned.formatted(.dateTime.month().day().hour().minute()) }
    var dirtyDisplay: String { isDirty ? "Yes" : "No" }
    var skippedDisplay: String { isSkipped ? "Yes" : "No" }
    var statusRank: Int {
        if !fetchSuccess { return 4 }
        if behind > 0 { return 3 }
        if isDirty { return 2 }
        if isSkipped { return 1 }
        return 0
    }

    var statusSummary: String {
        var parts: [String] = []
        if isSkipped { parts.append("skip") }
        if behind > 0 { parts.append("↓\(behind)") }
        if ahead > 0 { parts.append("↑\(ahead)") }
        if isDirty { parts.append("●") }
        if !fetchSuccess { parts.append("⚠") }
        return parts.isEmpty ? "✓" : parts.joined(separator: " ")
    }

    var statusLevel: StatusLevel {
        if !fetchSuccess { return .error }
        if behind > 0 { return .behind }
        if isDirty { return .dirty }
        return .clean
    }
}

enum StatusLevel: Int, Comparable, Codable {
    case clean = 0
    case dirty = 1
    case behind = 2
    case error = 3

    static func < (lhs: StatusLevel, rhs: StatusLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Scan Result

struct ScanResult {
    let repos: [RepoSnapshot]
    let notifications: [MonitorNotification]
    let scannedAt: Date
    let duration: TimeInterval

    var totalCount: Int { repos.count }
    var behindCount: Int { repos.filter(\.isBehind).count }
    var dirtyCount: Int { repos.filter(\.isDirty).count }
    var warningCount: Int { repos.filter(\.hasWarning).count }

    var overallStatus: StatusLevel {
        repos.map(\.statusLevel).max() ?? .clean
    }
}

// MARK: - Notification

struct MonitorNotification: Identifiable {
    let id = UUID()
    let repoName: String
    let message: String
    let level: NotificationLevel
    let timestamp: Date = .now

    enum NotificationLevel: Int, Comparable {
        case info = 1
        case warning = 2
        case error = 3

        static func < (lhs: NotificationLevel, rhs: NotificationLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

// MARK: - Persisted State

struct PersistedState: Codable {
    var repos: [RepoSnapshot]
    var lastScanDate: Date?
    var lastNotificationDate: Date?
}

// MARK: - Scan Progress

struct ScanProgress {
    var current: Int = 0
    var total: Int = 0
    var currentRepo: String = ""
    var currentRepoPath: String = ""
    var isScanning: Bool = false

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}
