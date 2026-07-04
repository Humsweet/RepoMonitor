import Foundation

@MainActor
final class RepoMonitorService: ObservableObject {
    @Published var progress = ScanProgress()
    @Published var repos: [RepoSnapshot] = []
    @Published var lastResult: ScanResult?
    /// Remote repos found during the last full scan that have no local clone.
    @Published var pendingRemoteRepos: [DiscoveredRemoteRepo] = []
    /// Live per-repo operation state (pull/push sub-phases), keyed by normalized
    /// path. The single source of truth for in-progress UI; never persisted.
    @Published var operations: [String: RepoOperation] = [:]
    /// Counts from the most recent scan's auto passes, for the bottom-bar summary.
    @Published var lastAutoPushed = 0
    @Published var lastAutoPulled = 0

    /// True while anything is running (a scan, or any pull/push). Gates new
    /// operations so a manual pull/push and a scan can't overlap and conflict.
    var isBusy: Bool { progress.isScanning || !operations.isEmpty }

    private var gitCli: GitCLI
    private let commitMessageGenerator = CommitMessageGenerator()
    private var config: MonitorConfig
    private var previousState: PersistedState
    private var skipRequestedPath: String?
    private var isDiscoveringRemotes = false

    var persistedLastScanDate: Date? { previousState.lastScanDate }

    init(config: MonitorConfig) {
        self.config = config
        self.gitCli = GitCLI()
        self.previousState = ConfigLoader.loadState(from: config)
        self.repos = previousState.repos
        pruneUnavailableRepos()
    }

