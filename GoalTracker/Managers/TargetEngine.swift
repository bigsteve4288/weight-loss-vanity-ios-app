import Foundation

struct WeightPoint: Identifiable, Hashable, Sendable {
    let id = UUID()
    let date: Date
    let pounds: Double
}

/// The daily accountability verdict: behaviour, logging and the measured trend against a *sustainable*
/// plan. Whether the trend is fast enough for the user's own deadline is a separate assessment
/// (`PaceAssessment`). Never grades a partial day against a deadline-driven deficit.
enum TrackStatus: Equatable, Sendable {
    case needsData
    case goalReached
    case deadlinePassed
    case onTrack
    case buildingMomentum
    case needsAttention
    case loggingIncomplete
    case goalNeedsAdjustment

    var title: String {
        switch self {
        case .needsData: "AWAITING DATA"
        case .goalReached: "GOAL REACHED"
        case .deadlinePassed: "TARGET DATE PASSED"
        case .onTrack: "ON TRACK TODAY"
        case .buildingMomentum: "BUILDING MOMENTUM"
        case .needsAttention: "NEEDS ATTENTION"
        case .loggingIncomplete: "LOGGING INCOMPLETE"
        case .goalNeedsAdjustment: "GOAL NEEDS ADJUSTMENT"
        }
    }

    var message: String {
        switch self {
        case .needsData: "Connect Apple Health or log a weigh-in to start the engine."
        case .goalReached: "Target weight hit. Set the next standard."
        case .deadlinePassed: "The target date has passed. Set a new date and keep the progress going."
        case .onTrack: "Your trend matches a sustainable plan. Keep stacking normal days."
        case .buildingMomentum: "Moving in the right direction. Keep the routine steady and keep weighing in."
        case .needsAttention: "Your trend has flattened or ticked up. Review this week's logging and routine and make one adjustment. No crash fixes."
        case .loggingIncomplete: "Some of today's meals aren't logged yet. Log them when you can so today's numbers mean something."
        case .goalNeedsAdjustment: "Your date needs a faster pace than is sustainable. Follow the steady plan and consider moving the date."
        }
    }
}

struct TargetSnapshot: Sendable {
    let targetWeight: Double
    let currentWeight: Double?
    let poundsLost: Double
    let poundsRemaining: Double
    /// 0...1 progress toward the loss goal.
    let progress: Double
    let daysRemaining: Int
    /// What the deadline alone would demand. Context only.
    let requiredPoundsPerWeek: Double
    /// Rough 3,500 kcal/lb estimate of the deadline's daily deficit. Context only, never an instruction.
    let requiredDailyDeficit: Double
    /// Food logged so far today.
    let caloriesConsumed: Double
    /// Burn so far today (resting + active), including estimates where data is missing.
    let todayBurn: Double
    /// Burn so far minus food logged so far. Only meaningful when `intake.canJudgeDeficit`.
    let todayDeficit: Double
    /// Measured trend over the trailing window; nil when there isn't enough data.
    let actualPoundsPerWeek: Double?
    /// Daily accountability.
    let status: TrackStatus
    /// Goal trajectory against the user's own deadline.
    let pace: PaceAssessment
    let forecast: GoalForecast
    let trend: WeightTrend
    /// True when the deadline needs more than the sustainable maximum.
    let exceedsSafePace: Bool
    /// True when the measured trend is faster than the sustainable maximum.
    let paceAboveSustainable: Bool
    let plan: GoalPlan
    let energy: EnergySummary
    let intake: IntakeAssessment
}

/// Pure calculation layer: turns goal settings + HealthKit numbers into a status snapshot.
enum TargetEngine {
    static let caloriesPerPound = WeightGoalEngine.caloriesPerPound

    struct Input {
        var startWeight: Double
        var lossGoal: Double
        var targetDate: Date
        var currentWeight: Double?
        var latestWeightDate: Date?
        var history: [WeightPoint]
        var nutrition: NutritionLog
        /// Active energy from Apple Health samples (source-de-duplicated by HealthKit).
        var activeBurn: Double
        /// Resting energy from Apple Health so far today.
        var basalBurn: Double
        var workouts: [WorkoutEnergy] = []
        var restingCaloriesPerDay: Double
        var rhythm: DailyRhythm
        var intensity: GoalIntensity = .standard
        var clinicianMaxPoundsPerWeek: Double?
        var policy: PacePolicy = .standard
        var now: Date = .now
        var calendar: Calendar = .current
    }

