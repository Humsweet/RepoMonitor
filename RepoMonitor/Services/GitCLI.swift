import Foundation

actor GitCLI {
    struct HTTPBasicCredential {
        let username: String
        let token: String
    }

    private let timeoutSeconds: Int
    private var currentProcess: Process?

    init(timeoutSeconds: Int = 30) {
        self.timeoutSeconds = timeoutSeconds
    }

    struct GitResult {
        let output: String
        let error: String
        let exitCode: Int32
        var success: Bool { exitCode == 0 }
    }

    func run(_ arguments: [String], in directory: String) async throws -> GitResult {
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

        currentProcess = process

        do {
            try process.run()
        } catch {
            currentProcess = nil
            throw error
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task {
                    try await Task.sleep(for: .seconds(timeoutSeconds))
                    if process.isRunning {
                        process.terminate()
                    }
                }

                process.terminationHandler = { [weak stdout, weak stderr] process in
                    timeoutTask.cancel()

                    let outData = stdout?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                    let errData = stderr?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                    let result = GitResult(
                        output: String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        error: String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        exitCode: process.terminationStatus
                    )

                    Task { await self.clearCurrentProcess(process) }
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    func terminateCurrentProcess() {
        currentProcess?.terminate()
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

    func originRemoteUrl(in directory: String) async -> String {
        guard let result = try? await run(["remote", "get-url", "origin"], in: directory),
              result.success else { return "" }
        return result.output
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

    func isDirty(in directory: String) async -> Bool {
        guard let result = try? await run(["status", "--porcelain"], in: directory),
              result.success else { return false }
        return !result.output.isEmpty
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

    private func clearCurrentProcess(_ process: Process) {
        if currentProcess === process {
            currentProcess = nil
        }
    }
}
