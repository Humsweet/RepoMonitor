import SwiftUI

struct RepoTableView: View {
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(vm.displayedRepos) { repo in
                        RepoTableRow(
                            repo: repo,
                            isScanning: vm.progress.isScanning,
                            onScan: { Task { await vm.scanRepo(repo) } },
                            onOpenTerminal: { vm.openInTerminal(repo) },
                            onOpenVSCode: { vm.openInVSCode(repo) },
                            onOpenFinder: { vm.openInFinder(repo) },
                            onUnwatch: { vm.unwatchRepo(repo) }
                        )
                        Divider().background(Theme.border)
                    }
                } header: {
                    RepoTableHeader(vm: vm)
                }
            }
        }
        .background(Theme.bgCard)
    }
}

private struct RepoTableHeader: View {
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        HStack(spacing: 0) {
            SortableHeader(title: "", column: .status, vm: vm)
                .frame(width: 44)
            SortableHeader(title: "Repo", column: .name, vm: vm)
                .frame(minWidth: 160, maxWidth: 200)
            SortableHeader(title: "Path", column: .path, vm: vm)
                .frame(minWidth: 200, maxWidth: .infinity)
            SortableHeader(title: "Ahead", column: .ahead, vm: vm, alignment: .trailing)
                .frame(width: 64)
            SortableHeader(title: "Behind", column: .behind, vm: vm, alignment: .trailing)
                .frame(width: 64)
            Color.clear.frame(width: 20)
            SortableHeader(title: "Last Scan", column: .scanned, vm: vm)
                .frame(width: 140)
            // Space for action buttons
            Color.clear.frame(width: 110)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Theme.bgSecondary.opacity(0.96))
    }
}

private struct SortableHeader: View {
    let title: String
    let column: DashboardViewModel.RepoSortColumn
    @ObservedObject var vm: DashboardViewModel
    var alignment: Alignment = .leading

    var body: some View {
        Button {
            vm.toggleSort(by: column)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .lineLimit(1)
                if vm.sortColumn == column {
                    Image(systemName: vm.sortAscending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: alignment)
        }
        .buttonStyle(.plain)
    }
}

private struct RepoTableRow: View {
    let repo: RepoSnapshot
    let isScanning: Bool
    let onScan: () -> Void
    let onOpenTerminal: () -> Void
    let onOpenVSCode: () -> Void
    let onOpenFinder: () -> Void
    let onUnwatch: () -> Void

    @State private var isHovering = false

    private var statusTooltip: String {
        var lines: [String] = []
        if !repo.fetchSuccess {
            lines.append("⚠ Fetch failed: \(repo.fetchError)")
        } else if repo.behind > 0 {
            lines.append("Behind remote by \(repo.behind) commit\(repo.behind > 1 ? "s" : "")")
        }
        if repo.ahead > 0 {
            lines.append("Ahead of remote by \(repo.ahead) commit\(repo.ahead > 1 ? "s" : "")")
        }
        if repo.isDirty { lines.append("Uncommitted changes") }
        if repo.isSkipped { lines.append("Skipped in last scan") }
        if !repo.branch.isEmpty { lines.append("Branch: \(repo.branch)") }
        if !repo.upstream.isEmpty { lines.append("Upstream: \(repo.upstream)") }
        if !repo.remoteUrl.isEmpty { lines.append("Remote: \(repo.remoteUrl)") }
        if lines.isEmpty { lines.append("Clean — up to date") }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 0) {
            // Status — colored dot only, centered
            Circle()
                .fill(Theme.statusColor(for: repo.statusLevel))
                .frame(width: 9, height: 9)
                .frame(width: 44)
                .help(statusTooltip)

            // Repo name
            Text(repo.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(minWidth: 160, maxWidth: 200, alignment: .leading)

            // Path
            Text(repo.path)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)

            // Ahead
            Text("\(repo.ahead)")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(repo.ahead > 0 ? Theme.accent : Theme.textSecondary)
                .frame(width: 64, alignment: .trailing)

            // Behind
            Text("\(repo.behind)")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(repo.behind > 0 ? Theme.statusBehind : Theme.textSecondary)
                .frame(width: 64, alignment: .trailing)

            // Gap between Behind and Last Scan
            Color.clear.frame(width: 20)

            // Last Scan
            Text(repo.scannedDisplay)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            // Action buttons (always visible)
            HStack(spacing: 2) {
                RowActionButton(icon: "arrow.clockwise", tooltip: "Scan", isEnabled: !isScanning, action: onScan)
                RowActionButton(icon: "terminal", tooltip: "Terminal", action: onOpenTerminal)
                RowActionButton(icon: "chevron.left.forwardslash.chevron.right", tooltip: "VS Code", action: onOpenVSCode)
                RowActionButton(icon: "folder", tooltip: "Finder", action: onOpenFinder)
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovering ? Theme.bgHover.opacity(0.5) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button { onScan() } label: {
                Label("Scan This Repo", systemImage: "arrow.clockwise")
            }
            .disabled(isScanning)

            Divider()

            Button { onOpenTerminal() } label: {
                Label("Open in Terminal", systemImage: "terminal")
            }
            Button { onOpenVSCode() } label: {
                Label("Open in VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Button { onOpenFinder() } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Divider()

            Button(role: .destructive) { onUnwatch() } label: {
                Label("Unwatch", systemImage: "eye.slash")
            }
        }
    }
}

private struct RowActionButton: View {
    let icon: String
    let tooltip: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isEnabled ? Theme.textSecondary : Theme.textTertiary)
                .frame(width: 24, height: 24)
                .background(Theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(tooltip)
    }
}
