import Foundation

/// Pre-commit safety gate for the push flow, mirroring the `git-push-check`
/// skill's sensitive-information scan. Given the set of staged files and the
/// staged diff, it flags anything that looks like a secret about to be pushed.
///
/// The push flow treats any hit as a hard stop: the commit is aborted and the
/// working tree is left untouched, so the user resolves it manually rather than
/// leaking credentials to a remote. The rules favour high-signal filename
/// matches plus a conservative added-line content scan to keep false positives
/// from blocking every legitimate push.
enum SensitiveChangeScanner {

    /// Returns a human-readable reason to block the push, or nil when the staged
    /// changes look safe to commit.
    static func blockReason(stagedFiles: [String], stagedDiff: String) -> String? {
        if let file = stagedFiles.first(where: isSensitiveFilename) {
            return "sensitive file staged (\(file))"
        }
        if let hit = firstSecretLine(in: stagedDiff) {
            return "possible secret in staged changes (\(hit))"
        }
        return nil
    }

    // MARK: - Filename rules

    private static func isSensitiveFilename(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        let lowerPath = path.lowercased()

        // Per-machine Claude Code settings must never be committed.
        if lowerPath.hasSuffix(".claude/settings.local.json") { return true }

        // Key material / credential stores by extension.
        let sensitiveExtensions = [".pem", ".key", ".p12", ".pfx", ".keystore", ".jks", ".ppk"]
        if sensitiveExtensions.contains(where: { name.hasSuffix($0) }) {
            // A public key (`.pub`) is safe to share.
            if name.hasSuffix(".pub") { return false }
            return true
        }

        // Well-known credential filenames.
        let sensitiveNames: Set<String> = [
            "credentials", ".netrc", ".npmrc", ".pypirc", ".dockercfg",
            "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", "secrets.json"
        ]
        if sensitiveNames.contains(name) { return true }

        // .env and its variants, but allow templates/examples that carry no real values.
        if name == ".env" { return true }
        if name.hasPrefix(".env.") {
            let allowedSuffixes = ["example", "sample", "template", "dist", "defaults"]
            let suffix = String(name.dropFirst(".env.".count))
            return !allowedSuffixes.contains(suffix)
        }

        return false
    }

    // MARK: - Content rules

    /// Scans added diff lines (those starting with a single `+`) for assignments
    /// whose value looks like a real secret rather than a placeholder.
    private static func firstSecretLine(in diff: String) -> String? {
        let keyPattern = "(password|passwd|secret|token|apikey|api_key|access_key|access_token|private_key|client_secret|authorization|bearer)"
        // key <=/:> "value" — capture the value to judge whether it's real.
        guard let regex = try? NSRegularExpression(
            pattern: "(?i)\(keyPattern)\\s*[:=]\\s*[\"']?([^\"'\\s]+)",
            options: []
        ) else { return nil }

        for rawLine in diff.split(separator: "\n") {
            let line = String(rawLine)
            // Only consider newly added lines; skip the diff's `+++` file header.
            guard line.hasPrefix("+"), !line.hasPrefix("+++") else { continue }
            let content = String(line.dropFirst())

            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            guard let match = regex.firstMatch(in: content, options: [], range: range),
                  match.numberOfRanges >= 3,
                  let valueRange = Range(match.range(at: 2), in: content) else { continue }

            let value = String(content[valueRange])
            if looksLikeRealSecret(value) {
                return content.trimmingCharacters(in: .whitespaces).prefix(80).description
            }
        }
        return nil
    }

    private static func looksLikeRealSecret(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"';,"))
        guard v.count >= 8 else { return false }

        let placeholders = [
            "xxx", "your", "changeme", "placeholder", "example", "dummy",
            "todo", "none", "null", "true", "false", "redacted"
        ]
        let lower = v.lowercased()
        if placeholders.contains(where: { lower.contains($0) }) { return false }
        // Env-var indirection like ${SECRET} or $SECRET is not a literal secret.
        if v.hasPrefix("$") || v.hasPrefix("<") || v.hasPrefix("{{") { return false }
        // Require some entropy: a real key mixes letters and digits/symbols.
        let hasLetter = v.contains(where: { $0.isLetter })
        let hasDigitOrSymbol = v.contains(where: { $0.isNumber || "+/=_-".contains($0) })
        return hasLetter && hasDigitOrSymbol
    }
}
