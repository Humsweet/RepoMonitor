import Foundation

@MainActor
final class RepoMonitorService: ObservableObject {
    @Published var progress = ScanProgress()
    @Published var repos: [RepoSnapshot] = []
    @Published var lastResult: ScanResult?

    private var gitCli: GitCLI
    private var config: MonitorConfig
    private var previousState: PersistedState
    private var skipRequestedPath: String?

    var persistedLastScanDate: Date? { previousState.lastScanDate }

    init(config: MonitorConfig) {
        self.config = config
        self.gitCli = GitCLI(timeoutSeconds: config.git.fetchTimeoutSeconds)
        self.previousState = ConfigLoader.loadState(from: config)
        self.repos = previousState.repos
        pruneUnavailableRepos()
    }

    func updateConfig(_ config: MonitorConfig) {
        self.config = config
        self.gitCli = GitCLI(timeoutSeconds: config.git.fetchTimeoutSeconds)
        self.previousState = ConfigLoader.loadState(from: config)
        self.repos = previousState.repos
        pruneUnavailableRepos()
    }

    func requestSkipCurrentRepo() {
        guard progress.isScanning, !progress.currentRepoPath.isEmpty else { return }
        skipRequestedPath = progress.currentRepoPath
        Task { await gitCli.terminateCurrentProcess() }
    }

    func removeRepo(at path: String) {
        let normalizedPath = normalizePath(path)
        repos.removeAll { normalizePath($0.path) == normalizedPath }
        repos = sortRepos(repos)
        persistCurrentState(lastScanDate: previousState.lastScanDate, lastNotificationDate: previousState.lastNotificationDate)
    }

    // MARK: - Scan

    func scan() async -> ScanResult {
        await runScan(targetPaths: scanCandidates())
    }

    func scanRepo(at path: String) async -> ScanResult {
        let normalizedPath = normalizePath(path)
        pruneUnavailableRepos()

        guard isRepoAvailable(at: normalizedPath) else {
            removeRepo(at: normalizedPath)
            return makeResult(notifications: [], scannedAt: Date(), duration: 0)
        }

        if repos.first(where: { normalizePath($0.path) == normalizedPath }) == nil {
            upsertRepo(RepoSnapshot(
                name: URL(fileURLWithPath: normalizedPath).lastPathComponent,
                path: normalizedPath
            ))
        }

        return await runScan(targetPaths: [normalizedPath])
    }

    private func runScan(targetPaths: [String]) async -> ScanResult {
        guard !progress.isScanning else {
            return makeResult(notifications: [], scannedAt: Date(), duration: 0)
        }

        pruneUnavailableRepos()

        let uniqueTargets = Array(Set(targetPaths.map(normalizePath))).filter { isRepoAvailable(at: $0) }
        guard !uniqueTargets.isEmpty else {
            let result = makeResult(notifications: [], scannedAt: Date(), duration: 0)
            lastResult = result
            return result
        }

        let startTime = Date()
        let oldReposByPath = Dictionary(uniqueKeysWithValues: previousState.repos.map { (normalizePath($0.path), $0) })
        skipRequestedPath = nil
        progress = ScanProgress(isScanning: true)
        progress.total = uniqueTargets.count

        var notifications: [MonitorNotification] = []

        for (index, repoPath) in uniqueTargets.enumerated() {
            let name = URL(fileURLWithPath: repoPath).lastPathComponent
            progress.current = index + 1
            progress.currentRepo = name
            progress.currentRepoPath = repoPath

            let previousSnapshot = repos.first(where: { normalizePath($0.path) == repoPath })
            let placeholder = previousSnapshot ?? RepoSnapshot(name: name, path: repoPath)
            upsertRepo(placeholder)

            let snapshot = await scanSnapshot(for: repoPath, previous: placeholder)
            upsertRepo(snapshot)

            if !snapshot.isSkipped, let oldSnapshot = oldReposByPath[repoPath] {
                notifications.append(contentsOf: generateNotifications(old: oldSnapshot, new: snapshot))
            }
        }

        repos = sortRepos(repos)

        let filtered = filterNotifications(notifications)
        let throttled = throttleNotifications(filtered)
        let scannedAt = Date()
        persistCurrentState(
            lastScanDate: scannedAt,
            lastNotificationDate: throttled.isEmpty ? previousState.lastNotificationDate : scannedAt
        )

        let result = makeResult(
            notifications: throttled,
            scannedAt: scannedAt,
            duration: Date().timeIntervalSince(startTime)
        )

        progress = ScanProgress()
        lastResult = result
        return result
    }

