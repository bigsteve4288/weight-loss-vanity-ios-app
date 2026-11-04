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

    // The user's day, in minutes after midnight. Reminder times are derived from these.
    var wakeMinutes: Int = 330
    /// `nil` when they skip breakfast (e.g. fasting until lunch).
    var breakfastMinutes: Int? = 450
    var lunchMinutes: Int = 720
    var dinnerMinutes: Int = 1110
    var bedMinutes: Int = 1320
    /// Per-reminder tweaks on top of the derived times, keyed by `ReminderSlot.rawValue`:
    /// minutes after midnight, or -1 to turn that reminder off.
    var reminderOverrides: [String: Int] = [:]
    var hasSetDailyRhythm: Bool = false

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
    }

    var targetWeightLbs: Double { startWeightLbs - lossGoalLbs }
}
