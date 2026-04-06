import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: DashboardViewModel
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

                    // Notifications section
                    settingsSection("Notifications") {
                        settingsToggle("Enable notifications", isOn: $vm.config.notifications.enabled)

                        if vm.config.notifications.enabled {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notification mode")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)

                                Picker("", selection: $vm.config.notifications.mode) {
                                    Text("Errors only").tag(NotificationConfig.NotifyMode.errors)
                                    Text("Behind").tag(NotificationConfig.NotifyMode.behind)
                                    Text("Behind + Dirty").tag(NotificationConfig.NotifyMode.behindAndDirty)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Minimum interval (minutes)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)

                                HStack {
                                    TextField("", value: $vm.config.notifications.minimumIntervalMinutes, format: .number)
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
                                    Spacer()
                                }
                            }
                        }
                    }

                    // Scanning section
                    settingsSection("Scanning") {
                        settingsToggle("Fetch before compare", isOn: $vm.config.git.fetchBeforeCompare)

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
                                Spacer()
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Fetch timeout (seconds)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)

                            HStack {
                                TextField("", value: $vm.config.git.fetchTimeoutSeconds, format: .number)
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
                                Spacer()
                            }
                        }
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

            Divider().background(Theme.border)

            // Save button
            HStack {
                Spacer()
                Button {
                    dismiss()
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

                Button {
                    vm.saveConfig()
                    dismiss()
                } label: {
                    Text("Save")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .frame(width: 480, height: 620)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .cardStyle()
        }
    }

    private func settingsToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .toggleStyle(.switch)
        .tint(Theme.accent)
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
