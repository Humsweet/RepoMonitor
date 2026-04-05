import SwiftUI

struct MenuBarView: View {
    @ObservedObject var vm: DashboardViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var scanIconRotation: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("RepoMonitor")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                if vm.progress.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }

                if let date = vm.lastScanDate {
                    Text(date, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().background(Theme.border)

            // Quick stats
            HStack(spacing: 16) {
                MiniStat(value: vm.totalCount, label: "repos", color: Theme.accent)
                MiniStat(value: vm.behindCount, label: "behind", color: Theme.statusBehind)
                MiniStat(value: vm.dirtyCount, label: "dirty", color: Theme.statusDirty)
                MiniStat(value: vm.warningCount, label: "warnings", color: Theme.statusError)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().background(Theme.border)

            // Actions
            VStack(spacing: 2) {
                MenuBarButton(title: "Open Dashboard", icon: "rectangle.3.group") {
                    openWindow(id: "dashboard")
                }
                MenuBarScanButton(isScanning: vm.progress.isScanning) {
                    Task { await vm.scan() }
                }
                if vm.progress.isScanning {
                    MenuBarButton(title: "Skip Current Repo", icon: "forward") {
                        vm.skipCurrentRepo()
                    }
                }
                MenuBarButton(title: "Edit Config", icon: "gear") {
                    vm.revealConfig()
                }

                Divider().background(Theme.border).padding(.vertical, 4)

                MenuBarButton(title: "Quit", icon: "power") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 300)
        .background(Theme.bg)
    }
}

// MARK: - Sub Components

private struct MiniStat: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(value > 0 ? color : Theme.textSecondary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MenuBarRepoRow: View {
    let repo: RepoSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.statusColor(for: repo.statusLevel))
                .frame(width: 6, height: 6)

            Text(repo.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(repo.statusSummary)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.statusColor(for: repo.statusLevel))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct MenuBarScanButton: View {
    let isScanning: Bool
    let action: () -> Void
    @State private var rotation: Double = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(isScanning ? Theme.accent : Theme.textSecondary)
                    .frame(width: 16)
                    .rotationEffect(.degrees(rotation))
                Text(isScanning ? "Scanning..." : "Scan Now")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isScanning ? Theme.accent : Theme.textPrimary)
                Spacer()
                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(isScanning)
        .onChange(of: isScanning) { _, scanning in
            if scanning {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            } else {
                withAnimation(.default) {
                    rotation = 0
                }
            }
        }
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private struct MenuBarButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
