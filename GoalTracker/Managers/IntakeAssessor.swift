import Foundation

/// Today's food log as read from Apple Health (Carb Manager writes into it).
struct NutritionLog: Equatable, Sendable {
    var calories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    /// Start times of today's dietary-energy samples, one per logged food or meal.
    var entryTimes: [Date]
    /// False when calories were logged but no protein samples exist (the app may not sync macros).
    var hasProteinData: Bool
    /// Whether any food was logged in the seven days before today. False usually means the user
    /// doesn't log food in Apple Health at all (or Health read access was declined).
    var loggedInPastWeek: Bool

    static let empty = NutritionLog(
        calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0, entryTimes: [], hasProteinData: false, loggedInPastWeek: false
    )
}

/// How complete today's food log looks for this time of day.
enum IntakeState: Equatable, Sendable {
    /// No food data today or in the past week: nutrition isn't being tracked in Apple Health.
    case notTracking
    /// Nothing logged yet, and no meal is due yet. Normal early in the day.
    case noEntriesYet
    /// Meals that should have happened by now have nothing logged against them.
    case missingLogs
    /// Logging is keeping up; the day isn't over.
    case inProgress
    /// The eating day is over and the log covers it.
    case complete

    var label: String {
        switch self {
        case .notTracking: "NOT TRACKED"
        case .noEntriesYet: "NOT STARTED"
        case .missingLogs: "LOG INCOMPLETE"
        case .inProgress: "IN PROGRESS"
        case .complete: "DAY LOGGED"
        }
    }
}

enum Confidence: String, Equatable, Comparable, Sendable {
    case low, medium, high

    static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.low, .medium, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

struct IntakeAssessment: Equatable, Sendable {
    let state: IntakeState
    /// Meals whose time (plus a grace period) has passed.
    let mealsDue: Int
    /// Separate eating occasions logged today (foods within an hour of each other count as one).
    let mealsLogged: Int
    /// True once the eating day is over (two hours after dinner, or bedtime, whichever is first).
    let isEatingDayOver: Bool
    /// A fully logged day with intake below the floor. Phrased as a check-in, never as praise or blame.
    let lowIntakeConcern: Bool
    /// Calories were logged but no protein data reached Apple Health.
    let proteinDataMissing: Bool
    let confidence: Confidence

    /// Only a complete day can be judged on its deficit; anything else is "so far".
    var canJudgeDeficit: Bool { state == .complete }

    /// A neutral sentence for the dashboard and the coach. Never treats a partial log as restriction.
    var summary: String {
        switch state {
        case .notTracking:
            return "No food logged in Apple Health this week, so intake isn't part of today's picture."
        case .noEntriesYet:
            return "Nothing logged yet today, and that's normal this early. Log meals as you go."
        case .missingLogs:
            let gap = max(mealsDue - mealsLogged, 1)
            return gap == 1
                ? "One meal that's likely happened isn't logged yet. Log it when you can so today's numbers are accurate."
                : "\(gap) meals that have likely happened aren't logged yet. Log them when you can so today's numbers are accurate."
        case .inProgress:
            return "You've started logging. Aim for adequate protein and balanced meals through the rest of the day."
        case .complete:
            return lowIntakeConcern
                ? "Logged intake is low for a full day. If that's accurate, make sure you're eating enough to fuel yourself. If meals are missing, add them."
                : "Today's meals are logged."
        }
    }
}

/// Judges today's food log against the time of day and the user's own meal times, so a 9 AM
/// breakfast entry is read as "started logging", not as the whole day's intake.
enum IntakeAssessor {
    /// How long after a meal's usual time before it counts as "should be logged by now".
    static let mealGraceMinutes = 90
    /// Foods logged within this many minutes of each other are one eating occasion.
    static let mealClusterMinutes = 60
    /// The eating day is considered over this long after dinner (or at bedtime, if earlier).
    static let dayOverMinutesAfterDinner = 120
    /// A complete day below this is flagged for a gentle check-in. A general floor, not a personal target.
    static let lowIntakeFloor = 1200.0

    static func assess(
        _ log: NutritionLog,
        rhythm: DailyRhythm,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> IntakeAssessment {
        let nowMinutes = minutesAfterMidnight(now, calendar: calendar)
        // Before wake-up (including after midnight for night owls) nothing is due yet.
        let isBeforeWake = nowMinutes < rhythm.wake
        let mealTimes = [rhythm.breakfast, rhythm.lunch, rhythm.dinner].compactMap { $0 }
        let mealsDue = isBeforeWake ? 0 : mealTimes.filter { nowMinutes >= $0 + mealGraceMinutes }.count
        let mealsLogged = occasions(in: log.entryTimes)

        let bed = rhythm.bed < rhythm.wake ? rhythm.bed + 1440 : rhythm.bed
        let dayOverAt = min(rhythm.dinner + dayOverMinutesAfterDinner, bed)
        let isEatingDayOver = !isBeforeWake && nowMinutes >= dayOverAt

        let state: IntakeState
        if log.entryTimes.isEmpty, log.calories <= 0 {
            if !log.loggedInPastWeek {
                state = .notTracking
            } else if mealsDue == 0 {
                state = .noEntriesYet
            } else {
                state = .missingLogs
            }
        } else if mealsLogged < mealsDue - 1 || (isEatingDayOver && mealsLogged < min(mealsDue, 2)) {
            // Allow one skipped or combined meal before calling the log incomplete.
            state = .missingLogs
        } else if isEatingDayOver {
            state = .complete
        } else {
            state = .inProgress
        }

        let confidence: Confidence = switch state {
        case .complete: .high
        case .inProgress, .noEntriesYet: .medium
        case .missingLogs, .notTracking: .low
        }

        return IntakeAssessment(
            state: state,
            mealsDue: mealsDue,
            mealsLogged: mealsLogged,
            isEatingDayOver: isEatingDayOver,
            lowIntakeConcern: state == .complete && log.calories < lowIntakeFloor,
            proteinDataMissing: log.calories > 0 && !log.hasProteinData,
            confidence: confidence
        )
    }

    /// Number of separate eating occasions: entries more than `mealClusterMinutes` apart start a new one.
    static func occasions(in times: [Date]) -> Int {
        let sorted = times.sorted()
        guard var last = sorted.first else { return 0 }
        var count = 1
        for time in sorted.dropFirst() {
            if time.timeIntervalSince(last) > Double(mealClusterMinutes * 60) { count += 1 }
            last = time
        }
        return count
    }

    private static func minutesAfterMidnight(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
