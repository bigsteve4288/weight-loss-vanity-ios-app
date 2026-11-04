import UserNotifications

/// Without a delegate, iOS silently drops notifications that arrive while the app is open.
/// This shows them as banners in the foreground too, and opens the Check-ins list when one is tapped.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    private let router: AppRouter

    init(router: AppRouter) {
        self.router = router
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await router.openCheckIns()
    }
}
