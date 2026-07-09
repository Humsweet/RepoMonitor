import Foundation

/// Generates a Git commit message by summarising a staged diff with Claude
/// Code's latest Haiku model, run headlessly (`claude -p … --model haiku`).
///
/// The app is launched from Finder/login items, where PATH is minimal, so the
/// `claude` binary is located from a fixed set of install locations rather than
/// relying on `which` — the same strategy used to find the VS Code CLI.
actor CommitMessageGenerator {

    enum GenerationError: Error {
        /// The `claude` executable could not be found on this machine.
        case cliNotFound
        /// The CLI ran but produced no usable message (offline, auth, timeout…).
        case emptyOutput
    }

    /// Cap the diff sent to the model so a huge changeset never blows up the
    /// prompt; a truncated view is plenty to summarise the intent.
    private let maxDiffChars = 16_000
    private let timeoutSeconds: TimeInterval = 60

    /// Produces a single-line, English, imperative commit subject for `diff`.
    /// Throws `GenerationError` when no message can be obtained — the caller
    /// then aborts the push rather than committing a placeholder.
    func generate(diff: String, repoName: String) async throws -> String {
        guard let cli = Self.locateClaude() else { throw GenerationError.cliNotFound }

        let truncated = diff.count > maxDiffChars
            ? String(diff.prefix(maxDiffChars)) + "\n…[diff truncated]…"
            : diff

        let prompt = """
        You are writing a git commit message. Summarise the following staged diff \
        as ONE concise, imperative English commit subject line (max ~72 chars). \
        Output ONLY the message text — no quotes, no code fences, no explanation, \
        no leading "commit:" label.

        Repository: \(repoName)

        Diff:
        \(truncated)
        """

        let output = try await runClaude(cli: cli, prompt: prompt)
        let message = sanitize(output)
        guard !message.isEmpty else { throw GenerationError.emptyOutput }
        return message
    }

    // MARK: - Process

    private func runClaude(cli: URL, prompt: String) async throws -> String {
        let process = Process()
        process.executableURL = cli
        process.arguments = ["-p", prompt, "--model", "haiku", "--output-format", "text"]

        // Give the child a sane PATH/HOME so it can find its own runtime and the
        // logged-in credentials under ~/.claude, which a Finder-launched app
        // otherwise lacks.
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        env["HOME"] = home
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.claude/local"]
        let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPaths + [existing]).joined(separator: ":")
        process.environment = env

        // Pin the child to a dedicated working directory. Claude Code records a
        // transcript under `~/.claude/projects/<cwd>` even in headless `-p` mode;
        // without this the process inherits the app's cwd (typically `/` for a
        // Finder-launched app), scattering these throwaway commit-message runs
        // into the root project folder. A stable, recognisable directory keeps
        // them isolated so tooling can filter them out by path.
        process.currentDirectoryURL = Self.commitMessageWorkingDirectory()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw GenerationError.cliNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                if process.isRunning { process.terminate() }
            }
            process.terminationHandler = { [weak stdout] process in
                timeoutTask.cancel()
                let data = stdout?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                let text = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: GenerationError.emptyOutput)
                }
            }
        }
    }

    /// Collapses the model output into a single clean subject line, stripping
    /// stray quoting/fencing the model may add despite the instructions.
    private func sanitize(_ raw: String) -> String {
        var line = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .first
            .map(String.init) ?? ""
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop surrounding backticks/quotes if the model wrapped the message.
        let trimSet = CharacterSet(charactersIn: "`\"'")
        line = line.trimmingCharacters(in: trimSet)
        return line
    }

    // MARK: - Working directory

    /// A dedicated, stable working directory for the headless `claude` process,
    /// living alongside RepoMonitor's other state under `~/.config/repo-monitor/`.
    /// Created on demand so the process launch never fails on a missing cwd.
    private static func commitMessageWorkingDirectory() -> URL {
        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/repo-monitor/commit-msg", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Locate binary

    private static func locateClaude() -> URL? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.local/bin/claude"
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