    private func scanSnapshot(for path: String, previous: RepoSnapshot) async -> RepoSnapshot {
        var snapshot = previous
        snapshot.isSkipped = false
        snapshot.fetchSuccess = true
        snapshot.fetchError = ""

        if shouldSkip(path) {
            return makeSkippedSnapshot(from: previous)
        }

        if config.git.fetchBeforeCompare {
            let fetchResult = await gitCli.fetch(in: path)
            if consumeSkip(for: path) {
                return makeSkippedSnapshot(from: previous)
            }
            snapshot.fetchSuccess = fetchResult.success
            snapshot.fetchError = fetchResult.error
        }

        snapshot.branch = await gitCli.currentBranch(in: path)
        if consumeSkip(for: path) {
            return makeSkippedSnapshot(from: previous)
        }

        snapshot.upstream = await gitCli.upstream(in: path)
        if consumeSkip(for: path) {
            return makeSkippedSnapshot(from: previous)
        }

        snapshot.remoteUrl = await gitCli.remoteUrl(in: path)
        if consumeSkip(for: path) {
            return makeSkippedSnapshot(from: previous)
        }

        snapshot.isDirty = await gitCli.isDirty(in: path)
        if consumeSkip(for: path) {
            return makeSkippedSnapshot(from: previous)
        }

        let counts = await gitCli.aheadBehind(in: path)
        if consumeSkip(for: path) {
            return makeSkippedSnapshot(from: previous)
        }

        snapshot.ahead = counts.ahead
        snapshot.behind = counts.behind
        snapshot.lastScanned = Date()
        return snapshot
    }

    // MARK: - Discover Repos

    private func scanCandidates() -> [String] {
        var paths = Set(discoverRepos())
        for repo in repos {
            let normalized = normalizePath(repo.path)
            if isRepoAvailable(at: normalized) {
                paths.insert(normalized)
            }
        }
        return sortPaths(Array(paths))
    }

    private func discoverRepos() -> [String] {
        var paths: [String] = []
        let fm = FileManager.default
        let unwatched = unwatchedPaths()

        for root in config.roots {
            let expanded = normalizePath(root.path)
            switch root.mode {
            case .`self`:
                if isRepoAvailable(at: expanded) && !unwatched.contains(expanded) {
                    paths.append(expanded)
                }
            case .children:
                guard let children = try? fm.contentsOfDirectory(atPath: expanded) else { continue }
                for child in children {
                    let childPath = normalizePath((expanded as NSString).appendingPathComponent(child))
                    if isRepoAvailable(at: childPath) && !unwatched.contains(childPath) {
                        paths.append(childPath)
                    }
                }
            }
        }

        return sortPaths(paths)
    }

    private func pruneUnavailableRepos() {
        let pruned = repos.filter { isRepoAvailable(at: normalizePath($0.path)) }
        let sorted = sortRepos(pruned)
        guard sorted != repos || sorted != previousState.repos else {
            repos = sorted
            return
        }

        repos = sorted
        persistCurrentState(lastScanDate: previousState.lastScanDate, lastNotificationDate: previousState.lastNotificationDate)
    }

    private func isRepoAvailable(at path: String) -> Bool {
        let normalizedPath = normalizePath(path)
        let fm = FileManager.default
        guard !unwatchedPaths().contains(normalizedPath) else { return false }
        guard fm.fileExists(atPath: normalizedPath) else { return false }
        let gitDir = (normalizedPath as NSString).appendingPathComponent(".git")
        return fm.fileExists(atPath: gitDir)
    }

