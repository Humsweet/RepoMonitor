import SwiftUI
import AppKit

extension Notification.Name {
    /// Posted whenever the dashboard window should be opened and focused.
    static let openDashboard = Notification.Name("RepoMonitor.openDashboard")
}

/// Bridges AppKit launch/reopen events into the SwiftUI window, and toggles the
/// activation policy so the app shows a Dock icon while the dashboard is open
/// and reverts to a menu-bar-only accessory once it closes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply the saved appearance globally before any window draws so the
        // first frame already matches the user's chosen theme.
        ThemeManager.shared.apply()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        // Open the dashboard on launch. The slight delay lets the SwiftUI scene
        // (and the menu-bar label that performs the open) finish wiring up so
        // the request isn't dropped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(name: .openDashboard, object: nil)
        }
    }

    /// Clicking the app in the Dock / Launchpad / Spotlight while it's already
    /// running re-opens the dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotificationCenter.default.post(name: .openDashboard, object: nil)
        return true
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow,
              isDashboard(window) else { return }
        // Defer so `isVisible` reflects state after this window finishes closing.
        DispatchQueue.main.async {
            let anotherOpen = NSApp.windows.contains {
                $0 !== window && self.isDashboard($0) && $0.isVisible
            }
            if !anotherOpen {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func isDashboard(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.contains("dashboard") == true
    }
}

/// Centralizes opening + focusing the dashboard window so the launch path, the
/// reopen path, and the menu-bar button all behave identically.
enum DashboardWindowPresenter {
    static func present(using openWindow: OpenWindowAction) {
        // Show a Dock icon while the window is up.
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.identifier?.rawValue.contains("dashboard") == true {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Closes the dashboard and reverts to a menu-bar-only accessory. Used by ⌘Q
    /// so the app stays resident in the menu bar instead of terminating.
    static func dismiss() {
        for window in NSApp.windows where window.identifier?.rawValue.contains("dashboard") == true {
            window.close()
        }
        NSApp.setActivationPolicy(.accessory)
    }
}
