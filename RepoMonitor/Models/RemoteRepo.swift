import Foundation

enum RepoProvider: String, Codable {
    case github
    case bitbucket
}

/// A repository that exists on a remote account but has no local clone in the
/// folder mapped to that account. Surfaced in the new-repo review sheet.
struct DiscoveredRemoteRepo: Identifiable, Equatable {
    let provider: RepoProvider
    let host: String        // real API host, e.g. github.com / bitbucket.org
    let owner: String       // owner / workspace, e.g. formyvibecoding
    let name: String
    let cloneURL: String     // built to match the folder's existing clone style
    let targetFolder: String // expanded destination folder
    let isPrivate: Bool
    let summary: String      // short description, may be empty

    /// Stable identity used for ignore-list membership and dedup.
    var id: String { "\(host.lowercased())/\(owner.lowercased())/\(name.lowercased())" }

    /// Full path the repo would be cloned to.
    var targetPath: String {
        (targetFolder as NSString).appendingPathComponent(name)
    }
}
