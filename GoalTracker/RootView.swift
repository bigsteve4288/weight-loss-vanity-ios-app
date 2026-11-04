import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(HealthKitManager.self) private var health
    @Environment(UserNotificationManager.self) private var notifications
    @Environment(CoachNotesManager.self) private var coachNotes
    @Environment(AppRouter.self) private var router

    @Query private var profiles: [GoalProfile]

    /// New users set their goal, then their day; existing users are asked for their day once.
    private var needsOnboarding: Bool { profiles.first?.hasSetDailyRhythm != true }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "flame.fill") }
                .tag(AppTab.dashboard)
            TransformationView()
                .tabItem { Label("Transform", systemImage: "photo.on.rectangle.angled") }
                .tag(AppTab.transform)
            MindsetView()
                .tabItem { Label("Mindset", systemImage: "sparkles") }
                .tag(AppTab.mindset)
            PlanView()
                .tabItem { Label("Plan", systemImage: "list.bullet.clipboard") }
                .tag(AppTab.plan)
        }
        .sheet(isPresented: Binding(get: { needsOnboarding }, set: { _ in })) {
            Group {
                if let profile = profiles.first {
                    DailyRhythmView(profile: profile, isOnboarding: true)
                } else {
                    GoalSetupView(profile: nil)
                }
            }
            .interactiveDismissDisabled()
        }
        .task {
            SeedData.insertDefaultQuotesIfNeeded(into: context)
            await health.start()
            await rescheduleNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await health.refresh()
                    await rescheduleNotifications()
                }
            case .background:
                CoachNotesManager.scheduleBackgroundRefresh()
            default:
                break
            }
        }
    }

    /// Check-ins embed live numbers (days/lbs left), so they're rebuilt whenever the app becomes active,
    /// then rebuilt again if the coach wrote fresh messages.
    private func rescheduleNotifications() async {
        await notifications.reschedule(context: context, currentWeight: health.latestWeightLbs)
        if await coachNotes.refreshIfNeeded(context: context, health: health) {
            await notifications.reschedule(context: context, currentWeight: health.latestWeightLbs)
        }
    }
}
