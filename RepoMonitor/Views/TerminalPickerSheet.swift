import SwiftUI

/// First-run prompt: pick which installed terminal to use by default when
/// opening repos. The choice is saved and can be changed later in Settings.
struct TerminalPickerSheet: View {
    @ObservedObject var vm: DashboardViewModel
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose your terminal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Used when you open a repo in the terminal. Change it anytime in Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(20)

            Divider().background(Theme.border)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(vm.availableTerminals) { app in
                        Button {
                            vm.selectTerminal(app)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 20)
                                Text(app.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
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
                .padding(20)
            }

            Divider().background(Theme.border)

            HStack {
                Spacer()
                Button {
                    vm.cancelTerminalSelection()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Theme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .frame(width: 380, height: 420)
        .background(Theme.bg)
        .preferredColorScheme(theme.mode.colorScheme)
    }
}
