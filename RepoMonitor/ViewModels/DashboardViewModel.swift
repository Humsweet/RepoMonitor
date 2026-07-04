import Foundation
import SwiftUI
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    enum RepoSortColumn {
        case status
        case group
        case name
        case branch
        case upstream
        case remote
        case ahead
        case behind
        case sync
        case issue
        case dirty
        case skipped
        case scanned
        case path

        var defaultAscending: Bool {
            switch self {
            case .ahead, .behind, .sync, .issue, .dirty, .skipped, .scanned, .status:
                return false
            case .group, .name, .branch, .upstream, .remote, .path:
                return true
            }
        }
    }

    @Published var config: MonitorConfig
    @Published var repos: [RepoSnapshot] = []
    @Published var selectedRepo: RepoSnapshot?

    /// Set when an unwatch is requested (button, context menu, or ⌘6); drives a
    /// confirmation dialog since unwatching is destructive.
    @Published var repoPendingUnwatch: RepoSnapshot?
    @Published var progress = ScanProgress()
    @Published var lastScanDate: Date?
    @Published var scanDuration: TimeInterval = 0
    @Published var showSettings = false
    @Published var searchText = ""
    @Published var sortColumn: RepoSortColumn = .group
    @Published var sortAscending = true
    @Published var pullingPaths: Set<String> = []
    @Published var pushingPaths: Set<String> = []

    /// Network reachability, mirrored from `NetworkMonitor`. Drives the offline
    /// indicator and gates the periodic scan loop.
    @Published var isOnline = true

    // Terminal selection (first run picks a default; changeable in Settings)
    @Published var showTerminalPicker = false
    @Published var availableTerminals: [TerminalApp] = []
    private var pendingTerminalRepoPath: String?

    // New-remote-repo review
    @Published var pendingRemoteRepos: [DiscoveredRemoteRepo] = []
    @Published var showRemoteReview = false
    @Published var cloningRemoteIDs: Set<String> = []
    @Published var cloneErrors: [String: String] = [:]

    /// Launch-at-login state, backed by macOS (`SMAppService`), not config.json.
    var launchAtLogin: Bool {
        get { LaunchAtLoginService.isEnabled }
        set {
            LaunchAtLoginService.setEnabled(newValue)
            objectWillChange.send()
        }
    }

    let service: RepoMonitorService
    private let networkMonitor = NetworkMonitor()
    private var scanTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false

    // Computed
    var filteredRepos: [RepoSnapshot] {
        guard !searchText.isEmpty else { return repos }
        let query = searchText.lowercased()
        return repos.filter {
            $0.name.lowercased().contains(query) ||
            $0.branch.lowercased().contains(query) ||
            $0.path.lowercased().contains(query) ||
            $0.upstream.lowercased().contains(query) ||
            $0.remoteUrl.lowercased().contains(query)
        }
    }

    var displayedRepos: [RepoSnapshot] {
        filteredRepos.sorted(by: compareRepos)
    }

    // MARK: - Keyboard Selection & Navigation

    /// Index of the selected repo within the currently displayed (filtered +
    /// sorted) list, or nil if nothing is selected or it fell out of view.
    var selectedIndex: Int? {
        guard let id = selectedRepo?.id else { return nil }
        return displayedRepos.firstIndex { $0.id == id }
    }

    /// Selects the first visible repo (used when arrowing down out of search).
    func selectFirstRepo() {
        selectedRepo = displayedRepos.first
    }

    /// Selects the last visible repo (used when arrowing up out of search).
    func selectLastRepo() {
        selectedRepo = displayedRepos.last
    }

    /// Moves the selection by `delta` rows within the displayed list, clamped to
    /// the ends. Returns `false` when already at the boundary in that direction
    /// (so the caller can, e.g., hand focus back to the search field).
    @discardableResult
    func moveSelection(by delta: Int) -> Bool {
        let list = displayedRepos
        guard !list.isEmpty else { return false }
        guard let current = selectedIndex else {
            selectedRepo = delta >= 0 ? list.first : list.last
            return true
        }
        let next = current + delta
        guard next >= 0, next < list.count else { return false }
        selectedRepo = list[next]
        return true
    }

    /// Runs the action at position `n` (1...7) on `repo`, matching the on-screen
    /// order of the row's action buttons: 1 Scan · 2 Pull · 3 Push · 4 Finder ·
    /// 5 VS Code · 6 Terminal · 7 Unwatch.
    func performRowAction(_ n: Int, on repo: RepoSnapshot) {
        switch n {
        case 1: Task { await scanRepo(repo) }
        case 2: Task { await pullRepo(repo) }
        case 3: Task { await pushRepo(repo) }
        case 4: openInFinder(repo)
        case 5: openInVSCode(repo)
        case 6: openInTerminal(repo)
        case 7: requestUnwatch(repo)
        default: break
        }
    }

    var totalCount: Int { repos.count }
    var behindCount: Int { repos.filter(\.isBehind).count }
    var dirtyCount: Int { repos.filter(\.isDirty).count }
    var warningCount: Int { repos.filter(\.hasWarning).count }

    var overallStatus: StatusLevel {
        repos.map(\.statusLevel).max() ?? .clean
    }

    var menuBarIcon: String {
        if !isOnline { return "wifi.slash" }
        if progress.isScanning { return "arrow.triangle.2.circlepath" }
        switch overallStatus {
        case .clean: return "checkmark.circle"
        case .dirty: return "pencil.circle"
        case .behind: return "arrow.down.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    var menuBarLabel: String {
        if !isOnline { return "Offline" }
        if progress.isScanning { return "Scanning..." }
        if repos.isEmpty { return "No repos" }
        let issues = behindCount + dirtyCount + warningCount
        if issues == 0 { return "All clean" }
        return "\(issues) issue\(issues == 1 ? "" : "s")"
    }

    init() {
        let loaded = (try? ConfigLoader.loadConfig()) ?? MonitorConfig.defaultConfig
        self.config = loaded
        self.service = RepoMonitorService(config: loaded)
        self.lastScanDate = service.persistedLastScanDate
        self.repos = service.repos

        // Observe service progress
        service.$progress
            .assign(to: &$progress)

        service.$repos
            .sink { [weak self] repos in
                guard let self else { return }
                self.repos = repos
                if let selectedPath = self.selectedRepo?.path {
                    self.selectedRepo = repos.first { $0.path == selectedPath }
                }
            }
            .store(in: &cancellables)

        service.$lastResult
            .compactMap { $0 }
            .sink { [weak self] result in
                self?.lastScanDate = result.scannedAt
                self?.scanDuration = result.duration

                // Send notifications
                NotificationService.shared.sendBatch(result.notifications)
            }
            .store(in: &cancellables)

        service.$pendingRemoteRepos
            .sink { [weak self] repos in
                guard let self else { return }
                self.pendingRemoteRepos = repos
                // Auto-present the review when new repos appear; harmless if the
                // dashboard window is closed (the sheet shows on next open).
                if !repos.isEmpty {
                    self.showRemoteReview = true
                }
            }
            .store(in: &cancellables)

        Task { @MainActor [weak self] in
            self?.startPeriodicScan()
            self?.startNetworkMonitoring()
        }
    }

    // MARK: - Actions

    func startPeriodicScan() {
        guard !hasStarted else { return }
        hasStarted = true
        NotificationService.shared.requestPermission()
        ConfigLoader.createDefaultConfigIfNeeded()

        // While offline, skip the initial scan and leave the timer disarmed —
        // the reconnect edge kicks off the first scan once connectivity returns.
        if isOnline {
            Task { await scan() }
            armScanTimer()
        }
    }

    private func armScanTimer() {
        scanTimer?.invalidate()
        let interval = TimeInterval(config.desktop.scanIntervalMinutes * 60)
        scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.scan()
            }
        }
    }

    func stopPeriodicScan() {
        scanTimer?.invalidate()
        scanTimer = nil
        hasStarted = false
    }

    // MARK: - Network Reconnect

    /// Bridges `NetworkMonitor` into the scan loop: pause periodic fetching while
    /// offline, and on reconnect run an immediate catch-up scan (fetch +
    /// auto-pull, which still honors `config.git.autoPullEnabled`) before
    /// resuming the timer.
    private func startNetworkMonitoring() {
        networkMonitor.onReconnect = { [weak self] in
            self?.handleNetworkReconnected()
        }
        networkMonitor.$isOnline
            .removeDuplicates()
            .sink { [weak self] online in
                guard let self else { return }
                self.isOnline = online
                if !online { self.pauseScanForOffline() }
            }
            .store(in: &cancellables)
        networkMonitor.start()
    }

    /// Network dropped — stop the periodic loop; every scan would just fail until
    /// connectivity returns.
    private func pauseScanForOffline() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    /// Network came back after a drop — catch up right away, then resume the loop.
    private func handleNetworkReconnected() {
        guard hasStarted else { return }
        Task { await scan() }
        if scanTimer == nil { armScanTimer() }
    }

    func scan() async {
        _ = await service.scan()
    }

    func scanRepo(_ repo: RepoSnapshot) async {
        guard !progress.isScanning else { return }
        _ = await service.scanRepo(at: repo.path)
    }

    func pullRepo(_ repo: RepoSnapshot) async {
        guard !progress.isScanning, !pullingPaths.contains(repo.path) else { return }
        pullingPaths.insert(repo.path)
        defer { pullingPaths.remove(repo.path) }
        _ = await service.pullRepo(at: repo.path)
    }

    func pushRepo(_ repo: RepoSnapshot) async {
        guard !progress.isScanning, !pushingPaths.contains(repo.path) else { return }
        pushingPaths.insert(repo.path)
        defer { pushingPaths.remove(repo.path) }
        _ = await service.pushRepo(at: repo.path)
    }

    func skipCurrentRepo() {
        service.requestSkipCurrentRepo()
    }

    func saveConfig() {
        try? ConfigLoader.saveConfig(config)
        service.updateConfig(config)
        lastScanDate = service.persistedLastScanDate

        // Restart timer with new interval
        stopPeriodicScan()
        startPeriodicScan()
    }

    /// Requests unwatching `repo`, surfacing a confirmation dialog first since
    /// the action is destructive. Confirm via `confirmPendingUnwatch()`.
    func requestUnwatch(_ repo: RepoSnapshot) {
        repoPendingUnwatch = repo
    }

    func confirmPendingUnwatch() {
        guard let repo = repoPendingUnwatch else { return }
        repoPendingUnwatch = nil
        unwatchRepo(repo)
    }

    func cancelPendingUnwatch() {
        repoPendingUnwatch = nil
    }

    func unwatchRepo(_ repo: RepoSnapshot) {
        if !config.unwatchedPaths.contains(repo.path) {
            config.unwatchedPaths.append(repo.path)
        }
        service.removeRepo(at: repo.path)
        repos.removeAll { $0.path == repo.path }
        if selectedRepo?.path == repo.path {
            selectedRepo = nil
        }
        saveConfig()
    }

    func rewatchPath(_ path: String) {
        config.unwatchedPaths.removeAll { $0 == path }
        saveConfig()
    }

    // MARK: - Remote Repo Review

    func cloneRemoteRepo(_ repo: DiscoveredRemoteRepo) async {
        guard !cloningRemoteIDs.contains(repo.id) else { return }
        cloningRemoteIDs.insert(repo.id)
        cloneErrors[repo.id] = nil
        defer { cloningRemoteIDs.remove(repo.id) }

        let error = await service.cloneRemoteRepo(repo)
        if error.isEmpty {
            if pendingRemoteRepos.isEmpty { showRemoteReview = false }
        } else {
            cloneErrors[repo.id] = error
        }
    }

    /// Records that the user doesn't want this repo cloned, so it's never asked
    /// about again, and drops it from the current review.
    func ignoreRemoteRepo(_ repo: DiscoveredRemoteRepo) {
        if !config.git.ignoredRemoteRepos.contains(repo.id) {
            config.git.ignoredRemoteRepos.append(repo.id)
        }
        saveConfig()
        service.dismissRemoteRepo(id: repo.id)
        if pendingRemoteRepos.isEmpty { showRemoteReview = false }
    }

    func ignoreAllRemoteRepos() {
        for repo in pendingRemoteRepos where !config.git.ignoredRemoteRepos.contains(repo.id) {
            config.git.ignoredRemoteRepos.append(repo.id)
        }
        saveConfig()
        for repo in pendingRemoteRepos { service.dismissRemoteRepo(id: repo.id) }
        showRemoteReview = false
    }

    /// Closing the review without acting on a repo counts as "don't pull it,
    /// don't ask again" — every still-pending repo is permanently ignored. Only
    /// genuinely new repos will surface on later scans. Mistakes can be undone
    /// via Settings › Ignored Remote Repos.
    func handleRemoteReviewDismissed() {
        guard !pendingRemoteRepos.isEmpty else { return }
        for repo in pendingRemoteRepos where !config.git.ignoredRemoteRepos.contains(repo.id) {
            config.git.ignoredRemoteRepos.append(repo.id)
        }
        saveConfig()
        let ids = pendingRemoteRepos.map(\.id)
        for id in ids { service.dismissRemoteRepo(id: id) }
    }

    func cloneAllRemoteRepos() async {
        for repo in pendingRemoteRepos {
            await cloneRemoteRepo(repo)
        }
    }

    /// Removes a repo from the permanent ignore list so it can be suggested again.
    func unignoreRemoteRepo(_ id: String) {
        config.git.ignoredRemoteRepos.removeAll { $0 == id }
        saveConfig()
    }

    /// Opens the repo in the user's chosen terminal. On first use (no choice
    /// yet, or the chosen app was uninstalled) it scans installed terminals and
    /// asks the user to pick a default, then proceeds with the launch.
    func openInTerminal(_ repo: RepoSnapshot) {
        let chosenID = config.desktop.terminalAppID
        if TerminalCatalog.app(for: chosenID) != nil, TerminalCatalog.isInstalled(chosenID) {
            launchPreferredTerminal(at: repo.path)
            return
        }

        let installed = TerminalCatalog.installed()
        guard !installed.isEmpty else {
            // Should never happen (Terminal.app is always present), but degrade
            // gracefully rather than do nothing.
            TerminalApp(id: "com.apple.Terminal", name: "Terminal", launch: .openDir(appName: "Terminal"))
                .open(at: repo.path)
            return
        }

        availableTerminals = installed
        pendingTerminalRepoPath = repo.path
        showTerminalPicker = true
    }

    /// Persists the chosen terminal as the default, then opens any repo whose
    /// terminal launch was waiting on this choice.
    func selectTerminal(_ app: TerminalApp) {
        config.desktop.terminalAppID = app.id
        saveConfig()
        showTerminalPicker = false
        if let path = pendingTerminalRepoPath {
            pendingTerminalRepoPath = nil
            launchPreferredTerminal(at: path)
        }
    }

    func cancelTerminalSelection() {
        showTerminalPicker = false
        pendingTerminalRepoPath = nil
    }

    private func launchPreferredTerminal(at path: String) {
        let installed = TerminalCatalog.installed()
        if let preferred = installed.first(where: { $0.id == config.desktop.terminalAppID }),
           preferred.open(at: path) {
            return
        }
        // Chosen app vanished mid-session — fall back to any installed terminal.
        for terminal in installed where terminal.open(at: path) { return }
    }

    func openInVSCode(_ repo: RepoSnapshot) {
        let repoURL = URL(fileURLWithPath: repo.path)

        if let cliURL = locateVSCodeCLI() {
            let process = Process()
            process.executableURL = cliURL
            process.arguments = [repo.path]
            try? process.run()
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Visual Studio Code", repo.path]
        if (try? process.run()) != nil {
            return
        }

        NSWorkspace.shared.open(repoURL)
    }

    func openInFinder(_ repo: RepoSnapshot) {
        NSWorkspace.shared.open(URL(fileURLWithPath: repo.path))
    }

    /// Opens a folder picker and adds the chosen folders as scan roots.
    /// Returns `true` if at least one new root was added.
    @discardableResult
    func addScanFolders() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Select a git repository, or a folder containing repositories"
        panel.prompt = "Add"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return false }

        var added = false
        for url in panel.urls {
            let path = url.path
            if !config.roots.contains(where: { $0.path == path }) {
                // If the folder itself is a git repo, use mode .self; otherwise .children
                let isGitRepo = FileManager.default.fileExists(
                    atPath: url.appendingPathComponent(".git").path
                )
                config.roots.append(RootEntry(path: path, mode: isGitRepo ? .`self` : .children))
                added = true
            }
            // Re-watching a previously unwatched path takes precedence over the unwatch list.
            if config.unwatchedPaths.contains(path) {
                config.unwatchedPaths.removeAll { $0 == path }
                added = true
            }
        }
        if added {
            saveConfig()
        }
        return added
    }

    /// Dashboard entry point: add scan folders, then immediately rescan so the
    /// newly added repositories show up without waiting for the next cycle.
    func addReposAndScan() {
        guard !progress.isScanning else {
            addScanFolders()
            return
        }
        if addScanFolders() {
            Task { await scan() }
        }
    }

    func removeRoot(_ root: RootEntry) {
        config.roots.removeAll { $0.path == root.path }
        saveConfig()
    }

    func revealConfig() {
        let path = ConfigLoader.configFilePath()
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }

    func saveHostCredential(host: String, username: String, token: String) throws {
        let entry = GitHostCredential(host: host, username: username)
        guard !entry.host.isEmpty else {
            throw GitCredentialStore.StoreError.emptyValue("Host")
        }
        guard !entry.username.isEmpty else {
            throw GitCredentialStore.StoreError.emptyValue("Username")
        }

        if let existing = config.git.hostCredentials.first(where: { $0.normalizedHost == entry.normalizedHost }),
           existing.username != entry.username {
            GitCredentialStore.deleteToken(host: existing.host, username: existing.username)
        }

        try GitCredentialStore.saveToken(token, host: entry.host, username: entry.username)

        if let index = config.git.hostCredentials.firstIndex(where: { $0.normalizedHost == entry.normalizedHost }) {
            config.git.hostCredentials[index] = entry
        } else {
            config.git.hostCredentials.append(entry)
        }

        config.git.hostCredentials.sort { $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending }
        saveConfig()
    }

    func removeHostCredential(_ credential: GitHostCredential) {
        GitCredentialStore.deleteToken(host: credential.host, username: credential.username)
        config.git.hostCredentials.removeAll { $0.normalizedHost == credential.normalizedHost }
        saveConfig()
    }

    func hasStoredToken(for credential: GitHostCredential) -> Bool {
        GitCredentialStore.hasToken(host: credential.host, username: credential.username)
    }

    func toggleSort(by column: RepoSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = column.defaultAscending
        }
    }

    private func compareRepos(_ lhs: RepoSnapshot, _ rhs: RepoSnapshot) -> Bool {
        let result: ComparisonResult = switch sortColumn {
        case .status:
            compareInts(lhs.statusRank, rhs.statusRank)
        case .group:
            compareStrings(lhs.groupTag, rhs.groupTag)
        case .sync:
            compareInts(lhs.syncMagnitude, rhs.syncMagnitude)
        case .issue:
            compareInts(lhs.issueRank, rhs.issueRank)
        case .name:
            compareStrings(lhs.name, rhs.name)
        case .branch:
            compareStrings(lhs.branch, rhs.branch)
        case .upstream:
            compareStrings(lhs.upstream, rhs.upstream)
        case .remote:
            compareStrings(lhs.remoteDisplay, rhs.remoteDisplay)
        case .ahead:
            compareInts(lhs.ahead, rhs.ahead)
        case .behind:
            compareInts(lhs.behind, rhs.behind)
        case .dirty:
            compareInts(lhs.isDirty ? 1 : 0, rhs.isDirty ? 1 : 0)
        case .skipped:
            compareInts(lhs.isSkipped ? 1 : 0, rhs.isSkipped ? 1 : 0)
        case .scanned:
            compareDates(lhs.lastScanned, rhs.lastScanned)
        case .path:
            compareStrings(lhs.path, rhs.path)
        }

        if result == .orderedSame {
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return sortAscending ? result == .orderedAscending : result == .orderedDescending
    }

    private func compareStrings(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.localizedCaseInsensitiveCompare(rhs)
    }

    private func compareInts(_ lhs: Int, _ rhs: Int) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private func compareDates(_ lhs: Date, _ rhs: Date) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private func locateVSCodeCLI() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/code",
            "/usr/local/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
            "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code"
        ]

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let bundleIDs = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders"
        ]

        for bundleID in bundleIDs {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let cliURL = appURL
                    .appendingPathComponent("Contents")
                    .appendingPathComponent("Resources")
                    .appendingPathComponent("app")
                    .appendingPathComponent("bin")
                    .appendingPathComponent("code")
                if fileManager.isExecutableFile(atPath: cliURL.path) {
                    return cliURL
                }
            }
        }

        return nil
    }
}
