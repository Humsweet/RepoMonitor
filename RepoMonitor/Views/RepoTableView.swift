import SwiftUI

// MARK: - Shared column metrics
//
// Header and rows both reference these so the columns stay perfectly aligned.
// `repo` is the flexible column that absorbs any extra window width.
private enum Col {
    static let tag: CGFloat = 104
    static let repoMin: CGFloat = 200
    static let sync: CGFloat = 112
    static let issues: CGFloat = 196
    static let scan: CGFloat = 132
    static let actions: CGFloat = 196
    static let hPad: CGFloat = 16
    static let vPad: CGFloat = 9
}

/// Layout facts other views need. Derives the minimum table width from the
/// column metrics above so the window's minimum width stays correct when a
/// column changes — a single source of truth instead of a magic number.
enum RepoTable {
    /// Width needed to show every column at its size (repo column at its floor),
    /// including the table's own horizontal padding. Excludes any outer chrome.
    static var minContentWidth: CGFloat {
        Col.tag + Col.repoMin + Col.sync + Col.issues + Col.scan + Col.actions
            + Col.hPad * 2
    }
}

struct RepoTableView: View {
    @ObservedObject var vm: DashboardViewModel
    var focus: FocusState<DashboardFocus?>.Binding

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(vm.displayedRepos) { repo in
                            RepoTableRow(
                                repo: repo,
                                isScanning: vm.progress.isScanning,
                                operation: vm.operation(for: repo),
                                recentOutcome: vm.recentOutcome(for: repo),
                                pull: vm.pullEligibility(for: repo),
                                push: vm.pushEligibility(for: repo),
                                isSelected: vm.selectedRepo?.id == repo.id,
                                onSelect: {
                                    vm.selectedRepo = repo
                                    focus.wrappedValue = .list
                                },
                                onScan: { Task { await vm.scanRepo(repo) } },
                                onPull: { Task { await vm.pullRepo(repo) } },
                                onPush: { Task { await vm.pushRepo(repo) } },
                                onOpenTerminal: { vm.openInTerminal(repo) },
                                onOpenVSCode: { vm.openInVSCode(repo) },
                                onOpenFinder: { vm.openInFinder(repo) },
                                onUnwatch: { vm.requestUnwatch(repo) }
                            )
                            .id(repo.id)
                            Rectangle()
                                .fill(Theme.border)
                                .frame(height: 0.5)
                        }
                    } header: {
                        RepoTableHeader(vm: vm)
                    }
                }
            }
            .background(Theme.bg)
            // Make the list a focus target so arrow keys reach it. The default
            // focus ring is suppressed; the selected-row highlight is the cue.
            .focusable()
            .focusEffectDisabled()
            .focused(focus, equals: .list)
            .onKeyPress(.downArrow) {
                vm.moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                // At the top row, hand focus back to the search field.
                if !vm.moveSelection(by: -1) {
                    focus.wrappedValue = .search
                }
                return .handled
            }
            // Keep the selected row visible as it moves under the keyboard.
            // A nil anchor scrolls the minimum needed to reveal an off-screen
            // row and does nothing when it's already visible — so clicking a
            // visible row never causes a jump.
            .onChange(of: vm.selectedRepo?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(id)
                }
            }
        }
    }
}

private struct RepoTableHeader: View {
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        HStack(spacing: 0) {
            SortableHeader(title: "Tag", column: .group, vm: vm)
                .frame(width: Col.tag, alignment: .leading)
            SortableHeader(title: "Repo", column: .name, vm: vm)
                .frame(minWidth: Col.repoMin, maxWidth: .infinity, alignment: .leading)
            SortableHeader(title: "Sync", column: .sync, vm: vm)
                .frame(width: Col.sync, alignment: .leading)
            SortableHeader(title: "Status", column: .issue, vm: vm)
                .frame(width: Col.issues, alignment: .leading)
            SortableHeader(title: "Last scan", column: .scanned, vm: vm)
                .frame(width: Col.scan, alignment: .leading)
            Text("Actions")
                .headerLabelStyle(active: false)
                .frame(width: Col.actions, alignment: .trailing)
        }
        .padding(.horizontal, Col.hPad)
        .padding(.vertical, 7)
        .background(Theme.bgSecondary)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderFocused).frame(height: 0.5)
        }
    }
}

private extension Text {
    func headerLabelStyle(active: Bool) -> some View {
        self
            .font(.system(size: 10, weight: .medium))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
            .lineLimit(1)
    }
}

private struct SortableHeader: View {
    let title: String
    let column: DashboardViewModel.RepoSortColumn
    @ObservedObject var vm: DashboardViewModel
    var alignment: Alignment = .leading

    @State private var isHovering = false

    private var isActive: Bool { vm.sortColumn == column }

