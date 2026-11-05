import Foundation

/// One day's totals from Apple Health. `nil` means nothing was recorded, which is different from zero.
struct DailyHealthTotals: Equatable, Sendable {
    let day: Date
    let caloriesConsumed: Double?
    let proteinGrams: Double?
    let activeEnergy: Double?
}

/// Plain values copied out of SwiftData models, so the summary is pure and testable.
struct GoalChangeRecord: Equatable, Sendable {
    let date: Date
    let targetWeight: Double
    let targetDate: Date
    let intensity: GoalIntensity
}

struct VerdictRecord: Equatable, Sendable {
    let date: Date
    let grade: String
    let headline: String
    let actions: [String]
}

struct MilestoneRecord: Equatable, Sendable {
    let title: String
    let weight: Double
    let achieved: Date?
}

/// A concise, structured history for the AI Coach. Summarized (weekly weights, daily totals) rather than
/// raw samples, to keep requests small and cheap and to send no more health data than a question needs.
/// Everything listed came from Apple Health or the app; anything absent is stated as absent.
enum CoachHistory {
    struct Input {
        var weights: [WeightPoint]
        var daily: [DailyHealthTotals]
        /// Workouts, any order. Duplicates of the same session are removed here.
        var workouts: [WorkoutSummary]
        var goalChanges: [GoalChangeRecord] = []
        var verdicts: [VerdictRecord] = []
        var milestones: [MilestoneRecord] = []
        var now: Date = .now
        var calendar: Calendar = .current
    }

    static let weeksOfWeight = 12
    static let daysOfDetail = 14

    static func lines(_ input: Input) -> [String] {
        let calendar = input.calendar
        let today = calendar.startOfDay(for: input.now)
        let workouts = uniqueWorkouts(input.workouts)
        var dayFormat = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        dayFormat.timeZone = calendar.timeZone
        var monthFormat = Date.FormatStyle.dateTime.month(.wide)
        monthFormat.timeZone = calendar.timeZone
        var dateFormat = Date.FormatStyle(date: .abbreviated, time: .omitted)
        dateFormat.timeZone = calendar.timeZone
        var lines = ["HISTORY (from Apple Health and the app; if something isn't listed, there's no data for it)"]

        // Weekly weight: the median of each 7-day block's daily weights, newest last.
        lines.append("- Weekly weight, 7-day blocks ending today:")
        let daily = WeightTrendService.dailyWeights(input.weights, calendar: calendar)
        var weekLines: [String] = []
        for week in (0..<weeksOfWeight).reversed() {
            let end = calendar.date(byAdding: .day, value: -7 * week, to: today) ?? today
            guard let start = calendar.date(byAdding: .day, value: -6, to: end) else { continue }
            let readings = daily.filter { $0.date >= start && $0.date <= end }
            guard !readings.isEmpty else { continue }
            let median = WeightTrendService.median(readings.map(\.pounds))
            weekLines.append("  • \(start.formatted(dayFormat))–\(end.formatted(dayFormat)): \(median.formatted(lbs)) lb (\(readings.count) weigh-in day\(readings.count == 1 ? "" : "s"))")
        }
        lines.append(contentsOf: weekLines.isEmpty ? ["  • No weigh-ins in the last \(weeksOfWeight) weeks."] : weekLines)

        // Day by day for the last two weeks: food, protein, active energy and workouts.
        lines.append("- Last \(daysOfDetail) days, day by day:")
        for offset in (0..<daysOfDetail).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let totals = input.daily.first { calendar.isDate($0.day, inSameDayAs: day) }
            var parts: [String] = []
            if let calories = totals?.caloriesConsumed, calories > 0 {
                var food = "\(calories.formatted(kcal)) kcal logged"
                if let protein = totals?.proteinGrams, protein > 0 { food += ", \(protein.formatted(kcal)) g protein" }
                parts.append(food)
            } else {
                parts.append("no food logged")
            }
            if let active = totals?.activeEnergy, active > 0 {
                parts.append("\(active.formatted(kcal)) active kcal")
            }
            let sessions = workouts.filter { calendar.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
            parts.append(sessions.isEmpty ? "no workouts" : sessions.map { "\($0.activityName) \(Int(($0.duration / 60).rounded())) min (\($0.source))" }.joined(separator: ", "))
            if let weight = daily.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                parts.append("weighed \(weight.pounds.formatted(lbs)) lb")
            }
            let label = offset == 0 ? "\(day.formatted(dayFormat)) (today, in progress)" : day.formatted(dayFormat)
            lines.append("  • \(label): " + parts.joined(separator: "; "))
        }

