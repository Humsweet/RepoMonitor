import SwiftUI

@main
struct RepoMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vm = DashboardViewModel()

    var body: some Scene {
        // Menu bar
        MenuBarExtra {
            MenuBarView(vm: vm)
        } label: {
            MenuBarLabel(vm: vm)
        }
        .menuBarExtraStyle(.window)

        // Dashboard window
        Window("RepoMonitor", id: "dashboard") {
            DashboardView(vm: vm)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 640)
        .commands {
            // RepoMonitor lives in the menu bar, so ⌘Q closes the window and
            // returns to a menu-bar-only accessory instead of quitting. The real
            // Quit stays in the menu-bar popover. This only rebinds the menu
            // command — system logout/shutdown still terminate normally.
            CommandGroup(replacing: .appTermination) {
                Button("Close Window") {
                    DashboardWindowPresenter.dismiss()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Repository…") {
                    vm.addReposAndScan()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Rescan All") {
                    Task { await vm.scan() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(vm.progress.isScanning)
            }
        }
    }

    init() {
        // Ensure config dir exists
        ConfigLoader.createDefaultConfigIfNeeded()
    }
}

/// The menu-bar status item label. It also owns the `openWindow` action and
/// performs the actual dashboard open in response to `.openDashboard`, since it
/// is always alive for the whole app lifetime (unlike the popover content).
private struct MenuBarLabel: View {
    @ObservedObject var vm: DashboardViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(vm.menuBarLabel, systemImage: vm.menuBarIcon)
            .onReceive(NotificationCenter.default.publisher(for: .openDashboard)) { _ in
                DashboardWindowPresenter.present(using: openWindow)
            }
    }
}
