import SwiftUI

/// Keyboard-focus regions on the dashboard. Arrow keys move focus between the
/// search field and the repo list; ⌘1–⌘7 only act while the list is focused.
enum DashboardFocus: Hashable {
    case search
    case list
}

struct DashboardView: View {
    @ObservedObject var vm: DashboardViewModel
    @ObservedObject private var theme = ThemeManager.shared

    /// Tracks which region owns the keyboard. ⌘F focuses the search field;
    /// arrowing down from there moves focus (and selection) into the list.
    @FocusState private var focus: DashboardFocus?

    /// Horizontal inset applied to each section (top bar, list, bottom bar).
    /// Also feeds the window's minimum width so the two never drift apart.
    private let contentHPad: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                // Re-enable native title-bar drag + double-click zoom/minimize
                // behind the custom top bar (lost under `.hiddenTitleBar`).
                .background(WindowControlArea())
                .sheet(isPresented: $vm.showRemoteReview, onDismiss: {
                    vm.handleRemoteReviewDismissed()
                }) {
                    RemoteReviewSheet(vm: vm)
                }

            Divider().background(Theme.border)

            // Repo list (full width)
            repoList
                .padding(.horizontal, contentHPad)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Bottom bar
            bottomBar
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .sheet(isPresented: $vm.showTerminalPicker) {
                    TerminalPickerSheet(vm: vm)
                }
        }
        // Floor the window at the width that shows every table column in full
        // (derived from the column metrics, plus this view's side insets).
        .frame(minWidth: RepoTable.minContentWidth + contentHPad * 2, minHeight: 500)
        // ⌘F focuses the search field for an immediately-active search. A hidden
        // zero-size button is the standard SwiftUI way to bind a global shortcut.
        .background(
            Button("") { focus = .search }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        )
        // ⌘1–⌘7 fire the selected row's action buttons by position, but only
        // while the list is focused. Hidden shortcut buttons deliver Command
        // combos reliably (unlike `.onKeyPress`), and reading `focus` in the
        // action keeps them scoped to the list.
        .background(rowActionShortcuts)
        // Unwatch is destructive, so it always routes through this confirmation
        // — whether triggered by the row button, the context menu, or ⌘6.
        .alert(
            "Unwatch \(vm.repoPendingUnwatch?.name ?? "")?",
            isPresented: Binding(
                get: { vm.repoPendingUnwatch != nil },
                set: { if !$0 { vm.cancelPendingUnwatch() } }
            )
        ) {
            Button("Unwatch", role: .destructive) { vm.confirmPendingUnwatch() }
            Button("Cancel", role: .cancel) { vm.cancelPendingUnwatch() }
        } message: {
            Text("Stops monitoring it. Restore later in Settings.")
        }
        .background(Theme.bg)
        .preferredColorScheme(theme.mode.colorScheme)
        .sheet(isPresented: $vm.showSettings) {
            SettingsView(vm: vm)
        }
        .onAppear {
            // Surface any pending review that arrived while the window was closed.
            if !vm.pendingRemoteRepos.isEmpty {
                vm.showRemoteReview = true
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                BrandIcon(size: 20)
                Text("RepoMonitor")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }

            Spacer()

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Search repos...", text: $vm.searchText)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
                    .focused($focus, equals: .search)
                    // Esc while searching: clear the query and drop focus.
                    .onExitCommand {
                        vm.searchText = ""
                        focus = nil
                    }
                    // Arrow down/up from the search field jumps into the list,
                    // selecting the first / last row respectively.
                    .onKeyPress(.downArrow) {
                        guard !vm.displayedRepos.isEmpty else { return .ignored }
                        vm.selectFirstRepo()
                        focus = .list
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard !vm.displayedRepos.isEmpty else { return .ignored }
                        vm.selectLastRepo()
                        focus = .list
                        return .handled
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .frame(maxWidth: 390)

            Button {
                vm.addReposAndScan()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Add Repo")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Add a repository to monitor (⌘N)")

            Button {
                vm.showSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Repo List

    private var repoList: some View {
        VStack(spacing: 0) {
            if vm.displayedRepos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: vm.searchText.isEmpty ? "tray" : "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.textTertiary)
                    Text(vm.searchText.isEmpty ? "No repositories" : "No results")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    if vm.searchText.isEmpty {
                        Text("Add a git repository, or a folder of repositories, to start monitoring.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)

                        Button {
                            vm.addReposAndScan()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Add Repository")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RepoTableView(vm: vm, focus: $focus)
            }
        }
        .cardStyle()
        .frame(maxHeight: .infinity)
    }

    // MARK: - Row Action Shortcuts (⌘1–⌘7)

    private var rowActionShortcuts: some View {
        let keys: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7"]
        return ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
            Button("") {
                guard focus == .list, let repo = vm.selectedRepo else { return }
                vm.performRowAction(index + 1, on: repo)
            }
            .keyboardShortcut(key, modifiers: .command)
            .hidden()
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            // Left side narrates the current state inside one fixed-height bar so
            // the layout never shifts: an active pull/push (with its sub-phase)
            // wins, then scan progress, then the last-scan summary.
            bottomStatus
            Spacer()
            Text("v1.3.3")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textTertiary)

            Button {
                Task { await vm.scan() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(vm.progress.isScanning ? 360 : 0))
                        .animation(
                            vm.progress.isScanning
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: vm.progress.isScanning
                        )
                    Text("Scan")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(vm.isBusy)
        }
    }

    @ViewBuilder
    private var bottomStatus: some View {
        if vm.progress.isScanning {
            // The determinate bar stays for the whole scan; the label reflects an
            // inline auto-pull happening on the current repo.
            Text(scanLabel)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            ProgressView(value: vm.progress.fraction)
                .tint(Theme.accent)
                .frame(width: 160)
            Text("\(vm.progress.current)/\(vm.progress.total)")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
            Button("Stop Scan") {
                vm.cancelScan()
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.statusBehind)
        } else if let active = vm.activeOperation {
            // A manual pull/push with no scan running: indeterminate spinner.
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.85)
                .tint(Theme.accent)
            Text(operationPhrase(active))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        } else if let date = vm.lastScanDate {
            Text(lastScanText(date))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var scanLabel: String {
        if let op = vm.operations[vm.progress.currentRepoPath], op != .scanning {
            return "Auto-\(op.verb.lowercased()) \(vm.progress.currentRepo)"
        }
        return "Scanning: \(vm.progress.currentRepo)"
    }

    /// "Pushing RepoMonitor — writing commit message" for a manual op.
    private func operationPhrase(_ active: (name: String, op: RepoOperation)) -> String {
        var phrase = "\(active.op.verb) \(active.name)"
        if !active.op.detail.isEmpty { phrase += " — \(active.op.detail)" }
        return phrase
    }

    private func lastScanText(_ date: Date) -> String {
        var text = "Last scan: \(date.formatted(.dateTime.hour().minute().second())) (\(String(format: "%.1fs", vm.scanDuration)))"
        var extras: [String] = []
        if vm.lastAutoPushed > 0 { extras.append("auto-pushed \(vm.lastAutoPushed)") }
        if vm.lastAutoPulled > 0 { extras.append("auto-pulled \(vm.lastAutoPulled)") }
        if !extras.isEmpty { text += " · " + extras.joined(separator: ", ") }
        return text
    }
}
