import SwiftData
import SwiftUI
import UserNotifications

@main
struct GoalTrackerApp: App {
    @State private var health = HealthKitManager()
    @State private var notifications = UserNotificationManager()
    /// Held here because the notification center only keeps a weak reference to its delegate.
    private let notificationPresenter = NotificationPresenter()

    init() {
        UNUserNotificationCenter.current().delegate = notificationPresenter
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(health)
                .environment(notifications)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
        .modelContainer(for: [
            GoalProfile.self,
            ProgressPhoto.self,
            WorkoutRoutine.self,
            WeightMilestone.self,
            SpiritualQuote.self,
            CoachCritique.self,
        ])
    }
}
