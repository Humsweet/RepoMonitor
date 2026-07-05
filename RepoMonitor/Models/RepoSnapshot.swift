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
    var modifiedCount: Int = 0
    var untrackedCount: Int = 0
    var dirtyFiles: [String] = []
    var fetchSuccess: Bool = true
    var fetchError: String = ""
    var pullError: String = ""
    var pushError: String = ""
    /// A push that stopped safely and needs the user to act (sensitive file
    /// staged, Claude unavailable, git identity missing). Distinct from
    /// `pushError` — rendered as amber "attention", not red "failure".
    var pushBlock: String = ""
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
        modifiedCount: Int = 0,
        untrackedCount: Int = 0,
        dirtyFiles: [String] = [],
        fetchSuccess: Bool = true,
        fetchError: String = "",
        pullError: String = "",
        pushError: String = "",
        pushBlock: String = "",
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
        self.modifiedCount = modifiedCount
        self.untrackedCount = untrackedCount
        self.dirtyFiles = dirtyFiles
        self.fetchSuccess = fetchSuccess
        self.fetchError = fetchError
        self.pullError = pullError
        self.pushError = pushError
        self.pushBlock = pushBlock
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
        modifiedCount = try container.decodeIfPresent(Int.self, forKey: .modifiedCount) ?? 0
        untrackedCount = try container.decodeIfPresent(Int.self, forKey: .untrackedCount) ?? 0
        dirtyFiles = try container.decodeIfPresent([String].self, forKey: .dirtyFiles) ?? []
        fetchSuccess = try container.decodeIfPresent(Bool.self, forKey: .fetchSuccess) ?? true
        fetchError = try container.decodeIfPresent(String.self, forKey: .fetchError) ?? ""
        pullError = try container.decodeIfPresent(String.self, forKey: .pullError) ?? ""
        pushError = try container.decodeIfPresent(String.self, forKey: .pushError) ?? ""
        pushBlock = try container.decodeIfPresent(String.self, forKey: .pushBlock) ?? ""
        isSkipped = try container.decodeIfPresent(Bool.self, forKey: .isSkipped) ?? false
        lastScanned = try container.decodeIfPresent(Date.self, forKey: .lastScanned) ?? .now
    }

    var isBehind: Bool { behind > 0 }
    var isAhead: Bool { ahead > 0 }
    var hasWarning: Bool { !fetchSuccess }

    /// Group label derived from the repo's parent folder, e.g. a repo at
    /// `…/Github Personal/RepoMonitor` is tagged "Github Personal".
    var groupTag: String {
        let parent = (path as NSString).deletingLastPathComponent
        let label = (parent as NSString).lastPathComponent
        return label.isEmpty ? "—" : label
    }

    /// Combined divergence used for the merged Sync column sort.
    var syncMagnitude: Int { ahead + behind }

    /// How loudly the Status column should speak: a real failure (red) outranks
    /// an actionable safe-stop (amber), which outranks purely informational
    /// local edits (neutral). Normal uncommitted work is *not* a warning.
    var issueSeverity: IssueSeverity {
        if !pushError.isEmpty || !pullError.isEmpty || !fetchSuccess { return .error }
        if !pushBlock.isEmpty { return .attention }
        if isDirty { return .info }
        return .clean
    }

    /// Sort key for the Status column: error > attention > info > clean.
    var issueRank: Int { issueSeverity.rawValue }

    /// Short summary of why the repo is dirty, e.g. "2 modified, 1 untracked".
    var dirtySummary: String {
        var parts: [String] = []
        if modifiedCount > 0 { parts.append("\(modifiedCount) modified") }
        if untrackedCount > 0 { parts.append("\(untrackedCount) untracked") }
        if parts.isEmpty { return isDirty ? "Uncommitted changes" : "" }
        return parts.joined(separator: ", ")
    }

    /// Glance-level label for the Status column. Raw git stderr is *categorised*
    /// into a human reason ("Rejected: remote ahead", "Auth failed", …) so the
    /// chip is legible at a glance; the full stderr lives in the tooltip
    /// (`issueDetail`). Order mirrors `issueSeverity`.
    var issueText: String {
        if !pushError.isEmpty { return Self.gitLabel(action: "Push", raw: pushError) }
        if !pullError.isEmpty { return Self.gitLabel(action: "Pull", raw: pullError) }
        if !pushBlock.isEmpty { return pushBlock }
        if !fetchSuccess { return Self.gitLabel(action: "Fetch", raw: fetchError) }
        if isDirty { return dirtySummary }
        return ""
    }

    /// Full, uncategorised detail for the tooltip — the raw git message the
    /// short `issueText` was distilled from. Empty for the info/clean states.
    var issueDetail: String {
        if !pushError.isEmpty { return pushError }
        if !pullError.isEmpty { return pullError }
        if !pushBlock.isEmpty { return pushBlock }
        if !fetchSuccess { return fetchError }
        return ""
    }

    var hasIssue: Bool { !issueText.isEmpty }
    /// Red "failure" styling. `pushBlock` is deliberately excluded — it's a safe
    /// stop rendered as amber attention, not an error.
    var issueIsError: Bool { issueSeverity == .error }

    /// Map raw git stderr onto a short, human reason. Falls back to a plain
    /// "<action> failed" when the failure doesn't match a known pattern.
    private static func gitLabel(action: String, raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("non-fast-forward") || s.contains("fetch first")
            || s.contains("rejected") || s.contains("failed to push some refs") {
            return "Rejected: remote ahead"
        }
        if s.contains("authentication") || s.contains("could not read username")
            || s.contains("permission denied") || s.contains("publickey")
            || s.contains("403") || s.contains("401") {
            return "Auth failed"
        }
        if s.contains("could not resolve host") || s.contains("unable to access")
            || s.contains("timed out") || s.contains("timeout")
            || s.contains("connection") {
            return "Network error"
        }
        if s.contains("conflict") { return "Merge conflict" }
        return "\(action) failed"
    }
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

/// How the Status column should read a repo's state. Deliberately separates
/// "informational" (normal local edits) from "attention" (a safe stop that
/// needs the user) and "error" (a real failure) so normal work never wears a
/// warning colour.
enum IssueSeverity: Int {
    case clean = 0
    case info = 1
    case attention = 2
    case error = 3
}

// MARK: - Scan Result

struct ScanResult {
    let repos: [RepoSnapshot]
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
