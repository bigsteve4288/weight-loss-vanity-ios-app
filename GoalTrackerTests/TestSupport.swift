import Foundation
@testable import GoalTracker

/// Fixed calendar and dates so tests don't depend on the machine's time zone or the current day.
enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Wake 5:30, breakfast 7:30, lunch 12:00, dinner 6:30 PM, bed 10:00 PM (the app's defaults).
    static let rhythm = DailyRhythm(wake: 330, breakfast: 450, lunch: 720, dinner: 1110, bed: 1320)

    static func log(
        calories: Double = 0,
        protein: Double = 0,
        entries: [Date] = [],
        hasProteinData: Bool = true,
        loggedInPastWeek: Bool = true
    ) -> NutritionLog {
        NutritionLog(
            calories: calories, proteinGrams: protein, carbsGrams: 0, fatGrams: 0,
            entryTimes: entries, hasProteinData: hasProteinData, loggedInPastWeek: loggedInPastWeek
        )
    }

    static func workout(
        _ start: Date,
        minutes: Double,
        reported: Double?,
        sampled: Double,
        source: String = "Peloton"
    ) -> WorkoutEnergy {
        WorkoutEnergy(
            id: UUID(), start: start, end: start.addingTimeInterval(minutes * 60), source: source,
            reportedCalories: reported, sampledCaloriesInWindow: sampled
        )
    }

    /// Daily weigh-ins ending at `end`, losing `perDay` pounds a day.
    static func history(endingAt end: Date, days: Int, from start: Double, perDay: Double) -> [WeightPoint] {
        (0..<days).map { offset in
            WeightPoint(
                date: calendar.date(byAdding: .day, value: offset - days + 1, to: end)!,
                pounds: start - Double(offset) * perDay
            )
        }
    }
}