    static func snapshot(_ input: Input) -> TargetSnapshot {
        let target = input.startWeight - input.lossGoal
        let weight = input.currentWeight ?? input.startWeight
        let lost = input.startWeight - weight
        let progress = input.lossGoal > 0 ? min(max(lost / input.lossGoal, 0), 1) : 0

        let plan = WeightGoalEngine.plan(.init(
            targetWeight: target,
            targetDate: input.targetDate,
            currentWeight: weight,
            latestWeightDate: input.latestWeightDate,
            intensity: input.intensity,
            clinicianMaxPoundsPerWeek: input.clinicianMaxPoundsPerWeek,
            policy: input.policy,
            now: input.now,
            calendar: input.calendar
        ))
        let energy = EnergyBalance.summarize(.init(
            basalObserved: input.basalBurn,
            activeObserved: input.activeBurn,
            workouts: input.workouts,
            restingCaloriesPerDay: input.restingCaloriesPerDay,
            now: input.now,
            calendar: input.calendar
        ))
        let intake = IntakeAssessor.assess(input.nutrition, rhythm: input.rhythm, now: input.now, calendar: input.calendar)
        let trend = WeightTrendService.trend(input.history, now: input.now, calendar: input.calendar)
        let actual = trend.actualPoundsPerWeek
        let pace = GoalForecastService.assessPace(plan: plan, trend: trend)
        let forecast = GoalForecastService.forecast(plan: plan, trend: trend, currentWeight: weight, now: input.now, calendar: input.calendar)
        let sustainableMax = plan.sustainablePace.upperBound

        let status: TrackStatus
        if input.currentWeight == nil {
            status = .needsData
        } else if plan.feasibility == .achieved {
            status = .goalReached
        } else if plan.feasibility == .deadlinePassed {
            status = .deadlinePassed
        } else if let actual, actual >= plan.recommendedPoundsPerWeek * 0.8 {
            status = .onTrack
        } else if plan.feasibility == .exceedsSustainable, input.intensity == .standard {
            // Aggressive and Clinician-Guided users chose to keep the date; they see the gap on YOUR PACE instead.
            status = .goalNeedsAdjustment
        } else if intake.state == .missingLogs {
            status = .loggingIncomplete
        } else if let actual, actual <= 0.1 {
            status = .needsAttention
        } else {
            // Losing, but slower than plan, or not enough weigh-ins yet to measure a trend.
            status = .buildingMomentum
        }

        return TargetSnapshot(
            targetWeight: target,
            currentWeight: input.currentWeight,
            poundsLost: lost,
            poundsRemaining: plan.poundsRemaining,
            progress: progress,
            daysRemaining: plan.daysRemaining,
            requiredPoundsPerWeek: plan.requiredPoundsPerWeek,
            requiredDailyDeficit: plan.requiredDailyDeficitEstimate,
            caloriesConsumed: input.nutrition.calories,
            todayBurn: energy.total,
            todayDeficit: energy.total - input.nutrition.calories,
            actualPoundsPerWeek: actual,
            status: status,
            pace: pace,
            forecast: forecast,
            trend: trend,
            exceedsSafePace: plan.feasibility == .exceedsSustainable,
            paceAboveSustainable: (actual ?? 0) > sustainableMax + 0.25,
            plan: plan,
            energy: energy,
            intake: intake
        )
    }

    static func daysRemaining(from now: Date, to target: Date, calendar: Calendar = .current) -> Int {
        WeightGoalEngine.daysRemaining(from: now, to: target, calendar: calendar)
    }

    static func fractionOfDayElapsed(_ now: Date, calendar: Calendar = .current) -> Double {
        EnergyBalance.fractionOfDayElapsed(now, calendar: calendar)
    }
}
