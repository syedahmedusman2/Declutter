import DownloadOrganizerCore
import UserNotifications

struct UserNotificationPoster: NotificationDelivering {
    func deliver(_ request: NotificationRequest) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        let notification = UNNotificationRequest(
            identifier: "\(request.kind.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(notification)
    }
}
