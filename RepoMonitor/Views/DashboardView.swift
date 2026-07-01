import SwiftUI

struct DashboardView: View {
    @ObservedObject var vm: DashboardViewModel
    @ObservedObject private var theme = ThemeManager.shared

    /// Drives ⌘F: pressing it moves keyboard focus into the search field.
    @FocusState private var isSearchFocused: Bool

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
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        )
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
                    .focused($isSearchFocused)
                    // Esc while searching: clear the query and drop focus.
                    .onExitCommand {
                        vm.searchText = ""
                        isSearchFocused = false
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
                RepoTableView(vm: vm)
            }
        }
        .cardStyle()
        .frame(maxHeight: .infinity)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            // Left side: scan progress while scanning, last-scan info otherwise.
            // Both states render inside the same fixed-height bar, so the
            // layout never shifts when a scan starts or ends.
            if vm.progress.isScanning {
                Text("Scanning: \(vm.progress.currentRepo)")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                ProgressView(value: vm.progress.fraction)
                    .tint(Theme.accent)
                    .frame(width: 160)
                Text("\(vm.progress.current)/\(vm.progress.total)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Button("Skip Current") {
                    vm.skipCurrentRepo()
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.statusBehind)
            } else if let date = vm.lastScanDate {
                Text("Last scan: \(date.formatted(.dateTime.hour().minute().second())) (\(String(format: "%.1fs", vm.scanDuration)))")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text("v1.2.3")
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
            .disabled(vm.progress.isScanning)
        }
    }
}
