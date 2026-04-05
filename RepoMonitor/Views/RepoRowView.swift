import SwiftUI

struct RepoRowView: View {
    let repo: RepoSnapshot
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator dot
            Circle()
                .fill(Theme.statusColor(for: repo.statusLevel))
                .frame(width: 8, height: 8)

            // Name + branch
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(repo.branch)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status badges
            HStack(spacing: 6) {
                if repo.isSkipped {
                    StatusBadge(text: "skip", color: Theme.textSecondary)
                }
                if repo.behind > 0 {
                    StatusBadge(text: "↓\(repo.behind)", color: Theme.statusBehind)
                }
                if repo.ahead > 0 {
                    StatusBadge(text: "↑\(repo.ahead)", color: Theme.accent)
                }
                if repo.isDirty {
                    StatusBadge(text: "●", color: Theme.statusDirty)
                }
                if !repo.fetchSuccess {
                    StatusBadge(text: "⚠", color: Theme.statusError)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Theme.accent.opacity(0.15) : Color.clear)
        .background(Theme.bgCard.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Theme.accent.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
