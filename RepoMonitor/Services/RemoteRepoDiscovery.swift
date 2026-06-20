import Foundation

/// Discovers repositories that exist on the user's remote accounts but have no
/// local clone in the folder mapped to that account.
///
/// The account → folder → clone-style mapping is *derived* from the remotes of
/// the repos already on disk (single source of truth), so no personal account
/// names or paths are hardcoded in source. For each `children` scan root, the
/// dominant (provider, owner, clone style) among its child repos becomes that
/// folder's account.
enum RemoteRepoDiscovery {

    struct ParsedRemote {
        let provider: RepoProvider
        let host: String        // real API host (github.com / bitbucket.org)
        let owner: String
        let name: String
        let sshAlias: String?   // SSH host (possibly an alias) if SSH form; nil for https

        /// Same shape as `DiscoveredRemoteRepo.id` so the two compare directly.
        var id: String { "\(host.lowercased())/\(owner.lowercased())/\(name.lowercased())" }
    }

    struct DerivedAccount {
        let provider: RepoProvider
        let host: String
        let owner: String
        let folder: String      // expanded destination folder
        let sshAlias: String?

        /// Builds a clone URL for `name` matching the folder's existing convention.
        func cloneURL(for name: String) -> String {
            if let alias = sshAlias {
                return "git@\(alias):\(owner)/\(name).git"
            }
            return "https://\(host)/\(owner)/\(name).git"
        }
    }

    struct RemoteListing {
        let name: String
        let isPrivate: Bool
        let summary: String
    }

    // MARK: - Entry point

    static func discover(config: MonitorConfig, repos: [RepoSnapshot]) async -> [DiscoveredRemoteRepo] {
        let accounts = deriveAccounts(config: config, repos: repos)
        guard !accounts.isEmpty else { return [] }

        let ignored = Set(config.git.ignoredRemoteRepos.map { $0.lowercased() })
        // A remote repo is "already present" if RepoMonitor already tracks it at
        // ANY monitored location — not just inside the mapped folder. This keeps
        // repos like ~/dotfiles (a self root living outside the Personal folder)
        // from being offered for cloning when they're already being watched.
        let monitoredIDs = Set(repos.compactMap { parse($0.remoteUrl) }.map(\.id))
        let fm = FileManager.default
        var discovered: [DiscoveredRemoteRepo] = []

        for account in accounts {
            let remote: [RemoteListing]
            switch account.provider {
            case .github:
                remote = await GitHubLister.ownedRepos(owner: account.owner)
            case .bitbucket:
                remote = await BitbucketLister.workspaceRepos(workspace: account.owner, config: config)
            }

            for listing in remote {
                let candidate = DiscoveredRemoteRepo(
                    provider: account.provider,
                    host: account.host,
                    owner: account.owner,
                    name: listing.name,
                    cloneURL: account.cloneURL(for: listing.name),
                    targetFolder: account.folder,
                    isPrivate: listing.isPrivate,
                    summary: listing.summary
                )
                if monitoredIDs.contains(candidate.id) { continue }
                if ignored.contains(candidate.id) { continue }
                // A folder already at the target means it's effectively present.
                if fm.fileExists(atPath: candidate.targetPath) { continue }
                discovered.append(candidate)
            }
        }

        var seen = Set<String>()
        return discovered
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Account derivation

    static func deriveAccounts(config: MonitorConfig, repos: [RepoSnapshot]) -> [DerivedAccount] {
        var result: [DerivedAccount] = []

        for root in config.roots where root.mode == .children {
            let folder = (root.path as NSString).expandingTildeInPath
            let children = repos.filter {
                ($0.path as NSString).deletingLastPathComponent == folder
            }

            var tally: [String: (count: Int, parsed: ParsedRemote)] = [:]
            for repo in children {
                guard let parsed = parse(repo.remoteUrl) else { continue }
                let key = "\(parsed.provider.rawValue)|\(parsed.owner.lowercased())|\(parsed.sshAlias ?? parsed.host)"
                if let existing = tally[key] {
                    tally[key] = (existing.count + 1, existing.parsed)
                } else {
                    tally[key] = (1, parsed)
                }
            }

            guard let top = tally.values.max(by: { $0.count < $1.count }) else { continue }
            result.append(DerivedAccount(
                provider: top.parsed.provider,
                host: top.parsed.host,
                owner: top.parsed.owner,
                folder: folder,
                sshAlias: top.parsed.sshAlias
            ))
        }

        return result
    }

    // MARK: - Remote URL parsing

    static func parse(_ raw: String) -> ParsedRemote? {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }

        // SCP-like SSH form: user@host:owner/name(.git)
        if !url.contains("://"), url.contains("@"), url.contains(":") {
            guard let atIdx = url.firstIndex(of: "@") else { return nil }
            let afterAt = url[url.index(after: atIdx)...]
            guard let colonIdx = afterAt.firstIndex(of: ":") else { return nil }
            let host = String(afterAt[..<colonIdx])
            let path = String(afterAt[afterAt.index(after: colonIdx)...])
            guard let (owner, name) = ownerName(path),
                  let provider = provider(forHost: host) else { return nil }
            return ParsedRemote(provider: provider, host: realHost(provider), owner: owner, name: name, sshAlias: host)
        }

        // HTTP(S) form
        if let comps = URLComponents(string: url), let host = comps.host {
            guard let (owner, name) = ownerName(comps.path),
                  let provider = provider(forHost: host) else { return nil }
            return ParsedRemote(provider: provider, host: host, owner: owner, name: name, sshAlias: nil)
        }

        return nil
    }

