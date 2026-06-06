import SwiftUI

@main
struct RepoMonitorApp: App {
    @StateObject private var vm = DashboardViewModel()

    var body: some Scene {
        // Menu bar
        MenuBarExtra {
            MenuBarView(vm: vm)
        } label: {
            Label(vm.menuBarLabel, systemImage: vm.menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        // Dashboard window
        Window("RepoMonitor", id: "dashboard") {
            DashboardView(vm: vm)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 640)
        .commands {
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
