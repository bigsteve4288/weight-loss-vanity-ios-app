import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    var isShowingEmergencyReset = false
    var isShowingLogWeight = false
    var isShowingSettings = false

    func snapshot(profile: GoalProfile, health: HealthKitManager, now: Date = .now) -> TargetSnapshot {
        TargetEngine.snapshot(.init(
            startWeight: profile.startWeightLbs,
            lossGoal: profile.lossGoalLbs,
            targetDate: profile.targetDate,
            currentWeight: health.latestWeightLbs,
            history: health.weightHistory,
            caloriesConsumed: health.caloriesConsumed,
            activeBurn: health.activeEnergyBurned,
            basalBurn: health.basalEnergyBurned,
            restingCaloriesPerDay: profile.restingCaloriesPerDay,
            now: now
        ))
    }

    func markAchievedMilestones(_ milestones: [WeightMilestone], currentWeight: Double?) {
        guard let currentWeight else { return }
        for milestone in milestones where milestone.achievedDate == nil && currentWeight <= milestone.targetWeightLbs {
            milestone.achievedDate = .now
        }
    }
}
