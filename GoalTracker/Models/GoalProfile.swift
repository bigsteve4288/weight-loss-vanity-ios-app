import Foundation
import SwiftData

/// The single goal the app is tracking toward. Only one instance is expected.
@Model
final class GoalProfile {
    var startDate: Date
    var startWeightLbs: Double
    var lossGoalLbs: Double
    var targetDate: Date
    /// Fallback for resting burn when Apple Health has no basal energy data (e.g. no Apple Watch).
    var restingCaloriesPerDay: Double
    var notificationsEnabled: Bool
    var notificationHour: Int
    var notificationMinute: Int

    init(
        startWeightLbs: Double,
        lossGoalLbs: Double = 34,
        targetDate: Date,
        restingCaloriesPerDay: Double = 1800,
        startDate: Date = .now
    ) {
        self.startDate = startDate
        self.startWeightLbs = startWeightLbs
        self.lossGoalLbs = lossGoalLbs
        self.targetDate = targetDate
        self.restingCaloriesPerDay = restingCaloriesPerDay
        self.notificationsEnabled = false
        self.notificationHour = 7
        self.notificationMinute = 0
    }

    var targetWeightLbs: Double { startWeightLbs - lossGoalLbs }
}
