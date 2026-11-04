import Foundation

struct WeightPoint: Identifiable, Hashable, Sendable {
    let id = UUID()
    let date: Date
    let pounds: Double
}

enum TrackStatus: Equatable, Sendable {
    case needsData
    case goalReached
    case deadlinePassed
    case onTrack
    case pushHarder
    case deficitNeeded

    var title: String {
        switch self {
        case .needsData: "AWAITING DATA"
        case .goalReached: "GOAL REACHED"
        case .deadlinePassed: "TARGET DATE PASSED"
        case .onTrack: "ON TRACK"
        case .pushHarder: "PUSH HARDER TODAY"
        case .deficitNeeded: "DEFICIT NEEDED"
        }
    }

    var message: String {
        switch self {
        case .needsData: "Connect Apple Health or log a weigh-in to start the engine."
        case .goalReached: "Target weight hit. Set the next standard."
        case .deadlinePassed: "The target date has passed. Reset the date and keep going."
        case .onTrack: "Your pace meets the goal. Keep stacking days."
        case .pushHarder: "You're in a deficit, but not enough for the pace you need. Add a workout or tighten intake."
        case .deficitNeeded: "You're at or above maintenance today. Close the gap."
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
    let requiredPoundsPerWeek: Double
    let requiredDailyDeficit: Double
    let todayBurn: Double
    let todayDeficit: Double
    /// Measured trend over the trailing window; nil when there isn't enough data.
    let actualPoundsPerWeek: Double?
    let status: TrackStatus
    /// True when the required pace exceeds the commonly cited 2 lb/week safe maximum.
    let exceedsSafePace: Bool
}

/// Pure calculation layer: turns goal settings + HealthKit numbers into a status snapshot.
enum TargetEngine {
    static let caloriesPerPound = 3500.0
    static let maxSafePoundsPerWeek = 2.0

    struct Input {
        var startWeight: Double
        var lossGoal: Double
        var targetDate: Date
        var currentWeight: Double?
        var history: [WeightPoint]
        var caloriesConsumed: Double
        var activeBurn: Double
        var basalBurn: Double
        var restingCaloriesPerDay: Double
        var now: Date = .now
        var calendar: Calendar = .current
    }

    static func snapshot(_ input: Input) -> TargetSnapshot {
        let calendar = input.calendar
        let target = input.startWeight - input.lossGoal
        let weight = input.currentWeight ?? input.startWeight
        let remaining = max(weight - target, 0)
        let lost = input.startWeight - weight
        let progress = input.lossGoal > 0 ? min(max(lost / input.lossGoal, 0), 1) : 0

        let days = daysRemaining(from: input.now, to: input.targetDate, calendar: calendar)
        let effectiveDays = Double(max(days, 1))
        let requiredPerWeek = remaining / (effectiveDays / 7)
        let requiredDaily = remaining * caloriesPerPound / effectiveDays

        // Basal burn from HealthKit is cumulative "so far today"; prorate the fallback to match.
        let basal = input.basalBurn > 0
            ? input.basalBurn
            : input.restingCaloriesPerDay * fractionOfDayElapsed(input.now, calendar: calendar)
        let burn = basal + input.activeBurn
        let todayDeficit = burn - input.caloriesConsumed
        let actual = weeklyLossRate(input.history, now: input.now)

        let status: TrackStatus
        if input.currentWeight == nil {
            status = .needsData
        } else if remaining <= 0 {
            status = .goalReached
        } else if days <= 0 {
            status = .deadlinePassed
        } else if let actual, actual >= requiredPerWeek {
            status = .onTrack
        } else if todayDeficit >= requiredDaily {
            status = .onTrack
        } else if todayDeficit > 0 {
            status = .pushHarder
        } else {
            status = .deficitNeeded
        }

        return TargetSnapshot(
            targetWeight: target,
            currentWeight: input.currentWeight,
            poundsLost: lost,
            poundsRemaining: remaining,
            progress: progress,
            daysRemaining: days,
            requiredPoundsPerWeek: requiredPerWeek,
            requiredDailyDeficit: requiredDaily,
            todayBurn: burn,
            todayDeficit: todayDeficit,
            actualPoundsPerWeek: actual,
            status: status,
            exceedsSafePace: requiredPerWeek > maxSafePoundsPerWeek
        )
    }

    static func daysRemaining(from now: Date, to target: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day ?? 0
    }

    static func fractionOfDayElapsed(_ now: Date, calendar: Calendar = .current) -> Double {
        min(now.timeIntervalSince(calendar.startOfDay(for: now)) / 86_400, 1)
    }

    /// Least-squares slope of weight over the trailing window, as pounds lost per week (positive = losing).
    static func weeklyLossRate(_ history: [WeightPoint], now: Date, windowDays: Int = 14) -> Double? {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let points = history.filter { $0.date >= cutoff && $0.date <= now }
        guard points.count >= 2,
              let first = points.map(\.date).min(),
              let last = points.map(\.date).max(),
              last.timeIntervalSince(first) >= 3 * 86_400
        else { return nil }

        let xs = points.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = points.map(\.pounds)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator > 0 else { return nil }
        return -(numerator / denominator) * 7
    }
}