    func updateConfig(_ config: MonitorConfig) {
        self.config = config
        self.gitCli = GitCLI()
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
        await runScan(targetPaths: scanCandidates(), discoverRemotes: true)
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

    // MARK: - Pull & Push
    //
    // Pull and Push share the same choke-point pattern (performPull / performPush)
    // so manual and automatic paths behave identically. Each choke point reports
    // its live sub-phase via `operations[path]`, so the row and bottom bar show
    // real progress instead of a frozen row.

    /// Typed pull/push results so callers can style the outcome precisely:
    /// green success, neutral advisory, amber "needs attention", or red failure.
    enum PullResult { case pulled, upToDate, failed(String) }
    enum PushResult { case pushed, nothingToPush, behind(Int), blocked(String), failed(String) }

    private func setOperation(_ op: RepoOperation?, for path: String) {
        operations[path] = op
    }

    /// Clears stale pull/push feedback the instant a new attempt starts, so an
    /// old red error never masquerades as a fresh failure while work is running.
    private func clearOpFeedback(at path: String) {
        guard var s = repos.first(where: { normalizePath($0.path) == path }) else { return }
        s.pullError = ""; s.pushError = ""; s.pushBlock = ""
        upsertRepo(s)
    }

    /// Re-reads a single repo's dirty + ahead/behind counts (no network fetch)
    /// and updates its snapshot. Lets a manual pull/push refresh its own row
    /// without a full scan, so it stays responsive even while a scan runs on
    /// other repos.
    private func refreshRepoState(at path: String) async {
        guard var s = repos.first(where: { normalizePath($0.path) == path }) else { return }
        let dirty = await gitCli.dirtyStatus(in: path)
        s.isDirty = dirty.isDirty
        s.modifiedCount = dirty.modified
        s.untrackedCount = dirty.untracked
        s.dirtyFiles = dirty.sampleFiles
        let counts = await gitCli.aheadBehind(in: path)
        s.ahead = counts.ahead
        s.behind = counts.behind
        s.lastScanned = Date()
        if !s.isDirty && s.ahead == 0 { s.pushError = ""; s.pushBlock = "" }
        upsertRepo(s)
    }

    /// Sends one informational summary notification after an auto pass acted, so
    /// the user learns their repos were synced even with the window closed.
    private func notifyAutoSummary(pulled: Int, pushed: Int) {
        guard config.notifications.enabled else { return }
        var parts: [String] = []
        if pushed > 0 { parts.append("pushed \(pushed) repo\(pushed > 1 ? "s" : "")") }
        if pulled > 0 { parts.append("pulled \(pulled) repo\(pulled > 1 ? "s" : "")") }
        guard !parts.isEmpty else { return }
        NotificationService.shared.send(MonitorNotification(
            repoName: "Auto sync",
            message: "Auto-\(parts.joined(separator: ", "))",
            level: .info
        ))
    }

    // MARK: Pull

    /// Manual pull: fast-forwards the repo, records the result, then rescans to
    /// refresh counts. Returns an outcome the caller surfaces as a fading chip.
    @discardableResult
    func pullRepo(at path: String) async -> OpOutcome? {
        let normalizedPath = normalizePath(path)
        // Per-repo gate: allowed even while a full scan runs on OTHER repos — only
        // blocked if this repo is itself being scanned / pulled / pushed.
        guard operations[normalizedPath] == nil, isRepoAvailable(at: normalizedPath) else { return nil }

        clearOpFeedback(at: normalizedPath)
        setOperation(.pulling, for: normalizedPath)
        let result = await performPull(at: normalizedPath)

        var outcome: OpOutcome?
        if var snapshot = repos.first(where: { normalizePath($0.path) == normalizedPath }) {
            switch result {
            case .pulled: snapshot.pullError = ""; outcome = .pulled
            case .upToDate: snapshot.pullError = ""; outcome = .upToDate
            case .failed(let msg): snapshot.pullError = msg
            }
            upsertRepo(snapshot)
        }

        await refreshRepoState(at: normalizedPath)
        setOperation(nil, for: normalizedPath)
        persistCurrentState(lastScanDate: previousState.lastScanDate, lastNotificationDate: previousState.lastNotificationDate)
        return outcome
    }

    /// Runs `git pull --ff-only`. When the pulled repo is RepoMonitor's own
    /// source and the pull advanced it with build-affecting changes, hands off to
    /// `SelfUpdateService` to rebuild and relaunch. The single choke point for
    /// both manual and auto pull.
    private func performPull(at path: String) async -> PullResult {
        let rawRemoteUrl = await gitCli.originRemoteUrl(in: path)
        let selfUpdateCandidate = config.git.selfUpdateEnabled && SelfUpdateService.isSelfRepo(path)
        let preSHA = await gitCli.headSHA(in: path)

        let result = await gitCli.pull(
            in: path,
            remoteURL: rawRemoteUrl,
            credential: credential(forRemoteURL: rawRemoteUrl)
        )
        guard result.success else { return .failed(decoratePullError(result.error)) }

        let postSHA = await gitCli.headSHA(in: path)
        let advanced = !preSHA.isEmpty && !postSHA.isEmpty && preSHA != postSHA
        if selfUpdateCandidate, advanced {
            let changed = await gitCli.changedFiles(in: path, from: preSHA)
            SelfUpdateService.shared.handlePostPull(repoPath: path, changedFiles: changed)
        }
        return advanced ? .pulled : .upToDate
    }

    /// Whether a freshly-scanned snapshot qualifies for auto-pull: behind remote,
    /// no local commits, clean tree, fetched cleanly, not skipped.
    private func isAutoPullEligible(_ s: RepoSnapshot) -> Bool {
        s.behind > 0 && s.ahead == 0 && !s.isDirty && s.fetchSuccess && !s.isSkipped
    }

    /// Auto-pulls one repo inline during the scan (already marked with a
    /// `.pulling` operation by the caller). Returns true if it actually advanced.
    private func autoPull(at repoPath: String) async -> Bool {
        let result = await performPull(at: repoPath)
        switch result {
        case .pulled:
            await refreshRepoState(at: repoPath)
            return true
        case .upToDate:
            await refreshRepoState(at: repoPath)
        case .failed(let msg):
            if var s = repos.first(where: { normalizePath($0.path) == repoPath }) {
                s.pullError = msg
                upsertRepo(s)
            }
        }
        return false
    }

    private func decoratePullError(_ error: String) -> String {
        if error.localizedCaseInsensitiveContains("not possible to fast-forward") {
            return "Cannot fast-forward: local commits diverge from remote. Resolve manually."
        }
        if error.localizedCaseInsensitiveContains("would be overwritten") {
            return "Local uncommitted changes conflict with incoming files. Commit or stash first."
        }
        if error.localizedCaseInsensitiveContains("no tracking information") {
            return "Current branch has no upstream configured."
        }
        return error.isEmpty ? "git pull failed" : error
    }

    // MARK: Push

    /// Manual push: commits any uncommitted changes (with an AI-generated
    /// message) and pushes, records the outcome, then rescans. Returns an outcome
    /// the caller surfaces as a fading chip.
    @discardableResult
    func pushRepo(at path: String) async -> OpOutcome? {
        let normalizedPath = normalizePath(path)
        // Per-repo gate: a manual push works even mid-scan (on other repos) — only
        // blocked if this repo is itself being scanned / pulled / pushed.
        guard operations[normalizedPath] == nil, isRepoAvailable(at: normalizedPath) else { return nil }

        clearOpFeedback(at: normalizedPath)
        let result = await performPush(at: normalizedPath)

        var outcome: OpOutcome?
        if var snapshot = repos.first(where: { normalizePath($0.path) == normalizedPath }) {
            applyPushResult(result, to: &snapshot, outcome: &outcome)
            upsertRepo(snapshot)
        }

        await refreshRepoState(at: normalizedPath)
        setOperation(nil, for: normalizedPath)
        persistCurrentState(lastScanDate: previousState.lastScanDate, lastNotificationDate: previousState.lastNotificationDate)
        return outcome
    }

    /// Maps a `PushResult` onto the snapshot: green success clears everything,
    /// amber "blocked" fills `pushBlock`, red "failed" fills `pushError`.
    private func applyPushResult(_ result: PushResult, to snapshot: inout RepoSnapshot, outcome: inout OpOutcome?) {
        switch result {
        case .pushed:        snapshot.pushError = ""; snapshot.pushBlock = ""; outcome = .pushed
        case .nothingToPush: snapshot.pushError = ""; snapshot.pushBlock = ""; outcome = .nothingToPush
        case .behind:        snapshot.pushError = ""; snapshot.pushBlock = ""; outcome = .behindPullFirst
        case .blocked(let msg): snapshot.pushError = ""; snapshot.pushBlock = msg
        case .failed(let msg):  snapshot.pushError = msg; snapshot.pushBlock = ""
        }
    }

    /// Commits + pushes a single repo, reporting each sub-phase via `operations`.
    /// The single choke point for both manual and auto push.
    ///
    /// Flow: recompute live state → refuse if behind remote → if dirty, stage
    /// everything, run the sensitive-content guard, generate a message and
    /// commit → push. Any abort before the push unstages so the working tree is
    /// left exactly as found.
    private func performPush(at path: String) async -> PushResult {
        setOperation(.pushChecking, for: path)
        let dirty = await gitCli.dirtyStatus(in: path)
        let counts = await gitCli.aheadBehind(in: path)

        // A non-fast-forward push would be rejected; make the user pull first.
        if counts.behind > 0 { return .behind(counts.behind) }

        // Nothing to commit and nothing unpushed — treat as a clean no-op.
        if !dirty.isDirty && counts.ahead == 0 { return .nothingToPush }

        // Pre-push safety gates (git-push-check). Any hit blocks the push.
        let rawRemoteUrl = await gitCli.originRemoteUrl(in: path)
        if GitCLI.embeddedCredential(in: rawRemoteUrl) {
            return .blocked("Push blocked: remote URL embeds a credential. Run `git remote set-url` to remove it before pushing.")
        }
        // The commit identity only matters when we're about to create a commit.
        if dirty.isDirty, let issue = await identityBlock(at: path) {
            return .blocked(issue)
        }

        if dirty.isDirty {
            setOperation(.pushStaging, for: path)
            let staged = await gitCli.stageAll(in: path)
            guard staged.success else {
                await gitCli.unstageAll(in: path)
                return .failed(staged.error.isEmpty ? "git add failed" : staged.error)
            }

            setOperation(.pushChecking, for: path)
            let stagedFiles = await gitCli.stagedFiles(in: path)
            let stagedDiff = await gitCli.stagedDiff(in: path)

            if let reason = SensitiveChangeScanner.blockReason(stagedFiles: stagedFiles, stagedDiff: stagedDiff) {
                await gitCli.unstageAll(in: path)
                return .blocked("Push blocked: \(reason). Resolve manually.")
            }

            setOperation(.pushGenerating, for: path)
            let message: String
            do {
                let repoName = URL(fileURLWithPath: path).lastPathComponent
                message = try await commitMessageGenerator.generate(diff: stagedDiff, repoName: repoName)
            } catch CommitMessageGenerator.GenerationError.cliNotFound {
                await gitCli.unstageAll(in: path)
                return .blocked("Claude CLI not found — cannot generate commit message.")
            } catch {
                await gitCli.unstageAll(in: path)
                return .blocked("Could not generate commit message (Claude unavailable or offline).")
            }

            setOperation(.pushCommitting, for: path)
            let committed = await gitCli.commit(message: message, in: path)
            guard committed.success else {
                await gitCli.unstageAll(in: path)
                return .failed(decoratePushError(committed.error, phase: "commit"))
            }
        }

        setOperation(.pushPushing, for: path)
        let result = await gitCli.push(
            in: path,
            remoteURL: rawRemoteUrl,
            credential: credential(forRemoteURL: rawRemoteUrl)
        )
        guard result.success else { return .failed(decoratePushError(result.error, phase: "push")) }
        return .pushed
    }

    /// Pre-push identity gate: refuses to create a commit when the repo's git
    /// identity is missing or looks machine-auto-generated (e.g. a `.local` /
    /// `.lan` hostname email), which would otherwise be published on the commit.
    /// Returns a block reason, or nil when the identity looks real.
    private func identityBlock(at path: String) async -> String? {
        let name = await gitCli.configValue("user.name", in: path)
        let email = await gitCli.configValue("user.email", in: path)

        if name.isEmpty || email.isEmpty {
            return "Push blocked: git user.name / user.email is not set. Configure them before pushing."
        }
        let lower = email.lowercased()
        let autoGenerated = !email.contains("@")
            || lower.contains("(none)")
            || lower.hasSuffix(".local")
            || lower.hasSuffix(".lan")
            || lower.hasSuffix(".localdomain")
            || lower.hasSuffix("@localhost")
        if autoGenerated {
            return "Push blocked: git identity looks auto-generated (\(email)). Set a real user.email before pushing."
        }
        return nil
    }

    /// Auto push pass: commits + pushes every repo that is dirty or has unpushed
    /// commits, is not behind remote, fetched cleanly, and wasn't skipped. Runs
    /// after any auto-pull. Returns how many were actually pushed.
    private func autoPushPass(targetPaths: [String]) async -> Int {
        var pushed = 0
        for repoPath in targetPaths {
            // Leave a repo the user is manually operating on to that operation.
            guard operations[repoPath] == nil else { continue }
            guard var snapshot = repos.first(where: { normalizePath($0.path) == repoPath }) else { continue }
            guard snapshot.isDirty || snapshot.ahead > 0,
                  snapshot.behind == 0,
                  snapshot.fetchSuccess,
                  !snapshot.isSkipped else { continue }

            progress.currentRepo = snapshot.name
            progress.currentRepoPath = repoPath
            let result = await performPush(at: repoPath)

            var outcome: OpOutcome?
            applyPushResult(result, to: &snapshot, outcome: &outcome)
            upsertRepo(snapshot)
            if case .pushed = result {
                pushed += 1
                await refreshRepoState(at: repoPath)
            }
            setOperation(nil, for: repoPath)
        }
        return pushed
    }

    /// Shared decoration for commit/push stderr into a concise, actionable line.
    private func decoratePushError(_ error: String, phase: String) -> String {
        if error.localizedCaseInsensitiveContains("non-fast-forward")
            || error.localizedCaseInsensitiveContains("fetch first")
            || error.localizedCaseInsensitiveContains("rejected") {
            return "Push rejected: remote has new commits. Pull first."
        }
        if error.localizedCaseInsensitiveContains("no upstream")
            || error.localizedCaseInsensitiveContains("has no upstream branch") {
            return "Current branch has no upstream configured."
        }
        if error.localizedCaseInsensitiveContains("authentication failed")
            || error.localizedCaseInsensitiveContains("could not read")
            || error.localizedCaseInsensitiveContains("permission denied") {
            return "Authentication failed. Add a saved credential in Settings."
        }
        if error.localizedCaseInsensitiveContains("please tell me who you are")
            || error.localizedCaseInsensitiveContains("empty ident") {
            return "Git user.name / user.email not configured for this repo."
        }
        if error.localizedCaseInsensitiveContains("nothing to commit") {
            return "Nothing to commit."
        }
        return error.isEmpty ? "git \(phase) failed" : error
    }

    private func runScan(targetPaths: [String], discoverRemotes: Bool = false) async -> ScanResult {
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

        var autoPulled = 0
        for (index, repoPath) in uniqueTargets.enumerated() {
            // Skip a repo the user is actively pulling/pushing right now — its own
            // operation refreshes it; scanning it concurrently would fight over the
            // same working tree.
            if operations[repoPath] != nil { continue }

            let name = URL(fileURLWithPath: repoPath).lastPathComponent
            progress.current = index + 1
            progress.currentRepo = name
            progress.currentRepoPath = repoPath
            setOperation(.scanning, for: repoPath)

            let previousSnapshot = repos.first(where: { normalizePath($0.path) == repoPath })
            let placeholder = previousSnapshot ?? RepoSnapshot(name: name, path: repoPath)
            upsertRepo(placeholder)

            let snapshot = await scanSnapshot(for: repoPath, previous: placeholder)
            upsertRepo(snapshot)

            if !snapshot.isSkipped, let oldSnapshot = oldReposByPath[repoPath] {
                notifications.append(contentsOf: generateNotifications(old: oldSnapshot, new: snapshot))
            }

            // Inline auto-pull: act on a behind repo the moment it's discovered,
            // instead of waiting for every other repo to finish scanning.
            if config.git.autoPullEnabled, isAutoPullEligible(snapshot) {
                setOperation(.pulling, for: repoPath)
                if await autoPull(at: repoPath) { autoPulled += 1 }
            }

            setOperation(nil, for: repoPath)
        }

        // Push is never automatic during the scan itself; it only runs here when
        // the user has explicitly enabled auto-push, as a separate pass.
        let autoPushed = config.git.autoPushEnabled ? await autoPushPass(targetPaths: uniqueTargets) : 0
        lastAutoPulled = autoPulled
        lastAutoPushed = autoPushed
        if autoPulled > 0 || autoPushed > 0 {
            notifyAutoSummary(pulled: autoPulled, pushed: autoPushed)
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

        // Remote discovery runs after the scan UI has settled so it never holds
        // up the scan; results flow in asynchronously via pendingRemoteRepos.
        if discoverRemotes {
            Task { await self.runRemoteDiscovery() }
        }

        return result
    }

    // MARK: - Remote Discovery & Clone

    /// Lists each mapped account's remote repos and surfaces the ones missing
    /// locally. Failures are swallowed so a flaky network never breaks scanning.
    func runRemoteDiscovery() async {
        guard !isDiscoveringRemotes else { return }
        isDiscoveringRemotes = true
        defer { isDiscoveringRemotes = false }

        let found = await RemoteRepoDiscovery.discover(config: config, repos: repos)
        let ignored = Set(config.git.ignoredRemoteRepos.map { $0.lowercased() })
        pendingRemoteRepos = found.filter { !ignored.contains($0.id.lowercased()) }
    }

    /// Clones a discovered repo into its target folder, then scans it so it
    /// appears in the list. Returns "" on success or a decorated error.
    func cloneRemoteRepo(_ repo: DiscoveredRemoteRepo) async -> String {
        let result = await gitCli.clone(repo.cloneURL, into: repo.targetPath)
        guard result.success else {
            return result.error.isEmpty ? "git clone failed" : result.error
        }
        pendingRemoteRepos.removeAll { $0.id == repo.id }
        _ = await scanRepo(at: repo.targetPath)
        return ""
    }

    /// Removes a repo from the pending list without touching the ignore list
    /// (the caller persists the ignore decision in config).
    func dismissRemoteRepo(id: String) {
        pendingRemoteRepos.removeAll { $0.id == id }
    }

    private func scanSnapshot(for path: String, previous: RepoSnapshot) async -> RepoSnapshot {
        var snapshot = previous
        snapshot.isSkipped = false
        snapshot.fetchSuccess = true
        snapshot.fetchError = ""
        let rawRemoteUrl = await gitCli.originRemoteUrl(in: path)
        let sanitizedRemoteUrl = GitCLI.sanitizeRemoteUrl(rawRemoteUrl)

        if shouldSkip(path) {
            return makeSkippedSnapshot(from: previous)
        }

        let fetchResult = await gitCli.fetch(
            in: path,
            remoteURL: rawRemoteUrl,
            credential: credential(forRemoteURL: rawRemoteUrl)
        )
        if consumeSkip(for: path) {
            return makeSkippedSnapshot(from: previous)
        }
        snapshot.fetchSuccess = fetchResult.success
        // Only keep stderr when the fetch actually failed — git writes benign
        // warnings (e.g. SSH post-quantum notices) to stderr on success too.
        snapshot.fetchError = fetchResult.success ? "" : decorateFetchError(fetchResult.error, remoteURL: rawRemoteUrl)

        snapshot.branch = await gitCli.currentBranch(in: path)
        if consumeSkip(for: path) {
            return makeSkippedSnapshot(from: previous)
        }

        snapshot.upstream = await gitCli.upstream(in: path)
        if consumeSkip(for: path) {
            return makeSkippedSnapshot(from: previous)
        }

        snapshot.remoteUrl = sanitizedRemoteUrl
        if consumeSkip(for: path) {
            return makeSkippedSnapshot(from: previous)
        }

        let dirtyStatus = await gitCli.dirtyStatus(in: path)
        snapshot.isDirty = dirtyStatus.isDirty
        snapshot.modifiedCount = dirtyStatus.modified
        snapshot.untrackedCount = dirtyStatus.untracked
        snapshot.dirtyFiles = dirtyStatus.sampleFiles
        if consumeSkip(for: path) {
            return makeSkippedSnapshot(from: previous)
        }

        let counts = await gitCli.aheadBehind(in: path)
        if consumeSkip(for: path) {
            return makeSkippedSnapshot(from: previous)
        }

        snapshot.ahead = counts.ahead
        snapshot.behind = counts.behind
        if snapshot.behind == 0 {
            // Repo caught up (pulled here or elsewhere) — stale pull errors no longer apply.
            snapshot.pullError = ""
        }
        if !snapshot.isDirty && snapshot.ahead == 0 {
            // Nothing left to commit or push — any prior push feedback is stale.
            snapshot.pushError = ""
            snapshot.pushBlock = ""
        }
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

    private func credential(forRemoteURL remoteURL: String) -> GitCLI.HTTPBasicCredential? {
        guard let host = GitCLI.remoteHost(from: remoteURL) else { return nil }
        guard let entry = config.git.hostCredentials.first(where: { $0.normalizedHost == host }) else { return nil }
        guard let token = GitCredentialStore.token(host: entry.host, username: entry.username) else { return nil }

        return GitCLI.HTTPBasicCredential(username: entry.username, token: token)
    }

    private func decorateFetchError(_ error: String, remoteURL: String) -> String {
        guard !error.isEmpty else { return error }
        guard error.localizedCaseInsensitiveContains("authentication failed")
                || error.localizedCaseInsensitiveContains("cannot prompt because user interactivity has been disabled")
        else {
            return error
        }

        guard let host = GitCLI.remoteHost(from: remoteURL) else { return error }

        if let entry = config.git.hostCredentials.first(where: { $0.normalizedHost == host }),
           !GitCredentialStore.hasToken(host: entry.host, username: entry.username) {
            return "\(error)\nSaved credential for \(host) is missing its token in macOS Keychain."
        }

        if remoteURL.lowercased().hasPrefix("https://") || remoteURL.lowercased().hasPrefix("http://") {
            return "\(error)\nAdd a saved HTTPS credential for \(host) in Settings to avoid interactive auth prompts."
        }

        return error
    }
}
