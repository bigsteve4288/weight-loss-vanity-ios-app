import SwiftData
import SwiftUI

@main
struct GoalTrackerApp: App {
    @State private var health = HealthKitManager()
    @State private var notifications = UserNotificationManager()

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
