import Foundation
import AppKit

/// Rebuilds and relaunches RepoMonitor when a pull brings in changes to its own
/// build-affecting source, archives the superseded bundle, and prunes archives
/// once the successor has run for the confirmation window (30 days).
///
/// This only ever acts on RepoMonitor's own repository — it is the single repo
/// whose build recipe (`scripts/bundle.sh`) the app knows how to run. All state
/// lives in `~/.config/repo-monitor/update-state.json`; the actual on-disk swap
/// is performed by a small detached shell script after the app quits, since a
/// running bundle cannot cleanly replace itself in place.
@MainActor
final class SelfUpdateService {
    static let shared = SelfUpdateService()

    /// Days the newly installed version must have been the running version
    /// before its predecessor archives are deleted.
    private let confirmationWindowDays = 30

    private let fileManager = FileManager.default
    private var isUpdating = false

    private init() {}

    // MARK: - Persisted state

    private struct ArchiveEntry: Codable {
        let version: String
        let build: String
        let path: String
        let archivedAt: Date
    }

    private struct SelfUpdateState: Codable {
        var installedVersion: String
        var installedBuild: String
        var installedAt: Date
        var archives: [ArchiveEntry]
    }

    private enum SelfUpdateError: LocalizedError {
        case missingBuildOutput
        case notRunningFromBundle
        case dittoFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingBuildOutput: return "build produced no app bundle"
            case .notRunningFromBundle: return "not running from an .app bundle"
            case .dittoFailed(let path): return "failed to copy \(path)"
            }
        }
    }

    // MARK: - Paths

    private var archiveDir: URL {
        ConfigLoader.resolveConfigDir().appendingPathComponent("archived-apps")
    }
    private var stagingDir: URL {
        ConfigLoader.resolveConfigDir().appendingPathComponent("staged-update")
    }
    private var stateFile: URL {
        ConfigLoader.resolveConfigDir().appendingPathComponent("update-state.json")
    }

    // MARK: - Classification

    /// A monitored repo is RepoMonitor's own source iff it carries the build
    /// recipe this app knows how to run: a SwiftPM manifest naming the RepoMonitor
    /// product plus `scripts/bundle.sh`. Detected structurally (no hard-coded
    /// path) so it keeps working wherever the repo is checked out.
    static func isSelfRepo(_ path: String) -> Bool {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: path)
        let bundleScript = root.appendingPathComponent("scripts/bundle.sh")
        let manifest = root.appendingPathComponent("Package.swift")
        guard fm.fileExists(atPath: bundleScript.path),
              fm.fileExists(atPath: manifest.path),
              let contents = try? String(contentsOf: manifest, encoding: .utf8) else {
            return false
        }
        return contents.contains("name: \"RepoMonitor\"")
    }

    /// Files whose change alters the built product. Pure docs (`*.md`, LICENSE,
    /// `.gitignore`, etc.) never trigger a rebuild.
    static func isBuildAffecting(_ path: String) -> Bool {
        if path.hasSuffix(".swift") { return true }
        if path == "Package.swift" || path == "Package.resolved" { return true }
        if path.hasPrefix("scripts/") { return true }
        if path.hasPrefix("RepoMonitor/Assets.xcassets/") { return true }
        if path == "RepoMonitor/Info.plist" { return true }
        if path.hasSuffix(".entitlements") { return true }
        return false
    }

    // MARK: - Trigger

    /// Called after a successful pull that advanced RepoMonitor's own repo.
    /// Starts a background rebuild + relaunch if any changed file is
    /// build-affecting. No-ops if an update is already in flight.
    func handlePostPull(repoPath: String, changedFiles: [String]) {
        guard !isUpdating else { return }
        let affected = changedFiles.filter(Self.isBuildAffecting)
        guard !affected.isEmpty else { return }
        isUpdating = true
        Task { await runUpdate(repoPath: repoPath, affectedCount: affected.count) }
    }

    private func runUpdate(repoPath: String, affectedCount: Int) async {
        // Only meaningful when running from an installed .app bundle we can swap.
        // Under `swift run` there is nothing to replace.
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            isUpdating = false
            return
        }

        notify(.info, "Updating",
               "Pulled \(affectedCount) core change(s). Rebuilding RepoMonitor in the background…")

        let build = await buildRelease(in: repoPath)
        guard build.success else {
            notify(.error, "Update failed",
                   "Rebuild failed; keeping the current version. \(build.tail)")
            isUpdating = false
            return
        }

        do {
            let plan = try prepareSwap(repoPath: repoPath)
            try recordState(plan: plan)
            let scriptURL = try writeUpdaterScript(plan: plan)
            notify(.info, "Restarting",
                   "New version \(plan.newVersion) (\(plan.newBuild)) built. RepoMonitor will relaunch now.")
            launchUpdater(scriptURL: scriptURL)
            // Let the notification surface, then quit so the detached updater
            // can archive the old bundle and swap in the new one.
            try? await Task.sleep(for: .seconds(1))
            NSApp.terminate(nil)
        } catch {
            notify(.error, "Update failed",
                   "Could not stage the new version (\(error.localizedDescription)). Keeping the current version.")
            isUpdating = false
        }
    }

    // MARK: - Build

    private struct BuildOutcome {
        let success: Bool
        let tail: String
    }

    private func buildRelease(in repoPath: String) async -> BuildOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [(repoPath as NSString).appendingPathComponent("scripts/bundle.sh")]
                process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

                var env = ProcessInfo.processInfo.environment
                env["REPOMONITOR_SKIP_INSTALL"] = "1"
                // A login-item / Finder-launched app inherits a minimal PATH;
                // make sure swift, codesign, PlistBuddy, ditto all resolve.
                let extraPath = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
                env["PATH"] = env["PATH"].map { "\($0):\(extraPath)" } ?? extraPath
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: BuildOutcome(success: false, tail: error.localizedDescription))
                    return
                }

                // Drain before waiting to avoid filling the pipe buffer.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(data: data, encoding: .utf8) ?? ""
                let tail = output
                    .split(separator: "\n")
                    .suffix(3)
                    .joined(separator: " ")
                continuation.resume(returning: BuildOutcome(success: process.terminationStatus == 0, tail: tail))
            }
        }
    }

    // MARK: - Swap plan

    private struct SwapPlan {
        let installedApp: URL
        let stagedApp: URL
        let archiveApp: URL
        let oldVersion: String
        let oldBuild: String
        let newVersion: String
        let newBuild: String
        let pid: Int32
        let timestamp: String
    }

    /// Stages the freshly built bundle into a neutral location (decoupled from
    /// both the repo's `build/` dir and the running bundle) and computes the
    /// archive destination for the version being replaced.
    private func prepareSwap(repoPath: String) throws -> SwapPlan {
        let built = URL(fileURLWithPath: repoPath).appendingPathComponent("build/RepoMonitor.app")
        guard fileManager.fileExists(atPath: built.path) else {
            throw SelfUpdateError.missingBuildOutput
        }

        let installedApp = Bundle.main.bundleURL
        guard installedApp.pathExtension == "app" else {
            throw SelfUpdateError.notRunningFromBundle
        }

        try? fileManager.removeItem(at: stagingDir)
        try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stagedApp = stagingDir.appendingPathComponent("RepoMonitor.app")
        try ditto(built, stagedApp)

        let (oldV, oldB) = bundleVersion(at: installedApp)
        let (newV, newB) = bundleVersion(at: stagedApp)

        let ts = Self.timestampString()
        try fileManager.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        let archiveName = "RepoMonitor-\(oldV.isEmpty ? "unknown" : oldV)-\(oldB.isEmpty ? "0" : oldB)-\(ts).app"
        let archiveApp = archiveDir.appendingPathComponent(archiveName)

        return SwapPlan(
            installedApp: installedApp,
            stagedApp: stagedApp,
            archiveApp: archiveApp,
            oldVersion: oldV,
            oldBuild: oldB,
            newVersion: newV,
            newBuild: newB,
            pid: ProcessInfo.processInfo.processIdentifier,
            timestamp: ts
        )
    }

    private func recordState(plan: SwapPlan) throws {
        var archives = loadState()?.archives ?? []
        archives.append(ArchiveEntry(
            version: plan.oldVersion,
            build: plan.oldBuild,
            path: plan.archiveApp.path,
            archivedAt: Date()
        ))
        let state = SelfUpdateState(
            installedVersion: plan.newVersion,
            installedBuild: plan.newBuild,
            installedAt: Date(),
            archives: archives
        )
        try saveState(state)
    }

    /// Writes the detached swap script. It waits for the app to quit, archives
    /// the currently installed bundle, moves the staged bundle into place, and
    /// relaunches. Signatures are preserved by `ditto`.
    private func writeUpdaterScript(plan: SwapPlan) throws -> URL {
        let script = """
        #!/bin/bash
        # RepoMonitor self-update swap — runs detached after the app quits.
        PID=\(plan.pid)
        INSTALLED=\(shellQuote(plan.installedApp.path))
        STAGED=\(shellQuote(plan.stagedApp.path))
        ARCHIVE=\(shellQuote(plan.archiveApp.path))

        # Wait up to ~60s for the running app to exit.
        for _ in $(seq 1 120); do
          /bin/kill -0 "$PID" 2>/dev/null || break
          /bin/sleep 0.5
        done

        if [ -d "$INSTALLED" ]; then
          /usr/bin/ditto "$INSTALLED" "$ARCHIVE" || exit 1
          /bin/rm -rf "$INSTALLED"
        fi
        /usr/bin/ditto "$STAGED" "$INSTALLED" || exit 1
        /bin/rm -rf "$STAGED"
        /usr/bin/open "$INSTALLED"
        """
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("repomonitor-update-\(plan.timestamp).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func launchUpdater(scriptURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        // Detached: not waited on. It survives our termination and is reparented
        // to launchd, then swaps the bundle and relaunches.
        try? process.run()
    }

    // MARK: - Startup maintenance

    /// Prunes archived bundles once the running version has been the installed
    /// version for the confirmation window. Also clears leftover staging and
    /// drops manifest entries whose files are gone. Call shortly after launch
    /// (delayed) so a crash-looping bad version never deletes its own rollback.
    func performStartupMaintenance() {
        // A completed swap already consumed staging; remove any leftovers.
        try? fileManager.removeItem(at: stagingDir)

        guard var state = loadState() else { return }

        // Drop dangling manifest entries (archive deleted out-of-band).
        state.archives.removeAll { !fileManager.fileExists(atPath: $0.path) }

        let (runVersion, runBuild) = Self.runningBundleVersion()
        let isConfirmedRunning = runVersion == state.installedVersion && runBuild == state.installedBuild
        let elapsed = Date().timeIntervalSince(state.installedAt)
        let windowSeconds = TimeInterval(confirmationWindowDays * 24 * 60 * 60)

        if isConfirmedRunning && elapsed >= windowSeconds {
            for entry in state.archives {
                try? fileManager.removeItem(atPath: entry.path)
            }
            state.archives.removeAll()
        }

        try? saveState(state)
    }

    // MARK: - Helpers

    private func loadState() -> SelfUpdateState? {
        guard let data = try? Data(contentsOf: stateFile) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SelfUpdateState.self, from: data)
    }

    private func saveState(_ state: SelfUpdateState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try fileManager.createDirectory(at: ConfigLoader.resolveConfigDir(), withIntermediateDirectories: true)
        try encoder.encode(state).write(to: stateFile, options: .atomic)
    }

    private static func runningBundleVersion() -> (String, String) {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleShortVersionString"] as? String ?? "",
                info?["CFBundleVersion"] as? String ?? "")
    }

    /// Reads version strings straight from a bundle's `Contents/Info.plist` to
    /// avoid `Bundle` caching of a just-staged bundle.
    private func bundleVersion(at appURL: URL) -> (String, String) {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return ("", "")
        }
        return (dict["CFBundleShortVersionString"] as? String ?? "",
                dict["CFBundleVersion"] as? String ?? "")
    }

    private func ditto(_ src: URL, _ dst: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [src.path, dst.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw SelfUpdateError.dittoFailed(dst.lastPathComponent)
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private func notify(_ level: MonitorNotification.NotificationLevel, _ phase: String, _ message: String) {
        NotificationService.shared.send(
            MonitorNotification(repoName: "RepoMonitor · \(phase)", message: message, level: level)
        )
    }
}
