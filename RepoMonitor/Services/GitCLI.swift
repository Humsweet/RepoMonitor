import Foundation

actor GitCLI {
    struct HTTPBasicCredential {
        let username: String
        let token: String
    }

    private let timeoutSeconds: Int
    /// Every git subprocess currently in flight, keyed by identity. A single
    /// slot could only represent one process, so parallel scans need the whole
    /// set — both to avoid clobbering the field and to terminate them all at
    /// once when the user hits "Stop Scan".
    private var runningProcesses: [ObjectIdentifier: Process] = [:]

    init(timeoutSeconds: Int = 30) {
        self.timeoutSeconds = timeoutSeconds
    }

    struct GitResult {
        let output: String
        let error: String
        let exitCode: Int32
        var success: Bool { exitCode == 0 }
    }

    func run(_ arguments: [String], in directory: String, timeoutOverride: Int? = nil) async throws -> GitResult {
        let effectiveTimeout = timeoutOverride ?? timeoutSeconds
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = "/bin/echo"
        env["SSH_ASKPASS"] = "/bin/echo"
        env["SSH_ASKPASS_REQUIRE"] = "never"
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
        env["GCM_INTERACTIVE"] = "Never"
        env["GCM_MODAL_PROMPT"] = "false"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw error
        }

        let key = ObjectIdentifier(process)
        runningProcesses[key] = process
        defer { runningProcesses[key] = nil }

        // Drain both pipes on background queues *while the process runs*, so a
        // large amount of output can never fill the ~64 KB OS pipe buffer and
        // deadlock the child (which would then hang until the timeout kills it).
        // The old code read only inside the termination handler; that was safe
        // only because fetch/pull output is small — concurrent scans make big
        // output far likelier, so we drain continuously instead.
        async let outData = Self.readToEnd(stdout.fileHandleForReading)
        async let errData = Self.readToEnd(stderr.fileHandleForReading)

        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                let timeoutTask = Task {
                    try? await Task.sleep(for: .seconds(effectiveTimeout))
                    if process.isRunning { process.terminate() }
                }
                process.terminationHandler = { process in
                    timeoutTask.cancel()
                    continuation.resume(returning: process.terminationStatus)
                }
            }
        } onCancel: {
            process.terminate()
        }

        return GitResult(
            output: String(data: await outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            error: String(data: await errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            exitCode: exitCode
        )
    }

    /// Reads a pipe to EOF on a background queue. `readDataToEndOfFile` blocks
    /// until the child closes its write end (i.e. exits), but drains the buffer
    /// continuously as bytes arrive — so it never back-pressures the child.
    /// `nonisolated` so the blocking read runs off the actor.
    private nonisolated static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = handle.readDataToEndOfFile()
                continuation.resume(returning: data)
            }
        }
    }

    /// Terminates every in-flight git subprocess. Used by "Stop Scan" to abort a
    /// parallel scan at once instead of waiting for each fetch to finish.
    func terminateAllRunning() {
        for process in runningProcesses.values { process.terminate() }
    }

    func fetch(
        in directory: String,
        remoteURL: String = "",
        credential: HTTPBasicCredential? = nil
    ) async -> (success: Bool, error: String) {
        do {
            var arguments: [String] = []
            if let configOverride = Self.fetchAuthorizationConfig(remoteURL: remoteURL, credential: credential) {
                arguments += ["-c", configOverride]
            }
            arguments += ["fetch", "origin", "--prune"]

            let result = try await run(arguments, in: directory)
            return (result.success, result.error)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func pull(
        in directory: String,
        remoteURL: String = "",
        credential: HTTPBasicCredential? = nil
    ) async -> (success: Bool, error: String) {
        do {
            var arguments: [String] = []
            if let configOverride = Self.fetchAuthorizationConfig(remoteURL: remoteURL, credential: credential) {
                arguments += ["-c", configOverride]
            }
            arguments += ["pull", "--ff-only"]

            let result = try await run(arguments, in: directory)
            return (result.success, result.error)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func push(
        in directory: String,
        remoteURL: String = "",
        credential: HTTPBasicCredential? = nil
    ) async -> (success: Bool, error: String) {
        do {
            var arguments: [String] = []
            if let configOverride = Self.fetchAuthorizationConfig(remoteURL: remoteURL, credential: credential) {
                arguments += ["-c", configOverride]
            }
            arguments += ["push"]

            let result = try await run(arguments, in: directory)
            return (result.success, result.error)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Commit primitives (used by the push flow)

    /// Stages every change in the working tree (tracked modifications,
    /// deletions, and untracked files) via `git add -A`.
    func stageAll(in directory: String) async -> (success: Bool, error: String) {
        guard let result = try? await run(["add", "-A"], in: directory) else {
            return (false, "git add failed")
        }
        return (result.success, result.error)
    }

    /// Unstages everything (`git reset`). Called to roll back after `stageAll`
    /// when the push is aborted (sensitive content, message generation failure)
    /// so the working tree is left exactly as it was found.
    func unstageAll(in directory: String) async {
        _ = try? await run(["reset"], in: directory)
    }

    /// Full diff of what is currently staged (`git diff --cached`). Feeds both
    /// the sensitive-content guard and the commit-message generator.
    func stagedDiff(in directory: String) async -> String {
        guard let result = try? await run(["diff", "--cached"], in: directory),
              result.success else { return "" }
        return result.output
    }

    /// Repo-relative paths of currently staged files (`git diff --cached --name-only`).
    func stagedFiles(in directory: String) async -> [String] {
        guard let result = try? await run(["diff", "--cached", "--name-only"], in: directory),
              result.success else { return [] }
        return result.output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func commit(message: String, in directory: String) async -> (success: Bool, error: String) {
        guard let result = try? await run(["commit", "-m", message], in: directory) else {
            return (false, "git commit failed")
        }
        return (result.success, result.error.isEmpty ? result.output : result.error)
    }

    /// Clones `url` into `destination`. Uses a long timeout since clones of
    /// large repos take far longer than a fetch. SSH auth runs in BatchMode, so
    /// the user's existing key/alias setup is honoured without prompts.
    func clone(_ url: String, into destination: String) async -> (success: Bool, error: String) {
        let parent = (destination as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        do {
            let result = try await run(["clone", url, destination], in: parent, timeoutOverride: 600)
            return (result.success, result.error)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func originRemoteUrl(in directory: String) async -> String {
        guard let result = try? await run(["remote", "get-url", "origin"], in: directory),
              result.success else { return "" }
        return result.output
    }

    /// Reads a single git config value ("" if unset). Used by the pre-push
    /// safety gates to inspect the commit identity.
    func configValue(_ key: String, in directory: String) async -> String {
        guard let result = try? await run(["config", "--get", key], in: directory),
              result.success else { return "" }
        return result.output
    }

    /// True when an http(s) remote URL embeds a username/password (e.g.
    /// `https://user:token@host/…`) — a credential that should be moved out of
    /// `.git/config` before pushing. SSH `git@host:…` forms are not flagged.
    static func embeddedCredential(in remoteURL: String) -> Bool {
        guard let url = URL(string: remoteURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return url.user != nil || url.password != nil
    }

    func currentBranch(in directory: String) async -> String {
        guard let result = try? await run(["rev-parse", "--abbrev-ref", "HEAD"], in: directory),
              result.success else { return "" }
        return result.output
    }

    func upstream(in directory: String) async -> String {
        guard let result = try? await run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: directory),
              result.success else { return "" }
        return result.output
    }

    func remoteUrl(in directory: String) async -> String {
        Self.sanitizeRemoteUrl(await originRemoteUrl(in: directory))
    }

    struct DirtyStatus {
        let modified: Int
        let untracked: Int
        let sampleFiles: [String]

        var isDirty: Bool { modified > 0 || untracked > 0 }
    }

    /// Mirrors VS Code's git extension: untracked (non-ignored) files count as
    /// changes like tracked modifications, but untracked directories that are
    /// themselves git repositories (nested repos / worktrees) are excluded —
    /// VS Code treats those as separate repositories, not parent-repo changes.
    func dirtyStatus(in directory: String) async -> DirtyStatus {
        guard let result = try? await run(["status", "--porcelain", "-uall"], in: directory),
              result.success, !result.output.isEmpty else {
            return DirtyStatus(modified: 0, untracked: 0, sampleFiles: [])
        }

        let fm = FileManager.default
        var modified = 0
        var untracked = 0
        var samples: [String] = []
        for line in result.output.split(separator: "\n") {
            let path = String(line.dropFirst(3))
            if line.hasPrefix("??") {
                // `-uall` only emits a bare directory entry when it cannot
                // descend into it, i.e. a nested git repo/worktree. Skip those.
                if path.hasSuffix("/") {
                    let gitMarker = ((directory as NSString)
                        .appendingPathComponent(path) as NSString)
                        .appendingPathComponent(".git")
                    if fm.fileExists(atPath: gitMarker) { continue }
                }
                untracked += 1
            } else {
                modified += 1
            }
            if samples.count < 5 {
                samples.append(path)
            }
        }
        return DirtyStatus(modified: modified, untracked: untracked, sampleFiles: samples)
    }

    /// Current HEAD commit SHA ("" on failure). Used by self-update to detect
    /// whether a pull actually advanced the local repo.
    func headSHA(in directory: String) async -> String {
        guard let result = try? await run(["rev-parse", "HEAD"], in: directory),
              result.success else { return "" }
        return result.output
    }

    /// Paths (repo-relative) that changed between `oldSHA` and the current HEAD.
    func changedFiles(in directory: String, from oldSHA: String) async -> [String] {
        guard !oldSHA.isEmpty,
              let result = try? await run(["diff", "--name-only", "\(oldSHA)..HEAD"], in: directory),
              result.success else { return [] }
        return result.output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func aheadBehind(in directory: String) async -> (ahead: Int, behind: Int) {
        guard let result = try? await run(["rev-list", "--left-right", "--count", "HEAD...@{u}"], in: directory),
              result.success else { return (0, 0) }

        let parts = result.output.split(separator: "\t")
        guard parts.count == 2,
              let ahead = Int(parts[0]),
              let behind = Int(parts[1]) else { return (0, 0) }
        return (ahead, behind)
    }

    static func sanitizeRemoteUrl(_ url: String) -> String {
        // Remove credentials from URLs like https://user:token@github.com/...
        guard let urlObj = URL(string: url),
              urlObj.user != nil || urlObj.password != nil else { return url }
        var components = URLComponents(url: urlObj, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        return components?.string ?? url
    }

    static func remoteHost(from remoteURL: String) -> String? {
        let sanitized = sanitizeRemoteUrl(remoteURL)

        if let url = URL(string: sanitized), let host = url.host {
            return host.lowercased()
        }

        guard let atIndex = sanitized.firstIndex(of: "@"),
              let colonIndex = sanitized[atIndex...].firstIndex(of: ":"),
              sanitized.index(after: atIndex) < colonIndex else {
            return nil
        }

        return String(sanitized[sanitized.index(after: atIndex)..<colonIndex]).lowercased()
    }

    private static func fetchAuthorizationConfig(
        remoteURL: String,
        credential: HTTPBasicCredential?
    ) -> String? {
        guard let credential else { return nil }

        let sanitized = sanitizeRemoteUrl(remoteURL)
        guard let url = URL(string: sanitized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }

        let auth = Data("\(credential.username):\(credential.token)".utf8).base64EncodedString()
        return "http.\(sanitized).extraHeader=Authorization: Basic \(auth)"
    }

}