    var body: some View {
        Button {
            vm.toggleSort(by: column)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .headerLabelStyle(active: isActive || isHovering)
                if isActive {
                    Image(systemName: vm.sortAscending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct RepoTableRow: View {
    let repo: RepoSnapshot
    let isScanning: Bool
    let operation: RepoOperation?
    let recentOutcome: OpOutcome?
    let pull: (enabled: Bool, tooltip: String)
    let push: (enabled: Bool, tooltip: String)
    let isSelected: Bool
    let onSelect: () -> Void
    let onScan: () -> Void
    let onPull: () -> Void
    let onPush: () -> Void
    let onOpenTerminal: () -> Void
    let onOpenVSCode: () -> Void
    let onOpenFinder: () -> Void
    let onUnwatch: () -> Void

    @State private var isHovering = false

    private var isPulling: Bool { operation == .pulling }
    private var isPushing: Bool { operation?.isPush == true }

    private var rowBackground: Color {
        if isSelected { return Theme.accentSoft }
        return isHovering ? Theme.bgHover : Color.clear
    }

    private var statusTooltip: String {
        var lines: [String] = ["\(repo.name)  ·  \(repo.path)"]
        if !repo.pushError.isEmpty {
            lines.append("⚠ Push failed: \(repo.pushError)")
        }
        if !repo.pushBlock.isEmpty {
            lines.append("• \(repo.pushBlock)")
        }
        if !repo.pullError.isEmpty {
            lines.append("⚠ Pull failed: \(repo.pullError)")
        }
        if !repo.fetchSuccess {
            lines.append("⚠ Fetch failed: \(repo.fetchError)")
        } else if repo.behind > 0 {
            lines.append("Behind remote by \(repo.behind) commit\(repo.behind > 1 ? "s" : "")")
        }
        if repo.ahead > 0 {
            lines.append("Ahead of remote by \(repo.ahead) commit\(repo.ahead > 1 ? "s" : "")")
        }
        if repo.isDirty { lines.append("Uncommitted: \(repo.dirtySummary)") }
        if repo.isSkipped { lines.append("Skipped in last scan") }
        if !repo.branch.isEmpty { lines.append("Branch: \(repo.branch)") }
        if !repo.upstream.isEmpty { lines.append("Upstream: \(repo.upstream)") }
        if !repo.remoteUrl.isEmpty { lines.append("Remote: \(repo.remoteUrl)") }
        if lines.count == 1 { lines.append("Clean — up to date") }
        return lines.joined(separator: "\n")
    }

    private var issueTooltip: String {
        // Lead with the full, uncategorised git message (the short chip is only
        // the distilled headline); fall back to the chip text for dirty/info.
        let headline = repo.issueDetail.isEmpty ? repo.issueText : repo.issueDetail
        var lines = [headline]
        if repo.issueSeverity == .info, !repo.dirtyFiles.isEmpty {
            lines.append(contentsOf: repo.dirtyFiles.map { "  \($0)" })
            let remaining = repo.modifiedCount + repo.untrackedCount - repo.dirtyFiles.count
            if remaining > 0 { lines.append("  …and \(remaining) more") }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 0) {
            // Tag
            TagBadge(label: repo.groupTag)
                .frame(width: Col.tag, alignment: .leading)

            // Repo — status dot + name, full detail (incl. path) on hover
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.statusColor(for: repo.statusLevel))
                    .frame(width: 7, height: 7)
                Text(repo.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: Col.repoMin, maxWidth: .infinity, alignment: .leading)
            .help(statusTooltip)

            // Sync — ahead ↑ · behind ↓
            SyncCell(ahead: repo.ahead, behind: repo.behind)
                .frame(width: Col.sync, alignment: .leading)

            // Status — in-progress phase wins, then a fading outcome, then the
            // failure/attention/info pill (or a quiet all-clear check).
            Group {
                if let operation {
                    ProgressPill(text: operation.chip)
                } else if let recentOutcome {
                    OutcomePill(outcome: recentOutcome)
                } else if repo.hasIssue {
                    IssuePill(text: repo.issueText, severity: repo.issueSeverity)
                        .help(issueTooltip)
                } else {
                    IssuePill.empty
                }
            }
            .frame(width: Col.issues, alignment: .leading)

            // Last scan
            Text(repo.scannedDisplay)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: Col.scan, alignment: .leading)

            // Actions
            HStack(spacing: 1) {
                ActionButton(icon: "arrow.clockwise", tooltip: "Scan", isEnabled: !isScanning && operation == nil, spinning: operation == .scanning, action: onScan)
                ActionButton(icon: "arrow.down.to.line", tooltip: pull.tooltip, isEnabled: pull.enabled, spinning: isPulling, action: onPull)
                ActionButton(icon: "arrow.up.to.line", tooltip: push.tooltip, isEnabled: push.enabled, spinning: isPushing, action: onPush)
                ActionButton(icon: "folder", tooltip: "Finder", action: onOpenFinder)
                ActionButton(icon: "chevron.left.forwardslash.chevron.right", tooltip: "VS Code", action: onOpenVSCode)
                ActionButton(icon: "terminal", tooltip: "Terminal", action: onOpenTerminal)
                ActionButton(icon: "eye.slash", tooltip: "Unwatch", isDanger: true, action: onUnwatch)
            }
            .frame(width: Col.actions, alignment: .trailing)
        }
        .padding(.horizontal, Col.hPad)
        .padding(.vertical, Col.vPad)
        .background(rowBackground)
        // A left accent bar marks the selected row without shifting layout.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.accent)
                .frame(width: 3)
                .opacity(isSelected ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // Click anywhere on the row (outside the action buttons) to select it.
        .onTapGesture { onSelect() }
        .contextMenu {
            Button { onScan() } label: {
                Label("Scan This Repo", systemImage: "arrow.clockwise")
            }
            .disabled(isScanning || operation != nil)

            Button { onPull() } label: {
                Label("Pull This Repo", systemImage: "arrow.down.to.line")
            }
            .disabled(!pull.enabled)

            Button { onPush() } label: {
                Label("Commit & Push This Repo", systemImage: "arrow.up.to.line")
            }
            .disabled(!push.enabled)

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

// MARK: - Cells

private struct TagBadge: View {
    let label: String

    var body: some View {
        let color = Theme.groupColor(for: label)
        Text(label)
            .font(.system(size: 10))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(color.opacity(0.28), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private struct SyncCell: View {
    let ahead: Int
    let behind: Int

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(ahead)")
                    .font(.system(size: 11, weight: ahead > 0 ? .semibold : .regular, design: .monospaced))
            }
            .foregroundStyle(ahead > 0 ? Theme.syncAhead : Theme.textTertiary)

            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)

            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(behind)")
                    .font(.system(size: 11, weight: behind > 0 ? .semibold : .regular, design: .monospaced))
            }
            .foregroundStyle(behind > 0 ? Theme.syncBehind : Theme.textTertiary)
        }
    }
}

/// Status-column pill whose loudness tracks severity: red/amber *filled*
/// capsules for real failures and safe-stops, quiet unstyled text for normal
/// local edits (info), and a near-invisible check for the all-clear majority —
/// so the common "everything's fine" state adds no visual noise to the table.
private struct IssuePill: View {
    let text: String
    let severity: IssueSeverity

    static let empty = IssuePill(text: "", severity: .clean, isEmpty: true)

    private var isEmpty = false

    init(text: String, severity: IssueSeverity) {
        self.text = text
        self.severity = severity
    }

    private init(text: String, severity: IssueSeverity, isEmpty: Bool) {
        self.text = text
        self.severity = severity
        self.isEmpty = isEmpty
    }

    private var tint: Color {
        switch severity {
        case .error: return Theme.statusError
        case .attention: return Theme.statusDirty
        case .info: return Theme.textSecondary
        case .clean: return Theme.textTertiary
        }
    }

    private var icon: String {
        switch severity {
        case .error: return "exclamationmark.octagon"
        case .attention: return "exclamationmark.triangle"
        case .info: return "pencil"
        case .clean: return "checkmark"
        }
    }

    var body: some View {
        if isEmpty {
            // All clear: the quietest possible mark, no capsule — it appears on
            // most rows, so it must recede.
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary.opacity(0.55))
        } else if severity == .info {
            // Normal local changes are information, not a warning: quiet text,
            // no fill, no border — never competes with a real issue.
            label
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
        } else {
            label
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(tint.opacity(0.12))
                .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 0.5))
                .clipShape(Capsule())
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct ActionButton: View {
    let icon: String
    let tooltip: String
    var isEnabled: Bool = true
    var isDanger: Bool = false
    var spinning: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    private var foreground: Color {
        guard isEnabled else { return Theme.textTertiary.opacity(0.6) }
        if isHovering { return isDanger ? Theme.statusError : Theme.accentHover }
        return Theme.textTertiary
    }

    private var background: Color {
        if spinning { return Theme.accentSoft }
        guard isEnabled, isHovering else { return .clear }
        return isDanger ? Theme.statusError.opacity(0.15) : Theme.accentSoft
    }

    var body: some View {
        Button(action: action) {
            Group {
                if spinning {
                    // A native spinner is an unambiguous "working" cue — distinct
                    // from a merely disabled (greyed) button.
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                        .tint(Theme.accent)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(foreground)
                }
            }
            .frame(width: 26, height: 26)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .help(tooltip)
    }
}

/// Neutral, accent-tinted "operation in progress" pill with a live spinner,
/// shown in the Status column so a running pull/push reads as activity — never
/// as a failure.
private struct ProgressPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .tint(Theme.accent)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Theme.accentSoft)
        .overlay(Capsule().stroke(Theme.accent.opacity(0.3), lineWidth: 0.5))
        .clipShape(Capsule())
    }
}

/// Brief confirmation pill after a manual pull/push: green check for a real
/// success, neutral for an advisory "nothing to do" outcome.
private struct OutcomePill: View {
    let outcome: OpOutcome

    private var tint: Color { outcome.isPositive ? Theme.statusClean : Theme.textSecondary }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: outcome.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(outcome.chip)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12))
        .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 0.5))
        .clipShape(Capsule())
    }
}
