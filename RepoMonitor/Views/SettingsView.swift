import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: DashboardViewModel
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var credentialHost = ""
    @State private var credentialUsername = ""
    @State private var credentialToken = ""
    @State private var credentialFeedback = ""
    @State private var credentialFeedbackIsError = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
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

            Divider().background(Theme.border)

            ScrollView {
                VStack(spacing: 20) {
                    // Appearance section
                    settingsSection("Appearance") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Theme")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)

                            Picker("", selection: $theme.mode) {
                                ForEach(ThemeMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        Text("Choose a light or dark appearance, or follow your Mac's system setting. Applies immediately.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Scan Folders section
                    settingsSection("Scan Folders") {
                        if vm.config.roots.isEmpty {
                            Text("No folders configured")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(vm.config.roots) { root in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(URL(fileURLWithPath: root.path).lastPathComponent)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(Theme.textPrimary)
                                            Text(root.mode == .children ? "children" : "self")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Theme.textTertiary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Theme.bgHover)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                        Text(root.path)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(Theme.textTertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Button {
                                        vm.removeRoot(root)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Theme.statusError)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        Button {
                            vm.addScanFolders()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12))
                                Text("Add Folder")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    // Startup section
                    settingsSection("Startup") {
                        settingsToggle("Launch at login", isOn: Binding(
                            get: { vm.launchAtLogin },
                            set: { vm.launchAtLogin = $0 }
                        ))

                        Text("Automatically start RepoMonitor when you log in to your Mac. Managed in System Settings › General › Login Items.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Scanning section
                    settingsSection("Scanning") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Scan interval (minutes)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)

                            HStack {
                                TextField("", value: $vm.config.desktop.scanIntervalMinutes, format: .number)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Theme.bgCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Theme.border, lineWidth: 1)
                                    )
                                    .frame(width: 80)
                                    // Apply on commit; the panel's onDisappear is the
                                    // catch-all if the user closes without pressing Return.
                                    .onSubmit { vm.saveConfig() }
                                Spacer()
                            }
                        }
                    }

                    // Terminal section
                    settingsSection("Terminal") {
                        let installed = TerminalCatalog.installed()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Open repos in")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)

                            Picker("", selection: applied($vm.config.desktop.terminalAppID)) {
                                Text("Not set").tag("")
                                ForEach(installed) { app in
                                    Text(app.name).tag(app.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        Text("Detected terminals on this Mac are listed above. Opens a new window already changed into the repo's directory. The first time you open a repo in the terminal, you'll be asked to pick one.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Pull section
                    settingsSection("Pull") {
                        settingsToggle("Auto pull after scan", isOn: applied($vm.config.git.autoPullEnabled))

                        Text("When enabled, repos that are behind with a clean working tree and no unpushed commits are pulled automatically (fast-forward only) after each scan.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        settingsToggle("Auto-update RepoMonitor", isOn: applied($vm.config.git.selfUpdateEnabled))

                        Text("When RepoMonitor's own repository is pulled and the changes affect the built app (Swift sources, Package.swift, build scripts, assets), it rebuilds and relaunches automatically. The previous version is archived and deleted 30 days after the new one has been running.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Push section
                    settingsSection("Push") {
                        settingsToggle("Auto commit & push after scan", isOn: applied($vm.config.git.autoPushEnabled))

                        Text("When enabled, repos with uncommitted changes (or unpushed commits) that are not behind remote are committed and pushed automatically after each scan. The commit message is written in English by Claude Haiku from the diff. A pre-push check runs first for both manual and automatic pushes and blocks (never pushes) on any problem: behind remote, staged secrets (.env, key files, hardcoded tokens), a missing or auto-generated git identity, or a credential embedded in the remote URL.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    settingsSection("Git Credentials") {
                        Text("Save one HTTPS username + token per Git host. Tokens are stored in macOS Keychain, not in config.json.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        if vm.config.git.hostCredentials.isEmpty {
                            Text("No saved host credentials")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textTertiary)
                        } else {
                            ForEach(vm.config.git.hostCredentials) { credential in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(credential.host)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(credential.username)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(Theme.textSecondary)
                                        Text(vm.hasStoredToken(for: credential) ? "Token stored in Keychain" : "Token missing from Keychain")
                                            .font(.system(size: 10))
                                            .foregroundStyle(vm.hasStoredToken(for: credential) ? Theme.statusClean : Theme.statusError)
                                    }

                                    Spacer()

                                    Button {
                                        credentialHost = credential.host
                                        credentialUsername = credential.username
                                        credentialToken = ""
                                        credentialFeedback = "Re-enter a token to replace the stored one."
                                        credentialFeedbackIsError = false
                                    } label: {
                                        Text("Edit")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Theme.accent)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        vm.removeHostCredential(credential)
                                        if credentialHost == credential.host {
                                            credentialHost = ""
                                            credentialUsername = ""
                                            credentialToken = ""
                                        }
                                        credentialFeedback = "Removed credential for \(credential.host)."
                                        credentialFeedbackIsError = false
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.statusError)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Host")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            settingsTextField("bitbucket.org", text: $credentialHost)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            settingsTextField("your-username", text: $credentialUsername)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Token / app password")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            settingsSecureField("Saved to macOS Keychain", text: $credentialToken)
                        }

                        HStack {
                            Spacer()
                            Button {
                                saveCredential()
                            } label: {
                                Text("Save Credential")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Theme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }

                        if !credentialFeedback.isEmpty {
                            Text(credentialFeedback)
                                .font(.system(size: 11))
                                .foregroundStyle(credentialFeedbackIsError ? Theme.statusError : Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Unwatched repos section
                    if !vm.config.unwatchedPaths.isEmpty {
                        settingsSection("Unwatched Repos") {
                            ForEach(vm.config.unwatchedPaths, id: \.self) { path in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(URL(fileURLWithPath: path).lastPathComponent)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(path)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(Theme.textTertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Button {
                                        vm.rewatchPath(path)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "eye")
                                                .font(.system(size: 10))
                                            Text("Re-watch")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .foregroundStyle(Theme.accent)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    // Ignored remote repos section
                    if !vm.config.git.ignoredRemoteRepos.isEmpty {
                        settingsSection("Ignored Remote Repos") {
                            Text("Remote repos you chose not to clone. Re-enable one to be asked again on the next scan.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)

                            ForEach(vm.config.git.ignoredRemoteRepos, id: \.self) { id in
                                HStack {
                                    Text(id)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        vm.unignoreRemoteRepo(id)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.uturn.backward")
                                                .font(.system(size: 10))
                                            Text("Re-enable")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .foregroundStyle(Theme.accent)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    // Config file section
                    settingsSection("Configuration") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Config file")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                Text(ConfigLoader.configFilePath().path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Button("Reveal") {
                                vm.revealConfig()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 620)
        .background(Theme.bg)
        .preferredColorScheme(theme.mode.colorScheme)
        // Settings apply immediately (no Save button), so persist any control —
        // notably a typed-but-not-submitted scan interval — when the panel closes.
        .onDisappear { vm.saveConfig() }
    }

    // MARK: - Helpers

    /// Wraps a config-backed binding so every change persists immediately — the
    /// panel has no Save button, so each control applies the moment it changes.
    private func applied<T>(_ binding: Binding<T>) -> Binding<T> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = $0; vm.saveConfig() })
    }

    @ViewBuilder
    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            // Pin every section card to the full panel width so the card never
            // shrinks to its content — otherwise a section holding only a short
            // toggle collapses to a small block while one with a long caption or
            // a segmented picker stretches wide.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .cardStyle()
        }
    }

    private func settingsToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        // A bare `Toggle` with a label just centres the label+switch pair when
        // stretched, so lay it out by hand: label leading, Spacer, switch
        // trailing. Switches then align in one column down the panel's edge.
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
    }

    private func settingsTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 12, design: .monospaced))
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }

    private func settingsSecureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .font(.system(size: 12, design: .monospaced))
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }

    private func saveCredential() {
        do {
            try vm.saveHostCredential(host: credentialHost, username: credentialUsername, token: credentialToken)
            credentialHost = GitHostCredential.normalizeHost(credentialHost)
            credentialUsername = credentialUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            credentialToken = ""
            credentialFeedback = "Saved credential for \(credentialHost)."
            credentialFeedbackIsError = false
        } catch {
            credentialFeedback = error.localizedDescription
            credentialFeedbackIsError = true
        }
    }
}
