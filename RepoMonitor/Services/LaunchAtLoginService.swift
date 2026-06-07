import Foundation
import ServiceManagement
import os

/// Manages whether RepoMonitor launches automatically at login.
///
/// Uses `SMAppService.mainApp`, which registers the app's own bundle as a
/// login item. The enabled state is owned by macOS (visible in System
/// Settings › General › Login Items), not by `config.json`.
enum LaunchAtLoginService {
    private static let logger = Logger(subsystem: "com.humsweet.RepoMonitor", category: "LaunchAtLogin")

    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register or unregister the app as a login item.
    /// - Returns: `true` if the requested state was reached, `false` on error.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            logger.error("Failed to \(enabled ? "enable" : "disable", privacy: .public) launch at login: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
