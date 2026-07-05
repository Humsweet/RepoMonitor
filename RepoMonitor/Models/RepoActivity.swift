import Foundation

/// What a repo is actively doing right now. Purely transient (never persisted);
/// drives the in-progress spinner + status text on the row and in the bottom
/// bar so pull/push never look frozen while git and Claude do their work.
enum RepoOperation: Equatable {
    case scanning
    case pulling
    case pushStaging
    case pushChecking      // sensitive-content guard
    case pushGenerating    // Claude commit-message generation (the slow step)
    case pushCommitting
    case pushPushing

    var isPush: Bool {
        switch self {
        case .scanning, .pulling: return false
        default: return true
        }
    }

    /// Short label for the in-progress chip in the Status column. Each push
    /// sub-step keeps its own label — surfacing exactly which phase is running
    /// (staging → secret-scan → commit message → commit → push) is the point.
    var chip: String {
        switch self {
        case .scanning: return "Scanning…"
        case .pulling: return "Pulling…"
        case .pushStaging: return "Preparing…"
        case .pushChecking: return "Checking…"
        case .pushGenerating: return "Writing message…"
        case .pushCommitting: return "Committing…"
        case .pushPushing: return "Pushing…"
        }
    }

    /// Verb for the bottom-bar phrase ("<verb> <repo> — <detail>").
    var verb: String {
        switch self {
        case .scanning: return "Scanning"
        case .pulling: return "Pulling"
        default: return "Pushing"
        }
    }

    /// Extra detail appended in the bottom bar for the slower push sub-steps.
    var detail: String {
        switch self {
        case .pushStaging: return "staging changes"
        case .pushChecking: return "scanning for secrets"
        case .pushGenerating: return "writing commit message"
        case .pushCommitting: return "committing"
        case .pushPushing: return "pushing to remote"
        default: return ""
        }
    }
}

/// The result of a completed manual pull/push, surfaced as a brief fading chip
/// so the user gets positive confirmation instead of the row silently changing.
enum OpOutcome: Equatable {
    case pushed
    case pulled
    case upToDate
    case nothingToPush
    case behindPullFirst

    var chip: String {
        switch self {
        case .pushed: return "Pushed"
        case .pulled: return "Pulled"
        case .upToDate: return "Up to date"
        case .nothingToPush: return "Nothing to push"
        case .behindPullFirst: return "Pull first"
        }
    }

    /// Positive outcomes read green with a filled check; advisory outcomes read
    /// neutral so "nothing to do" never looks like success or failure.
    var isPositive: Bool {
        switch self {
        case .pushed, .pulled, .upToDate: return true
        case .nothingToPush, .behindPullFirst: return false
        }
    }

    var icon: String {
        switch self {
        case .pushed: return "checkmark.circle.fill"
        case .pulled: return "checkmark.circle.fill"
        case .upToDate: return "checkmark.circle"
        case .nothingToPush: return "checkmark.circle"
        case .behindPullFirst: return "arrow.down.circle"
        }
    }

    /// How long the chip lingers before fading (seconds).
    var lingerSeconds: Double { 5 }
}
