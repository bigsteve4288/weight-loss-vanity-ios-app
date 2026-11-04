import UserNotifications

/// Without a delegate, iOS silently drops notifications that arrive while the app is open.
/// This shows them as banners in the foreground too.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
