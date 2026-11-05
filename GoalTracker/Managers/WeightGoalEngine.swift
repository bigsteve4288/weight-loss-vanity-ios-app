import Foundation

/// The range of weekly loss the app will plan around. These are common general guidelines for
/// adults (roughly 0.5–2 lb/week, or up to about 1% of body weight per week), not personal medical
/// advice; anyone with a medical condition should set their pace with their doctor.
struct PacePolicy: Equatable, Sendable {
    /// Slowest pace still treated as active weight loss.
    var minimumPoundsPerWeek = 0.5
    /// A comfortable everyday pace; projections use it as the steady end of the range.
    var typicalPoundsPerWeek = 1.0
    /// Upper bound as a share of current body weight per week.
    var maximumBodyWeightFractionPerWeek = 0.01
    /// Absolute upper bound, whatever the body weight.
    var maximumPoundsPerWeek = 2.0
    /// The largest daily deficit the app will ever suggest.
    var maximumDailyDeficit = 1000.0

    static let standard = PacePolicy()

    /// The fastest pace the app plans around for someone at `weight`.
    func sustainableMaximum(forWeight weight: Double) -> Double {
        min(max(weight * maximumBodyWeightFractionPerWeek, minimumPoundsPerWeek), maximumPoundsPerWeek)
    }

    /// The steady pace for someone at `weight`, never above their sustainable maximum.
    func typicalPace(forWeight weight: Double) -> Double {
        min(typicalPoundsPerWeek, sustainableMaximum(forWeight: weight))
    }
}

enum GoalFeasibility: Equatable, Sendable {
    case achieved
    /// The deadline needs a steady pace or slower.
    case comfortable
    /// The deadline needs a pace between steady and the sustainable maximum.
    case ambitious
    /// The deadline needs more than the sustainable maximum. The plan caps the pace instead.
    case exceedsSustainable
    case deadlinePassed

    var label: String {
        switch self {
        case .achieved: "Goal reached"
        case .comfortable: "Comfortable pace"
        case .ambitious: "Ambitious but sustainable"
        case .exceedsSustainable: "Deadline needs a faster pace than is sustainable"
        case .deadlinePassed: "Deadline passed"
        }
    }
}

/// Three separate things: what the user is aiming for, what the deadline alone would demand,
/// and the sustainable plan the app actually coaches toward.
struct GoalPlan: Equatable, Sendable {
    // 1. The aspiration.
    let targetWeight: Double
    let targetDate: Date
    let daysRemaining: Int
    let poundsRemaining: Double

    // 2. What the deadline alone would demand. Shown for context, never used as an instruction.
    let requiredPoundsPerWeek: Double
    /// Rough 3,500 kcal/lb estimate of the daily deficit the deadline implies.
    let requiredDailyDeficitEstimate: Double

    // 3. The plan the app coaches toward.
    let feasibility: GoalFeasibility
    /// The pace range used for projections: steady pace up to the sustainable maximum.
    let sustainablePace: ClosedRange<Double>
    let recommendedPoundsPerWeek: Double
    /// Rough 3,500 kcal/lb estimate, capped at `PacePolicy.maximumDailyDeficit`.
    let recommendedDailyDeficitEstimate: Double
    /// Likely weight on the deadline at a sustainable pace (never below the target). `nil` once the deadline has passed.
    let projectedWeightAtDeadline: ClosedRange<Double>?
    /// When the target would be reached at a sustainable pace: earliest (max pace) … steady pace.
    let projectedTargetDate: ClosedRange<Date>?
    /// A deadline that fits a steady pace, offered when the current one doesn't fit or has passed.
    let suggestedTargetDate: Date?
    /// True when the latest weigh-in is too old to plan from confidently.
    let weightIsStale: Bool

    var needsAdjustment: Bool { feasibility == .exceedsSustainable || feasibility == .deadlinePassed }

