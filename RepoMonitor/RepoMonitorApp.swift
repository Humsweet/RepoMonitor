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
    }

    init() {
        // Ensure config dir exists
        ConfigLoader.createDefaultConfigIfNeeded()
    }
}
