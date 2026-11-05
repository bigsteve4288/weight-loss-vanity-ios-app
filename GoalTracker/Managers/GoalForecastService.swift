import Foundation

/// Goal trajectory: is the observed trend fast enough for the user's own deadline? Separate from the
/// daily accountability verdict, and never weakened to look better.
enum PaceStatus: Equatable, Sendable {
    case aheadOfPace
    case onPace
    case behindPace
    case insufficientData
    case goalReached
    case deadlinePassed

    var title: String {
        switch self {
        case .aheadOfPace: "AHEAD OF PACE"
        case .onPace: "ON PACE"
        case .behindPace: "BEHIND PACE"
        case .insufficientData: "INSUFFICIENT DATA"
        case .goalReached: "GOAL REACHED"
        case .deadlinePassed: "DEADLINE PASSED"
        }
    }
}

struct PaceAssessment: Equatable, Sendable {
    /// Weekly loss the user's own deadline requires: remaining ÷ days left × 7. Zero once reached or passed.
    let requiredPoundsPerWeek: Double
    /// Observed weekly loss from weigh-ins (positive = losing, negative = gaining), or nil without enough history.
    let actualPoundsPerWeek: Double?
    /// actual − required. Negative = behind.
    let paceDifference: Double?
    let tolerance: Double
    let status: PaceStatus
    /// Weight is trending up, reported as such rather than as "slow loss".
    let isGaining: Bool

    static let insufficientDataMessage = "Not enough weight history to calculate a reliable pace."

    /// One line describing the gap, in plain numbers.
    var differenceSummary: String? {
        guard let paceDifference, status == .aheadOfPace || status == .onPace || status == .behindPace else { return nil }
        let amount = abs(paceDifference).formatted(.number.precision(.fractionLength(1)))
        switch status {
        case .aheadOfPace: return "\(amount) lb/week faster than required"
        case .behindPace: return "\(amount) lb/week below required pace"
        default: return "Within \(tolerance.formatted(.number.precision(.fractionLength(1)))) lb/week of required pace"
        }
    }
}

struct GoalForecast: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case goalReached
        case projected
        /// No honest projection is possible; `reason` says why.
        case notProjected(reason: String)
    }

    let state: State
    /// The weekly rate the forecast assumes (the slower of the 14- and 28-day trends).
    let paceUsed: Double?
    /// Likely weight on the user's deadline. Nil if the deadline has passed, it's too far out, or there's no reliable trend.
    let projectedWeightAtDeadline: ClosedRange<Double>?
    /// When the target would be reached at the observed pace (central estimate). Display at month precision.
    let projectedGoalDate: Date?
    let reachesTargetByDeadline: Bool?
    let confidence: Confidence
}

/// Projects forward from observed weigh-ins. Conservative on purpose: it uses the slower of the
/// recent trends, widens to a range, lowers confidence for long horizons, and refuses to project
/// from a flat, rising, stale or thin trend rather than inventing a date.
enum GoalForecastService {
    /// Below this observed loss rate, no completion date is projected.
    static let minimumProjectablePace = 0.1
    /// Beyond this many weeks, projections aren't shown at all.
    static let maximumHorizonWeeks = 104.0
    /// Projecting further than this multiple of the observed span lowers confidence.
    static let horizonToSpanRatio = 4.0

    static func assessPace(
        plan: GoalPlan,
        trend: WeightTrend,
        toleranceFloor: Double = 0.25,
        toleranceFraction: Double = 0.1
    ) -> PaceAssessment {
        let required = plan.requiredPoundsPerWeek
        let actual = trend.actualPoundsPerWeek
        let tolerance = max(toleranceFloor, required * toleranceFraction)
        let difference = actual.map { $0 - required }

        let status: PaceStatus
        if plan.feasibility == .achieved {
            status = .goalReached
        } else if plan.feasibility == .deadlinePassed {
            status = .deadlinePassed
        } else if let difference {
            status = difference > tolerance ? .aheadOfPace : difference < -tolerance ? .behindPace : .onPace
        } else {
            status = .insufficientData
        }

        return PaceAssessment(
            requiredPoundsPerWeek: status == .goalReached || status == .deadlinePassed ? 0 : required,
            actualPoundsPerWeek: actual,
            paceDifference: status == .goalReached || status == .deadlinePassed ? nil : difference,
            tolerance: tolerance,
            status: status,
            isGaining: (actual ?? 0) < -0.1
        )
    }

