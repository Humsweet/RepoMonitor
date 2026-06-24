import Foundation
import Network
import Combine

/// Watches network reachability via `NWPathMonitor` and republishes a simple
/// online/offline signal on the main actor.
///
/// This is RepoMonitor's analogue of the long-lived socket reconnect loop in
/// agent-remote: there is no persistent connection to re-establish here (the app
/// only polls `git fetch` on a timer), so instead we detect when connectivity is
/// restored and let the owner trigger an immediate catch-up scan + auto-pull.
@MainActor
final class NetworkMonitor: ObservableObject {
    /// Whether the system currently has a usable network path. Starts optimistic
    /// (`true`) so a normal launch with working network never flashes "offline"
    /// before the first path update arrives.
    @Published private(set) var isOnline = true

    /// Fired once on each offline → online transition, after a short debounce so
    /// a flapping link (Wi-Fi handoff, VPN reconnect) doesn't spawn a burst of
    /// scans. Assigned by the owner.
    var onReconnect: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.repomonitor.network-monitor")
    /// How long connectivity must stay satisfied before we treat it as a real
    /// reconnect and fire `onReconnect`.
    private let reconnectDebounce: TimeInterval = 2
    private var pendingReconnect: DispatchWorkItem?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(satisfied: satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
        pendingReconnect?.cancel()
        pendingReconnect = nil
        started = false
    }

    private func handlePathUpdate(satisfied: Bool) {
        let wasOnline = isOnline
        isOnline = satisfied

        guard satisfied else {
            // Went offline — disarm any pending reconnect callback.
            pendingReconnect?.cancel()
            pendingReconnect = nil
            return
        }

        // React only to a genuine offline → online edge.
        guard !wasOnline else { return }

        // Arm a debounced reconnect, replacing any previously armed one. If the
        // link flaps back offline within the window the offline branch above
        // cancels it, so a brief blip never triggers a scan.
        pendingReconnect?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onReconnect?()
        }
        pendingReconnect = work
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDebounce, execute: work)
    }
}
