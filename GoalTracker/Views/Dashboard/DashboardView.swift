import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(HealthKitManager.self) private var health
    @Query private var profiles: [GoalProfile]
    @Query private var milestones: [WeightMilestone]
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                if let profile = profiles.first {
                    let snapshot = viewModel.snapshot(profile: profile, health: health)
                    VStack(spacing: 16) {
                        TodaySummaryCard(
                            snapshot: snapshot,
                            onLogWeight: { viewModel.isShowingLogWeight = true },
                            onOpenSettings: { viewModel.isShowingSettings = true }
                        )
                        StatusCard(snapshot: snapshot)
                        EmergencyResetButton { viewModel.isShowingEmergencyReset = true }
                        TargetCard(snapshot: snapshot, startWeight: profile.startWeightLbs)
                        PaceCard(
                            snapshot: snapshot,
                            acknowledgedRequiredPace: profile.intensity == .aggressive ? profile.aggressiveAcknowledgedRequiredPace : nil
                        )
                        CountdownCard(targetDate: profile.targetDate)
                        DeficitCard(snapshot: snapshot)
                        MacrosCard(carbs: health.carbsGrams, protein: health.proteinGrams, fat: health.fatGrams)
                        WorkoutsCard(workouts: health.recentWorkouts)
                        if !health.weightHistory.isEmpty {
                            WeightTrendCard(snapshot: snapshot, goalStartDate: profile.startDate, goalStartWeight: profile.startWeightLbs)
                        }
                        HealthSyncFooter()
                    }
                    .padding()
                } else {
                    ContentUnavailableView("Set Your Goal", systemImage: "target", description: Text("Finish setup to start the engine."))
                        .padding(.top, 80)
                }
            }
            .background(ThemedBackground())
            .navigationTitle("Vanity")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Goal Settings", systemImage: "gearshape.fill") { viewModel.isShowingSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ask the Coach", systemImage: "bubble.left.and.text.bubble.right.fill") { viewModel.isShowingCoachChat = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log Weight", systemImage: "scalemass.fill") { viewModel.isShowingLogWeight = true }
                }
            }
            .refreshable { await health.refresh() }
            .sheet(isPresented: $viewModel.isShowingLogWeight) { LogWeightView() }
            .sheet(isPresented: $viewModel.isShowingSettings) { GoalSetupView(profile: profiles.first) }
            .sheet(isPresented: $viewModel.isShowingCoachChat) {
                NavigationStack { CoachChatView() }
            }
            .fullScreenCover(isPresented: $viewModel.isShowingEmergencyReset) { EmergencyResetView() }
            .onChange(of: health.latestWeightLbs, initial: true) { _, weight in
                viewModel.markAchievedMilestones(milestones, currentWeight: weight)
            }
        }
    }
}

#Preview {
    DashboardView()
        .environment(HealthKitManager())
        .modelContainer(for: [GoalProfile.self, WeightMilestone.self, CoachMessage.self], inMemory: true)
        .preferredColorScheme(.dark)
}
