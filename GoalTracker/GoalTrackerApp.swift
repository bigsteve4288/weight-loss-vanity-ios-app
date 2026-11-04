import SwiftData
import SwiftUI
import UserNotifications

@main
struct GoalTrackerApp: App {
    @State private var health = HealthKitManager()
    @State private var notifications = UserNotificationManager()
    @State private var coachNotes = CoachNotesManager()
    @State private var router: AppRouter
    /// Held here because the notification center only keeps a weak reference to its delegate.
    private let notificationPresenter: NotificationPresenter
    private let container: ModelContainer

    init() {
        let router = AppRouter()
        _router = State(initialValue: router)
        notificationPresenter = NotificationPresenter(router: router)
        UNUserNotificationCenter.current().delegate = notificationPresenter
        do {
            container = try ModelContainer(for:
                GoalProfile.self,
                ProgressPhoto.self,
                WorkoutRoutine.self,
                WeightMilestone.self,
                SpiritualQuote.self,
                CoachCritique.self,
                CoachNote.self
            )
        } catch {
            fatalError("Couldn't open the data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(health)
                .environment(notifications)
                .environment(coachNotes)
                .environment(router)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
        .modelContainer(container)
        .backgroundTask(.appRefresh(CoachNotesManager.backgroundTaskID)) {
            await refreshInBackground()
        }
    }

    /// Overnight wake-up: rewrite tomorrow's check-ins and reschedule. Health data may be locked
    /// while the phone is, in which case the coach writes from the last numbers it saw.
    @MainActor
    private func refreshInBackground() async {
        CoachNotesManager.scheduleBackgroundRefresh()
        await health.refresh()
        let context = container.mainContext
        if await coachNotes.refreshIfNeeded(context: context, health: health) {
            await notifications.reschedule(context: context, currentWeight: health.latestWeightLbs)
        }
    }
}
