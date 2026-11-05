import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    var isShowingEmergencyReset = false
    var isShowingLogWeight = false
    var isShowingSettings = false

    func snapshot(profile: GoalProfile, health: HealthKitManager, now: Date = .now) -> TargetSnapshot {
        TargetEngine.snapshot(profile: profile, health: health, now: now)
    }

    func markAchievedMilestones(_ milestones: [WeightMilestone], currentWeight: Double?) {
        guard let currentWeight else { return }
        for milestone in milestones where milestone.achievedDate == nil && currentWeight <= milestone.targetWeightLbs {
            milestone.achievedDate = .now
        }
    }
}

extension TargetEngine {
    /// The one place goal settings and Health data are combined, so the dashboard and the coach agree.
    @MainActor
    static func snapshot(profile: GoalProfile, health: HealthKitManager, now: Date = .now) -> TargetSnapshot {
        snapshot(.init(
            startWeight: profile.startWeightLbs,
            lossGoal: profile.lossGoalLbs,
            targetDate: profile.targetDate,
            currentWeight: health.latestWeightLbs,
            latestWeightDate: health.latestWeightDate,
            history: health.weightHistory,
            nutrition: health.nutrition,
            activeBurn: health.activeEnergyBurned,
            basalBurn: health.basalEnergyBurned,
            workouts: health.workoutEnergyToday,
            restingCaloriesPerDay: profile.restingCaloriesPerDay,
            rhythm: profile.dailyRhythm,
            intensity: profile.intensity,
            clinicianMaxPoundsPerWeek: profile.effectiveClinicianMaxPoundsPerWeek,
            now: now
        ))
    }
}
