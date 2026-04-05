import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private override init() {
        super.init()
    }

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("[NotificationService] Permission error: \(error)")
            }
        }
    }

    func send(_ notification: MonitorNotification) {
        let content = UNMutableNotificationContent()
        content.title = "RepoMonitor"
        content.subtitle = notification.repoName
        content.body = notification.message
        content.sound = .default

        switch notification.level {
        case .error:
            content.categoryIdentifier = "REPO_ERROR"
        case .warning:
            content.categoryIdentifier = "REPO_WARNING"
        case .info:
            content.categoryIdentifier = "REPO_INFO"
        }

        let request = UNNotificationRequest(
            identifier: notification.id.uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationService] Delivery error: \(error)")
            }
        }
    }

    func sendBatch(_ notifications: [MonitorNotification]) {
        for notification in notifications {
            send(notification)
        }
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
