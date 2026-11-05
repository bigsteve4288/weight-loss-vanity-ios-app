import Foundation

/// The one thing worth doing next, shown at the top of the dashboard. Always about a habit the user
/// controls (weighing in, logging, reviewing the plan), never about eating less or exercising more.
struct NextAction: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case logWeight
        case openGoalSettings
        /// Food is logged in another app (e.g. Carb Manager), so there's nothing to open here.
        case logFood
        case reflect
        case none
    }

    let kind: Kind
    let title: String
    let detail: String
    let symbol: String
}

enum NextActionAdvisor {
    /// Weigh-in days needed in the last 14 for a measured pace (mirrors `WeightTrendService`).
    static let weighInDaysForPace = WeightTrendService.fourteenDayRequirement.days

    static func advise(_ snapshot: TargetSnapshot, now: Date = .now, calendar: Calendar = .current) -> NextAction {
        let plan = snapshot.plan
        let intake = snapshot.intake
        let trend = snapshot.trend
        let weighedInToday = trend.latestReading.map { calendar.isDate($0, inSameDayAs: now) } ?? false

        if snapshot.currentWeight == nil {
            return NextAction(kind: .logWeight, title: "Log your first weigh-in", detail: "Your plan and pace start from a current weight.", symbol: "scalemass.fill")
        }
        if plan.feasibility == .achieved {
            return NextAction(kind: .openGoalSettings, title: "Set your next goal", detail: "You reached \(plan.targetWeight.formatted(oneDecimal)) lb. Decide what comes next in Goal Settings.", symbol: "crown.fill")
        }
        if plan.feasibility == .deadlinePassed {
            return NextAction(kind: .openGoalSettings, title: "Choose a new target date", detail: "Your progress is kept. Pick a date that fits a steady pace.", symbol: "calendar.badge.exclamationmark")
        }
        // Safety comes before anything about the scale.
        if intake.lowIntakeConcern {
            return NextAction(kind: .logFood, title: "Check today's intake", detail: intake.summary, symbol: "fork.knife")
        }
        if plan.weightIsStale || trend.isStale {
            let days = trend.latestReading.flatMap { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: now)).day }
            let detail = days.map { "Your last weigh-in was \($0) days ago. A current weight keeps the plan accurate." }
                ?? "Your last weigh-in is over a week old. A current weight keeps the plan accurate."
            return NextAction(kind: .logWeight, title: "Weigh in", detail: detail, symbol: "scalemass.fill")
        }
        if snapshot.status == .goalNeedsAdjustment {
            return NextAction(kind: .openGoalSettings, title: "Review your target date", detail: "Your date needs a faster pace than is sustainable. Moving it is up to you; the plan stays steady either way.", symbol: "calendar.badge.clock")
        }
        if intake.state == .missingLogs {
            return NextAction(kind: .logFood, title: "Log today's meals", detail: intake.summary, symbol: "square.and.pencil")
        }
        if trend.primaryWindow == nil, !weighedInToday {
            let recent = trend.dailyWeights.filter { WeightTrendService.dayIndex($0.date, from: now, calendar: calendar) > -14 }.count
            let needed = weighInDaysForPace - recent
            let detail = needed > 1
                ? "\(needed) more weigh-in days unlock your measured pace."
                : needed == 1
                    ? "One more weigh-in day unlocks your measured pace."
                    : "Keep weighing in this week to unlock your measured pace."
            return NextAction(kind: .logWeight, title: "Weigh in today", detail: detail, symbol: "scalemass.fill")
        }
        if snapshot.status == .needsAttention {
            return NextAction(kind: .reflect, title: "Pick one change for this week", detail: "Your trend has flattened. Choose one habit to tighten, like logging every meal or a steady bedtime. No crash fixes.", symbol: "lightbulb.fill")
        }
        if !weighedInToday {
            return NextAction(kind: .logWeight, title: "Weigh in today", detail: "Regular weigh-ins make your 7-day average more reliable.", symbol: "scalemass.fill")
        }
        switch intake.state {
        case .noEntriesYet, .inProgress:
            return NextAction(kind: .logFood, title: "Log meals as you go", detail: "Weigh-in done. Logging each meal keeps today's numbers honest.", symbol: "fork.knife")
        case .complete:
            return NextAction(kind: .none, title: "You're done for today", detail: "Weigh-in and meals are logged. Same routine tomorrow.", symbol: "checkmark.seal.fill")
        case .notTracking, .missingLogs:
            return NextAction(kind: .none, title: "Weigh-in done", detail: "Keep the routine steady. Same time tomorrow.", symbol: "checkmark.seal.fill")
        }
    }

    private static let oneDecimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
}

extension TargetSnapshot {
    /// Short notes on what's missing or estimated in today's picture. Empty when the data is solid.
    var dataGaps: [String] {
        var gaps: [String] = []
        if currentWeight != nil, trend.isStale { gaps.append("Weigh-in over a week old") }
        if currentWeight != nil, !trend.isStale, trend.primaryWindow == nil { gaps.append("Too few weigh-ins for a pace") }
        if intake.state == .notTracking { gaps.append("Food not tracked in Apple Health") }
        if !energy.isReliable || energy.includesEstimates { gaps.append("Burn partly estimated") }
        return gaps
    }

    /// One line for the projected goal date, at month precision, or why there isn't one.
    var projectionSummary: String? {
        switch forecast.state {
        case .goalReached:
            return nil
        case .projected:
            guard let date = forecast.projectedGoalDate else { return nil }
            return "Goal projected \(date.formatted(.dateTime.month(.abbreviated).year())) · \(forecast.confidence.rawValue) confidence"
        case .notProjected:
            return "Goal date not projected yet"
        }
    }
}