        // Workout counts by calendar month, so "this month" questions have an exact answer.
        let thisMonth = calendar.dateInterval(of: .month, for: today)
        if let thisMonth {
            let inMonth = workouts.filter { thisMonth.contains($0.start) && $0.start <= input.now }
            lines.append("- Workouts this month (\(thisMonth.start.formatted(monthFormat)) 1 to today): \(summary(inMonth)).")
            if let lastStart = calendar.date(byAdding: .month, value: -1, to: thisMonth.start),
               let lastMonth = calendar.dateInterval(of: .month, for: lastStart),
               let earliest = workouts.map(\.start).min(), earliest <= lastMonth.start.addingTimeInterval(3 * 86_400) {
                // Only reported when the fetched history covers that month, so a partial month isn't passed off as whole.
                let inLast = workouts.filter { lastMonth.contains($0.start) }
                lines.append("- Workouts last month (\(lastMonth.start.formatted(monthFormat))): \(summary(inLast)).")
            }
        }

        if !input.goalChanges.isEmpty {
            lines.append("- Goal changes (most recent last):")
            for change in input.goalChanges.sorted(by: { $0.date < $1.date }).suffix(5) {
                lines.append("  • \(change.date.formatted(dayFormat)): target \(change.targetWeight.formatted(lbs)) lb by \(change.targetDate.formatted(dateFormat)), \(change.intensity.label) mode")
            }
        }
        if !input.verdicts.isEmpty {
            lines.append("- Recent coach verdicts (most recent last):")
            for verdict in input.verdicts.sorted(by: { $0.date < $1.date }).suffix(3) {
                var line = "  • \(verdict.date.formatted(dayFormat)): grade \(verdict.grade), \"\(verdict.headline)\""
                if !verdict.actions.isEmpty { line += ". Actions given: " + verdict.actions.joined(separator: "; ") }
                lines.append(line)
            }
        }
        let achieved = input.milestones.filter { $0.achieved != nil }.sorted { $0.weight > $1.weight }
        if !achieved.isEmpty {
            lines.append("- Milestones reached: " + achieved.map { "\($0.title) (\($0.weight.formatted(lbs)) lb)" }.joined(separator: ", ") + ".")
        }
        lines.append("- Not available to you: sleep, steps, heart rate, meal contents, and anything before these dates.")
        return lines
    }

    /// Drops second recordings of the same session (e.g. Apple Watch and Peloton) with the same rule as today's burn.
    static func uniqueWorkouts(_ workouts: [WorkoutSummary]) -> [WorkoutSummary] {
        let energy = workouts.map {
            WorkoutEnergy(id: $0.id, start: $0.start, end: $0.end, source: $0.source, reportedCalories: $0.calories, sampledCaloriesInWindow: 0)
        }
        let duplicates = Set(EnergyBalance.removeDuplicates(energy).duplicates.map(\.id))
        return workouts.filter { !duplicates.contains($0.id) }
    }

    private static func summary(_ workouts: [WorkoutSummary]) -> String {
        guard !workouts.isEmpty else { return "none recorded" }
        let minutes = Int((workouts.map(\.duration).reduce(0, +) / 60).rounded())
        let kinds = Dictionary(grouping: workouts, by: \.activityName)
            .sorted { $0.value.count > $1.value.count }
            .map { "\($0.value.count) \($0.key.lowercased())" }
            .joined(separator: ", ")
        return "\(workouts.count) workout\(workouts.count == 1 ? "" : "s"), \(minutes / 60) h \(minutes % 60) min total (\(kinds))"
    }

    private static let lbs = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
    private static let kcal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)).grouping(.automatic)
}