    private func unwatchedPaths() -> Set<String> {
        Set(config.unwatchedPaths.map(normalizePath))
    }

    // MARK: - State

    private func persistCurrentState(lastScanDate: Date?, lastNotificationDate: Date?) {
        let state = PersistedState(
            repos: sortRepos(repos),
            lastScanDate: lastScanDate,
            lastNotificationDate: lastNotificationDate
        )
        ConfigLoader.saveState(state, config: config)
        previousState = state
        repos = state.repos
    }

    private func upsertRepo(_ snapshot: RepoSnapshot) {
        let path = normalizePath(snapshot.path)
        if let index = repos.firstIndex(where: { normalizePath($0.path) == path }) {
            repos[index] = snapshot
        } else {
            repos.append(snapshot)
        }
        repos = sortRepos(repos)
    }

    private func makeSkippedSnapshot(from previous: RepoSnapshot) -> RepoSnapshot {
        var snapshot = previous
        snapshot.isSkipped = true
        snapshot.fetchSuccess = true
        snapshot.fetchError = ""
        skipRequestedPath = nil
        return snapshot
    }

    private func shouldSkip(_ path: String) -> Bool {
        normalizePath(skipRequestedPath ?? "") == normalizePath(path)
    }

    private func consumeSkip(for path: String) -> Bool {
        guard shouldSkip(path) else { return false }
        skipRequestedPath = nil
        return true
    }

    // MARK: - Notification Generation

    private func generateNotifications(old: RepoSnapshot, new: RepoSnapshot) -> [MonitorNotification] {
        var notes: [MonitorNotification] = []

        if !new.fetchSuccess && old.fetchSuccess {
            notes.append(MonitorNotification(
                repoName: new.name,
                message: "Fetch failed: \(new.fetchError)",
                level: .error
            ))
        }

        if new.behind > old.behind {
            notes.append(MonitorNotification(
                repoName: new.name,
                message: "\(new.behind) commit(s) behind upstream",
                level: .warning
            ))
        }

        if new.isDirty && !old.isDirty {
            notes.append(MonitorNotification(
                repoName: new.name,
                message: "Working tree has uncommitted changes",
                level: .info
            ))
        }

        return notes
    }

    private func filterNotifications(_ notifications: [MonitorNotification]) -> [MonitorNotification] {
        guard config.notifications.enabled else { return [] }
        switch config.notifications.mode {
        case .errors:
            return notifications.filter { $0.level == .error }
        case .behind:
            return notifications.filter { $0.level >= .warning }
        case .behindAndDirty:
            return notifications
        }
    }

    private func throttleNotifications(_ notifications: [MonitorNotification]) -> [MonitorNotification] {
        guard !notifications.isEmpty else { return [] }
        let interval = TimeInterval(config.notifications.minimumIntervalMinutes * 60)
        if let lastDate = previousState.lastNotificationDate,
           Date().timeIntervalSince(lastDate) < interval {
            return []
        }
        if let top = notifications.max(by: { $0.level < $1.level }) {
            return [top]
        }
        return []
    }

    // MARK: - Helpers

    private func makeResult(notifications: [MonitorNotification], scannedAt: Date, duration: TimeInterval) -> ScanResult {
        ScanResult(
            repos: repos,
            notifications: notifications,
            scannedAt: scannedAt,
            duration: duration
        )
    }

    private func sortRepos(_ repos: [RepoSnapshot]) -> [RepoSnapshot] {
        repos.sorted { a, b in
            if a.behind != b.behind { return a.behind > b.behind }
            if a.isDirty != b.isDirty { return a.isDirty && !b.isDirty }
            if a.isSkipped != b.isSkipped { return !a.isSkipped && b.isSkipped }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func sortPaths(_ paths: [String]) -> [String] {
        paths.sorted { lhs, rhs in
            URL(fileURLWithPath: lhs).lastPathComponent.localizedCaseInsensitiveCompare(
                URL(fileURLWithPath: rhs).lastPathComponent
            ) == .orderedAscending
        }
    }

    private func normalizePath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
