import SwiftUI
import AppKit

/// Restores the native title-bar interactions that a `.hiddenTitleBar` window
/// otherwise loses, without changing the look. It is meant to sit *behind* the
/// dashboard's custom top bar: interactive SwiftUI controls (search field,
/// buttons) stay in front and keep receiving their own clicks, while clicks on
/// the empty title region fall through to this transparent layer.
///
/// Behaviors provided:
/// - Double-click the title region → zoom or minimize, honoring the system
///   "Double-click a window's title bar to…" setting (`AppleActionOnDoubleClick`).
/// - Drag the title region → move the window.
/// - Remember the window's frame across launches (frame autosave).
struct WindowControlArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitlebarBehaviorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Transparent view that re-implements the title-bar mouse behaviors AppKit
/// would give a standard titlebar. It draws nothing, so the window keeps its
/// current appearance.
private final class TitlebarBehaviorView: NSView {
    // Drive drag + double-click ourselves so a double-click isn't swallowed by
    // AppKit's automatic window-move machinery.
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Single source of truth for the window's persisted frame: once named,
        // AppKit saves the frame on move/resize and restores it on next launch.
        window?.setFrameAutosaveName("RepoMonitorDashboard")
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        if event.clickCount == 2 {
            performDoubleClickAction(on: window)
        } else {
            window.performDrag(with: event)
        }
    }

    /// Mirrors Finder and standard apps: read the user's "double-click a
    /// window's title bar to" preference and act accordingly.
    private func performDoubleClickAction(on window: NSWindow) {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize":
            window.performMiniaturize(nil)
        case "None":
            break
        default: // "Maximize" or unset → zoom (Fill), the system default
            window.performZoom(nil)
        }
    }
}
