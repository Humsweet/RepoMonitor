import SwiftUI

struct DashboardView: View {
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            Divider().background(Theme.border)

            // Stats
            StatsBarView(vm: vm)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Progress bar
            if vm.progress.isScanning {
                scanProgressBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            // Repo list (full width)
            repoList
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            // Bottom bar
            bottomBar
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 900, minHeight: 500)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $vm.showSettings) {
            SettingsView(vm: vm)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text("RepoMonitor")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

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

    // MARK: - Scan Progress

    private var scanProgressBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Scanning: \(vm.progress.currentRepo)")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Button("Skip Current") {
                    vm.skipCurrentRepo()
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.statusBehind)
                Text("\(vm.progress.current)/\(vm.progress.total)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
            ProgressView(value: vm.progress.fraction)
                .tint(Theme.accent)
                .scaleEffect(x: 1, y: 0.5)
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
                        Text("Add repos to ~/.config/repo-monitor/config.json")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)
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
        HStack {
            if let date = vm.lastScanDate {
                Text("Last scan: \(date.formatted(.dateTime.hour().minute().second())) (\(String(format: "%.1fs", vm.scanDuration)))")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text("v1.0.0")
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
