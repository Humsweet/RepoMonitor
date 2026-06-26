import SwiftUI

/// Presents remote repos that exist on the user's accounts but aren't cloned
/// locally. The user clones or ignores each (ignore is remembered permanently).
struct RemoteReviewSheet: View {
    @ObservedObject var vm: DashboardViewModel
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    private var groups: [(folder: String, repos: [DiscoveredRemoteRepo])] {
        let grouped = Dictionary(grouping: vm.pendingRemoteRepos, by: { $0.targetFolder })
        return grouped
            .map { (folder: $0.key, repos: $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
            .sorted { $0.folder.localizedCaseInsensitiveCompare($1.folder) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.border)

            if vm.pendingRemoteRepos.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.folder) { group in
                            groupSection(group.folder, repos: group.repos)
                        }
                    }
                    .padding(20)
                }
            }

            Divider().background(Theme.border)
            footer
        }
        .frame(width: 560, height: 600)
        .background(Theme.bg)
        .preferredColorScheme(theme.mode.colorScheme)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("New repositories found")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(vm.pendingRemoteRepos.count) remote repo\(vm.pendingRemoteRepos.count == 1 ? "" : "s") not cloned locally. Clone them, or ignore to stop being asked.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Theme.bgHover)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private func groupSection(_ folder: String, repos: [DiscoveredRemoteRepo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Text(abbreviate(folder))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            ForEach(repos) { repo in
                repoRow(repo)
            }
        }
    }

    private func repoRow(_ repo: DiscoveredRemoteRepo) -> some View {
        let isCloning = vm.cloningRemoteIDs.contains(repo.id)
        let error = vm.cloneErrors[repo.id]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(repo.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if repo.isPrivate {
                            Text("private")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.bgHover)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text("\(repo.owner) · \(repo.host)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                    if !repo.summary.isEmpty {
                        Text(repo.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if isCloning {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Button { Task { await vm.cloneRemoteRepo(repo) } } label: {
                        Text("Clone")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)

                    Button { vm.ignoreRemoteRepo(repo) } label: {
                        Text("Ignore")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.statusError)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Theme.bgCard.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(Theme.statusClean)
            Text("All caught up")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button { vm.ignoreAllRemoteRepos(); dismiss() } label: {
                Text("Ignore All")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(vm.pendingRemoteRepos.isEmpty)

            Button { Task { await vm.cloneAllRemoteRepos() } } label: {
                Text("Clone All")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(vm.pendingRemoteRepos.isEmpty || !vm.cloningRemoteIDs.isEmpty)
        }
        .padding(20)
    }

    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
