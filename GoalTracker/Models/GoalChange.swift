import Foundation
import SwiftData

/// A record of the goal as it was set at a point in time. Written whenever the user changes their
/// goal, never by the app on its own: forecasts are informational and don't touch the goal.
@Model
final class GoalChange {
    var date: Date
    var startWeightLbs: Double
    var targetWeightLbs: Double
    var targetDate: Date
    var intensityRaw: String

    init(date: Date = .now, startWeightLbs: Double, targetWeightLbs: Double, targetDate: Date, intensity: GoalIntensity) {
        self.date = date
        self.startWeightLbs = startWeightLbs
        self.targetWeightLbs = targetWeightLbs
        self.targetDate = targetDate
        self.intensityRaw = intensity.rawValue
    }

    convenience init(profile: GoalProfile, date: Date = .now) {
        self.init(
            date: date, startWeightLbs: profile.startWeightLbs, targetWeightLbs: profile.targetWeightLbs,
            targetDate: profile.targetDate, intensity: profile.intensity
        )
    }

    var intensity: GoalIntensity { GoalIntensity(rawValue: intensityRaw) ?? .standard }

    /// Whether `profile` differs from this record in anything the user would call "the goal".
    func differs(from profile: GoalProfile) -> Bool {
        abs(startWeightLbs - profile.startWeightLbs) > 0.05
            || abs(targetWeightLbs - profile.targetWeightLbs) > 0.05
            || !Calendar.current.isDate(targetDate, inSameDayAs: profile.targetDate)
            || intensityRaw != profile.goalIntensityRaw
    }
}
