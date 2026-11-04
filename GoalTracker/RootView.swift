import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(HealthKitManager.self) private var health
    @Environment(UserNotificationManager.self) private var notifications

    @Query private var profiles: [GoalProfile]
    @Query private var quotes: [SpiritualQuote]
    @Query(filter: #Predicate<ProgressPhoto> { $0.isBaseline == true }) private var baselines: [ProgressPhoto]

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "flame.fill") }
            TransformationView()
                .tabItem { Label("Transform", systemImage: "photo.on.rectangle.angled") }
            MindsetView()
                .tabItem { Label("Mindset", systemImage: "sparkles") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "list.bullet.clipboard") }
        }
        .sheet(isPresented: Binding(get: { profiles.isEmpty }, set: { _ in })) {
            GoalSetupView(profile: nil)
                .interactiveDismissDisabled()
        }
        .task {
            SeedData.insertDefaultQuotesIfNeeded(into: context)
            await health.start()
            await rescheduleNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await health.refresh()
                await rescheduleNotifications()
            }
        }
    }

    /// Daily notifications embed live numbers (days/lbs left), so they are rebuilt whenever the app becomes active.
    private func rescheduleNotifications() async {
        await notifications.reschedule(
            profile: profiles.first,
            currentWeight: health.latestWeightLbs,
            quotes: quotes,
            baselineImageData: baselines.first?.imageData
        )
    }
}