    private static func ownerName(_ rawPath: String) -> (owner: String, name: String)? {
        let trimmed = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        var name = parts[parts.count - 1]
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        guard !owner.isEmpty, !name.isEmpty else { return nil }
        return (owner, name)
    }

    private static func provider(forHost host: String) -> RepoProvider? {
        let h = host.lowercased()
        if h.contains("bitbucket") { return .bitbucket }
        if h.contains("github") { return .github }
        return nil
    }

    private static func realHost(_ provider: RepoProvider) -> String {
        switch provider {
        case .github: return "github.com"
        case .bitbucket: return "bitbucket.org"
        }
    }
}

// MARK: - GitHub listing (reuses gh CLI logins)

private enum GitHubLister {
    static func ownedRepos(owner: String) async -> [RemoteRepoDiscovery.RemoteListing] {
        guard let token = ghToken(forUser: owner) else { return [] }

        var out: [RemoteRepoDiscovery.RemoteListing] = []
        var page = 1
        while page <= 10 {
            guard let url = URL(string: "https://api.github.com/user/repos?affiliation=owner&per_page=100&page=\(page)") else { break }
            var req = URLRequest(url: url)
            req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("RepoMonitor", forHTTPHeaderField: "User-Agent")

            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { break }
            if arr.isEmpty { break }

            for item in arr {
                let fork = item["fork"] as? Bool ?? false
                let archived = item["archived"] as? Bool ?? false
                if fork || archived { continue }
                let login = (item["owner"] as? [String: Any])?["login"] as? String ?? ""
                guard login.lowercased() == owner.lowercased() else { continue }
                guard let name = item["name"] as? String else { continue }
                out.append(.init(
                    name: name,
                    isPrivate: item["private"] as? Bool ?? false,
                    summary: item["description"] as? String ?? ""
                ))
            }

            if arr.count < 100 { break }
            page += 1
        }
        return out
    }

    /// Reads the stored gh token for a specific account, falling back to the
    /// active account. Returns nil if gh isn't installed or has no token.
    private static func ghToken(forUser user: String) -> String? {
        guard let gh = resolveGh() else { return nil }
        if let token = runGh(gh, ["auth", "token", "--user", user]), !token.isEmpty { return token }
        if let token = runGh(gh, ["auth", "token"]), !token.isEmpty { return token }
        return nil
    }

    private static func resolveGh() -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func runGh(_ gh: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Bitbucket listing (uses the app's saved app password)

private enum BitbucketLister {
    static func workspaceRepos(workspace: String, config: MonitorConfig) async -> [RemoteRepoDiscovery.RemoteListing] {
        guard let cred = config.git.hostCredentials.first(where: { $0.normalizedHost == "bitbucket.org" }),
              let token = GitCredentialStore.token(host: cred.host, username: cred.username) else {
            return []
        }
        let auth = Data("\(cred.username):\(token)".utf8).base64EncodedString()

        var next: URL? = URL(string: "https://api.bitbucket.org/2.0/repositories/\(workspace)?pagelen=100&role=member")
        var out: [RemoteRepoDiscovery.RemoteListing] = []
        var pages = 0

        while let url = next, pages < 20 {
            pages += 1
            var req = URLRequest(url: url)
            req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }

            let values = obj["values"] as? [[String: Any]] ?? []
            for v in values {
                // Bitbucket workspaces here are entirely forks of upstream company
                // repos — i.e. forks ARE the working repos — so forks are kept.
                let name = (v["slug"] as? String) ?? (v["name"] as? String) ?? ""
                guard !name.isEmpty else { continue }
                out.append(.init(
                    name: name,
                    isPrivate: v["is_private"] as? Bool ?? false,
                    summary: v["description"] as? String ?? ""
                ))
            }

            if let nextStr = obj["next"] as? String { next = URL(string: nextStr) } else { next = nil }
        }
        return out
    }
}