    static func forecast(
        plan: GoalPlan,
        trend: WeightTrend,
        currentWeight: Double,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GoalForecast {
        if plan.feasibility == .achieved {
            return GoalForecast(state: .goalReached, paceUsed: nil, projectedWeightAtDeadline: nil, projectedGoalDate: nil, reachesTargetByDeadline: true, confidence: .high)
        }
        guard let window = trend.forecastWindow else {
            let reason = trend.isStale && trend.latestReading != nil
                ? "Not currently projected: no weigh-ins in the last week."
                : "Not currently projected: " + PaceAssessment.insufficientDataMessage.lowercased()
            return GoalForecast(state: .notProjected(reason: reason), paceUsed: nil, projectedWeightAtDeadline: nil, projectedGoalDate: nil, reachesTargetByDeadline: nil, confidence: .low)
        }

        let base = trend.smoothedCurrent ?? currentWeight
        let target = plan.targetWeight
        // Horizon confidence is judged against all the evidence observed, not just the window the pace came from.
        let observedSpan = max(trend.twentyEightDay?.spanDays ?? 0, trend.fourteenDay?.spanDays ?? 0)
        let spanWeeks = max(Double(observedSpan) / 7, 1)
        var confidence = trend.confidence

        // Weight on the deadline, as a range from the trend's uncertainty band.
        var atDeadline: ClosedRange<Double>?
        var reachesByDeadline: Bool?
        let weeksToDeadline = Double(plan.daysRemaining) / 7
        if plan.daysRemaining >= 0, weeksToDeadline <= maximumHorizonWeeks {
            let low = max(base - window.range.upperBound * weeksToDeadline, target)
            let high = max(base - window.range.lowerBound * weeksToDeadline, target)
            atDeadline = min(low, high)...max(low, high)
            reachesByDeadline = base - window.poundsPerWeek * weeksToDeadline <= target
            if weeksToDeadline > spanWeeks * horizonToSpanRatio { confidence = min(confidence, .medium) }
            if weeksToDeadline > spanWeeks * horizonToSpanRatio * 2 { confidence = .low }
        }

        let remaining = max(base - target, 0)
        guard window.poundsPerWeek >= minimumProjectablePace else {
            let reason = window.poundsPerWeek < -minimumProjectablePace
                ? "Not currently projected: your weight is trending up."
                : "Not currently projected: your weight is holding steady."
            return GoalForecast(state: .notProjected(reason: reason), paceUsed: window.poundsPerWeek, projectedWeightAtDeadline: atDeadline, projectedGoalDate: nil, reachesTargetByDeadline: reachesByDeadline, confidence: confidence)
        }
        let weeksToGoal = remaining / window.poundsPerWeek
        guard weeksToGoal <= maximumHorizonWeeks else {
            return GoalForecast(state: .notProjected(reason: "Not currently projected: more than two years at the current pace."), paceUsed: window.poundsPerWeek, projectedWeightAtDeadline: atDeadline, projectedGoalDate: nil, reachesTargetByDeadline: reachesByDeadline, confidence: .low)
        }
        if weeksToGoal > spanWeeks * horizonToSpanRatio { confidence = min(confidence, .medium) }
        if weeksToGoal > spanWeeks * horizonToSpanRatio * 2 { confidence = .low }
        let goalDate = calendar.date(byAdding: .day, value: Int((weeksToGoal * 7).rounded(.up)), to: calendar.startOfDay(for: now))

        return GoalForecast(
            state: .projected,
            paceUsed: window.poundsPerWeek,
            projectedWeightAtDeadline: atDeadline,
            projectedGoalDate: goalDate,
            reachesTargetByDeadline: reachesByDeadline,
            confidence: confidence
        )
    }
}
