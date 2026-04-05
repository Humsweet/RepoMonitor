import SwiftUI

struct StatsCardView: View {
    let title: String
    let value: Int
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            Text("\(value)")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardStyle()
    }
}

struct StatsBarView: View {
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        HStack(spacing: 10) {
            StatsCardView(
                title: "Repositories",
                value: vm.totalCount,
                icon: "folder",
                color: Theme.accent
            )
            StatsCardView(
                title: "Behind",
                value: vm.behindCount,
                icon: "arrow.down",
                color: Theme.statusBehind
            )
            StatsCardView(
                title: "Dirty",
                value: vm.dirtyCount,
                icon: "pencil",
                color: Theme.statusDirty
            )
            StatsCardView(
                title: "Warnings",
                value: vm.warningCount,
                icon: "exclamationmark.triangle",
                color: Theme.statusError
            )
        }
    }
}
