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
                        StatusCard(snapshot: snapshot)
                        EmergencyResetButton { viewModel.isShowingEmergencyReset = true }
                        TargetCard(snapshot: snapshot, startWeight: profile.startWeightLbs)
                        CountdownCard(targetDate: profile.targetDate)
                        DeficitCard(snapshot: snapshot, consumed: health.caloriesConsumed, active: health.activeEnergyBurned)
                        MacrosCard(carbs: health.carbsGrams, protein: health.proteinGrams, fat: health.fatGrams)
                        WorkoutsCard(workouts: health.recentWorkouts)
                        if !health.weightHistory.isEmpty {
                            WeightTrendCard(points: health.weightHistory, target: snapshot.targetWeight)
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
            .navigationTitle("GoalTracker")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Goal Settings", systemImage: "gearshape.fill") { viewModel.isShowingSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log Weight", systemImage: "scalemass.fill") { viewModel.isShowingLogWeight = true }
                }
            }
            .refreshable { await health.refresh() }
            .sheet(isPresented: $viewModel.isShowingLogWeight) { LogWeightView() }
            .sheet(isPresented: $viewModel.isShowingSettings) { GoalSetupView(profile: profiles.first) }
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
        .modelContainer(for: [GoalProfile.self, WeightMilestone.self], inMemory: true)
        .preferredColorScheme(.dark)
}
