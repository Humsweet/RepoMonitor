import SwiftUI

struct RepoDetailView: View {
    let repo: RepoSnapshot
    let isScanning: Bool
    let onScan: () -> Void
    let onOpenTerminal: () -> Void
    let onOpenVSCode: () -> Void
    let onOpenFinder: () -> Void
    let onUnwatch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.statusColor(for: repo.statusLevel))
                    .frame(width: 10, height: 10)

                Text(repo.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                // Action buttons
                HStack(spacing: 4) {
                    ActionButton(icon: "arrow.clockwise", tooltip: "Scan this repo", isEnabled: !isScanning, action: onScan)
                    ActionButton(icon: "terminal", tooltip: "Open in Terminal", action: onOpenTerminal)
                    ActionButton(icon: "chevron.left.forwardslash.chevron.right", tooltip: "Open in VS Code", action: onOpenVSCode)
                    ActionButton(icon: "folder", tooltip: "Reveal in Finder", action: onOpenFinder)
                    ActionButton(icon: "eye.slash", tooltip: "Unwatch", action: onUnwatch)
                }
            }
            .padding(16)

            Divider().background(Theme.border)

            // Details grid
            VStack(spacing: 0) {
                DetailRow(label: "Status", value: repo.isSkipped ? "Skipped in last scan" : "Scanned")
                DetailRow(label: "Path", value: repo.path)
                DetailRow(label: "Branch", value: repo.branch, isMono: true)
                DetailRow(label: "Upstream", value: repo.upstream.isEmpty ? "—" : repo.upstream, isMono: true)
                DetailRow(label: "Remote", value: repo.remoteUrl.isEmpty ? "—" : repo.remoteUrl, isMono: true)
                DetailRow(label: "Ahead", value: "\(repo.ahead)")
                DetailRow(label: "Behind", value: "\(repo.behind)",
                          valueColor: repo.behind > 0 ? Theme.statusBehind : nil)
                DetailRow(label: "Dirty", value: repo.isDirty ? "Yes" : "No",
                          valueColor: repo.isDirty ? Theme.statusDirty : nil)
                DetailRow(label: "Fetch", value: repo.fetchSuccess ? "OK" : repo.fetchError,
                          valueColor: repo.fetchSuccess ? Theme.statusClean : Theme.statusError)
                DetailRow(label: "Scanned", value: repo.lastScanned.formatted(.relative(presentation: .named)))
            }
            .padding(16)

            Spacer()
        }
        .frame(maxHeight: .infinity)
        .cardStyle()
    }
}

// MARK: - Sub Components

private struct ActionButton: View {
    let icon: String
    let tooltip: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isEnabled ? Theme.textSecondary : Theme.textTertiary)
                .frame(width: 28, height: 28)
                .background(Theme.bgHover)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(tooltip)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var isMono: Bool = false
    var valueColor: Color? = nil

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 70, alignment: .leading)

            Text(value)
                .font(.system(size: 12, weight: .regular, design: isMono ? .monospaced : .default))
                .foregroundStyle(valueColor ?? Theme.textPrimary)
                .lineLimit(2)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.vertical, 5)
    }
}