    static let estimateDisclaimer = "Calorie figures use the 3,500 kcal per pound rule of thumb. It's a rough estimate that tends to overstate loss over months, because your burn falls as you lose weight. Your measured trend is the better guide."
}

/// Turns the goal settings and current weight into a sustainable plan. Pure, so it's unit tested.
enum WeightGoalEngine {
    static let caloriesPerPound = 3500.0
    /// A weigh-in older than this makes the plan low-confidence.
    static let staleWeightDays = 7

    struct Input {
        var targetWeight: Double
        var targetDate: Date
        var currentWeight: Double
        var latestWeightDate: Date?
        var policy: PacePolicy = .standard
        var now: Date = .now
        var calendar: Calendar = .current
    }

    static func plan(_ input: Input) -> GoalPlan {
        let calendar = input.calendar
        let policy = input.policy
        let remaining = max(input.currentWeight - input.targetWeight, 0)
        let days = daysRemaining(from: input.now, to: input.targetDate, calendar: calendar)
        let weeks = Double(max(days, 1)) / 7

        let maximum = policy.sustainableMaximum(forWeight: input.currentWeight)
        let steady = policy.typicalPace(forWeight: input.currentWeight)
        let required = remaining / weeks

        let feasibility: GoalFeasibility
        if remaining <= 0 {
            feasibility = .achieved
        } else if days <= 0 {
            feasibility = .deadlinePassed
        } else if required <= steady {
            feasibility = .comfortable
        } else if required <= maximum {
            feasibility = .ambitious
        } else {
            feasibility = .exceedsSustainable
        }

        let recommended: Double = switch feasibility {
        case .achieved: 0
        // Slower than the minimum is fine when that's all the deadline needs.
        case .comfortable, .ambitious: required
        // Get as close as is sustainable; never push past the cap to chase the date.
        case .exceedsSustainable: maximum
        case .deadlinePassed: steady
        }
        let recommendedDeficit = min(recommended * caloriesPerPound / 7, policy.maximumDailyDeficit)

        var projectedAtDeadline: ClosedRange<Double>?
        if days > 0, remaining > 0 {
            let best = max(input.currentWeight - maximum * weeks, input.targetWeight)
            let steadyWeight = max(input.currentWeight - steady * weeks, input.targetWeight)
            projectedAtDeadline = best...steadyWeight
        }

        var projectedDate: ClosedRange<Date>?
        var suggested: Date?
        if remaining > 0 {
            let earliest = date(after: remaining / maximum, from: input.now, calendar: calendar)
            let steadyDate = date(after: remaining / steady, from: input.now, calendar: calendar)
            projectedDate = earliest...steadyDate
            if feasibility == .exceedsSustainable || feasibility == .deadlinePassed {
                suggested = steadyDate
            }
        }

        let stale = input.latestWeightDate.map {
            (calendar.dateComponents([.day], from: $0, to: input.now).day ?? 0) > staleWeightDays
        } ?? true

        return GoalPlan(
            targetWeight: input.targetWeight,
            targetDate: input.targetDate,
            daysRemaining: days,
            poundsRemaining: remaining,
            requiredPoundsPerWeek: days > 0 ? required : 0,
            requiredDailyDeficitEstimate: days > 0 ? remaining * caloriesPerPound / Double(days) : 0,
            feasibility: feasibility,
            sustainablePace: steady...maximum,
            recommendedPoundsPerWeek: recommended,
            recommendedDailyDeficitEstimate: recommendedDeficit,
            projectedWeightAtDeadline: projectedAtDeadline,
            projectedTargetDate: projectedDate,
            suggestedTargetDate: suggested,
            weightIsStale: stale
        )
    }

    static func daysRemaining(from now: Date, to target: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day ?? 0
    }

    private static func date(after weeks: Double, from now: Date, calendar: Calendar) -> Date {
        let days = Int((weeks * 7).rounded(.up))
        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
    }
}
