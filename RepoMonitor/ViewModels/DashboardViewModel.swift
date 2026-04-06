import Foundation
import SwiftUI
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    enum RepoSortColumn {
        case status
        case name
        case branch
        case upstream
        case remote
        case ahead
        case behind
        case dirty
        case skipped
        case scanned
        case path

        var defaultAscending: Bool {
            switch self {
            case .ahead, .behind, .dirty, .skipped, .scanned, .status:
                return false
            case .name, .branch, .upstream, .remote, .path:
                return true
            }
        }
    }

    @Published var config: MonitorConfig
    @Published var repos: [RepoSnapshot] = []
    @Published var selectedRepo: RepoSnapshot?
    @Published var progress = ScanProgress()
    @Published var lastScanDate: Date?
    @Published var scanDuration: TimeInterval = 0
    @Published var showSettings = false
    @Published var searchText = ""
    @Published var sortColumn: RepoSortColumn = .status
    @Published var sortAscending = false

    let service: RepoMonitorService
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

    var totalCount: Int { repos.count }
    var behindCount: Int { repos.filter(\.isBehind).count }
    var dirtyCount: Int { repos.filter(\.isDirty).count }
    var warningCount: Int { repos.filter(\.hasWarning).count }

    var overallStatus: StatusLevel {
        repos.map(\.statusLevel).max() ?? .clean
    }

    var menuBarIcon: String {
        if progress.isScanning { return "arrow.triangle.2.circlepath" }
        switch overallStatus {
        case .clean: return "checkmark.circle"
        case .dirty: return "pencil.circle"
        case .behind: return "arrow.down.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    var menuBarLabel: String {
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

        Task { @MainActor [weak self] in
            self?.startPeriodicScan()
        }
    }

    // MARK: - Actions

    func startPeriodicScan() {
        guard !hasStarted else { return }
        hasStarted = true
        NotificationService.shared.requestPermission()
        ConfigLoader.createDefaultConfigIfNeeded()

        // Initial scan
        Task { await scan() }

        // Periodic timer
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

    func scan() async {
        _ = await service.scan()
    }

    func scanRepo(_ repo: RepoSnapshot) async {
        guard !progress.isScanning else { return }
        _ = await service.scanRepo(at: repo.path)
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

    func openInTerminal(_ repo: RepoSnapshot) {
        let script = "tell application \"Terminal\" to do script \"cd '\(repo.path)'\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
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

    func addScanFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Select folders to scan for git repositories"
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            for url in panel.urls {
                let path = url.path
                if !config.roots.contains(where: { $0.path == path }) {
                    // If the folder itself is a git repo, use mode .self; otherwise .children
                    let isGitRepo = FileManager.default.fileExists(
                        atPath: url.appendingPathComponent(".git").path
                    )
                    config.roots.append(RootEntry(path: path, mode: isGitRepo ? .`self` : .children))
                }
            }
            saveConfig()
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
