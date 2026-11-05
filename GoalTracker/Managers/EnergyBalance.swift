import Foundation

/// One workout as the energy merge sees it. Built by `HealthKitManager` from an `HKWorkout`
/// plus a statistics query over the workout's window; pure data so the merge can be unit tested.
struct WorkoutEnergy: Identifiable, Equatable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let source: String
    /// Active calories the source app stored on the workout itself (Peloton, Nike Run Club…), if any.
    let reportedCalories: Double?
    /// Active energy samples HealthKit holds for the part of this workout that falls today.
    /// HealthKit's statistics query already de-duplicates overlapping sources by priority.
    let sampledCaloriesInWindow: Double

    var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }
}

/// Where a burn number came from, so the UI can label estimates honestly.
enum BurnSource: String, Equatable, Sendable {
    /// Measured by Apple Health for the whole day so far.
    case observed
    /// Apple Health has some data, but less than expected (e.g. the watch was charging), so it was topped up with the Goal Settings estimate.
    case observedPartial
    /// No Apple Health data; the Goal Settings resting calories were prorated for the time of day.
    case estimated
}

enum EnergyIssue: Equatable, Sendable {
    case noBasalData
    case partialBasalData
    case noActiveData
    /// Workouts whose app-reported calories weren't in Apple Health's active energy, so they were added.
    case workoutCaloriesAdded(count: Int)
    /// Workouts recorded twice (e.g. Apple Watch and Peloton for the same ride) that were counted once.
    case duplicateWorkoutsMerged(count: Int)

    var message: String {
        switch self {
        case .noBasalData:
            "No resting energy in Apple Health today, so resting burn is estimated from Goal Settings."
        case .partialBasalData:
            "Apple Health has less resting energy than expected (watch off or not synced?), so resting burn is partly estimated."
        case .noActiveData:
            "No active energy recorded yet today. If you've been moving, your watch or apps may not have synced."
        case let .workoutCaloriesAdded(count):
            count == 1
                ? "1 workout's calories came only from its app (not Apple Health samples) and were added to today's burn."
                : "\(count) workouts' calories came only from their apps (not Apple Health samples) and were added to today's burn."
        case let .duplicateWorkoutsMerged(count):
            count == 1
                ? "1 duplicate workout recording was counted once."
                : "\(count) duplicate workout recordings were counted once."
        }
    }

    /// Issues that make today's burn materially less reliable (versus informational notes).
    var reducesConfidence: Bool {
        switch self {
        case .noBasalData, .partialBasalData, .noActiveData: true
        case .workoutCaloriesAdded, .duplicateWorkoutsMerged: false
        }
    }
}

struct EnergySummary: Equatable, Sendable {
    /// Resting energy Apple Health reported today.
    var basalObserved: Double
    /// Resting energy used for today's burn (observed, or estimated where data is missing).
    var basal: Double
    var basalSource: BurnSource
    /// Active energy from Apple Health samples (already source-de-duplicated by HealthKit).
    var activeObserved: Double
    /// Workout calories reported only by the workout's app, added on top of `activeObserved`.
    var workoutSupplement: Double
    /// IDs of workouts treated as duplicates of another recording and not counted.
    var duplicateWorkoutIDs: Set<UUID>
    var issues: [EnergyIssue]

    var active: Double { activeObserved + workoutSupplement }
    var total: Double { basal + active }
    /// True when any part of the burn is an estimate rather than an Apple Health measurement.
    var includesEstimates: Bool { basalSource != .observed }
    var isReliable: Bool { !issues.contains(where: \.reducesConfidence) }

    static let empty = EnergySummary(
        basalObserved: 0, basal: 0, basalSource: .estimated, activeObserved: 0,
        workoutSupplement: 0, duplicateWorkoutIDs: [], issues: []
    )
}

/// Combines resting energy, active energy and workout calories for today without double-counting.
///
/// Apple Health's statistics queries merge overlapping samples from different sources by the user's
/// source priority, so `activeObserved` already counts an Apple Watch and Peloton ride once. What
/// that sum misses is calories an app stored only on the workout (no samples), and that's what is
/// added here: for each distinct workout, whatever its app reported beyond the samples already in
/// its time window.
enum EnergyBalance {
    /// Below this share of the expected resting burn, the observed value is treated as incomplete.
    static let minimumBasalCoverage = 0.6
    /// Two workouts overlapping by at least this share of the shorter one are the same session.
    static let duplicateOverlapThreshold = 0.5

    struct Input {
        var basalObserved: Double
        var activeObserved: Double
        /// Workouts that intersect today. `sampledCaloriesInWindow` must cover only today's portion.
        var workouts: [WorkoutEnergy]
        var restingCaloriesPerDay: Double
        var now: Date = .now
        var calendar: Calendar = .current
    }

    static func summarize(_ input: Input) -> EnergySummary {
        var issues: [EnergyIssue] = []
        let elapsed = fractionOfDayElapsed(input.now, calendar: input.calendar)
        let expectedBasal = input.restingCaloriesPerDay * elapsed

        let basal: Double
        let basalSource: BurnSource
        if input.basalObserved <= 0 {
            basal = expectedBasal
            basalSource = .estimated
            issues.append(.noBasalData)
        } else if elapsed > 0.1, input.basalObserved < expectedBasal * minimumBasalCoverage {
            basal = expectedBasal
            basalSource = .observedPartial
            issues.append(.partialBasalData)
        } else {
            basal = input.basalObserved
            basalSource = .observed
        }

        let today = dayInterval(containing: input.now, calendar: input.calendar)
        let todayWorkouts = input.workouts.filter { overlap(DateInterval(start: $0.start, end: max($0.end, $0.start)), today) > 0 }
        let (kept, duplicates) = removeDuplicates(todayWorkouts)
        if !duplicates.isEmpty { issues.append(.duplicateWorkoutsMerged(count: duplicates.count)) }

        var supplement = 0.0
        var supplemented = 0
        var counted: [DateInterval] = []
        for workout in kept.sorted(by: { $0.start < $1.start }) {
            let window = todayPortion(of: workout, now: input.now, calendar: input.calendar)
            defer { if let window { counted.append(window) } }
            guard let window, let reported = workout.reportedCalories, reported > 0, workout.duration > 0 else { continue }
            // Prorate for the part of the workout that's today, then drop any span another counted workout already covers.
            let todayShare = window.duration / workout.duration
            let alreadyCounted = counted.reduce(0) { $0 + overlap(window, $1) }
            let uncoveredShare = window.duration > 0 ? max(1 - alreadyCounted / window.duration, 0) : 0
            let reportedToday = reported * todayShare * uncoveredShare
            let missing = reportedToday - workout.sampledCaloriesInWindow
            if missing > 1 {
                supplement += missing
                supplemented += 1
            }
        }
        if supplemented > 0 { issues.append(.workoutCaloriesAdded(count: supplemented)) }

        if input.activeObserved <= 0, supplement <= 0, elapsed > 0.5 {
            issues.append(.noActiveData)
        }

        return EnergySummary(
            basalObserved: input.basalObserved,
            basal: basal,
            basalSource: basalSource,
            activeObserved: input.activeObserved,
            workoutSupplement: supplement,
            duplicateWorkoutIDs: Set(duplicates.map(\.id)),
            issues: issues
        )
    }

    /// Groups workouts that are the same session recorded twice and keeps the one with the most calories.
    static func removeDuplicates(_ workouts: [WorkoutEnergy]) -> (kept: [WorkoutEnergy], duplicates: [WorkoutEnergy]) {
        var groups: [[WorkoutEnergy]] = []
        for workout in workouts.sorted(by: { $0.start < $1.start }) {
            if let index = groups.firstIndex(where: { group in group.contains { isSameSession($0, workout) } }) {
                groups[index].append(workout)
            } else {
                groups.append([workout])
            }
        }
        var kept: [WorkoutEnergy] = []
        var duplicates: [WorkoutEnergy] = []
        for group in groups {
            let best = group.max { calories($0) < calories($1) } ?? group[0]
            kept.append(best)
            duplicates.append(contentsOf: group.filter { $0.id != best.id })
        }
        return (kept, duplicates)
    }

    static func isSameSession(_ a: WorkoutEnergy, _ b: WorkoutEnergy) -> Bool {
        let shorter = min(a.duration, b.duration)
        guard shorter > 0 else { return false }
        let shared = overlap(DateInterval(start: a.start, end: a.end), DateInterval(start: b.start, end: b.end))
        return shared / shorter >= duplicateOverlapThreshold
    }

    /// The part of a workout between today's midnight and now, or `nil` if none of it is.
    static func todayPortion(of workout: WorkoutEnergy, now: Date, calendar: Calendar = .current) -> DateInterval? {
        todayPortion(start: workout.start, end: workout.end, now: now, calendar: calendar)
    }

    static func todayPortion(start: Date, end: Date, now: Date, calendar: Calendar = .current) -> DateInterval? {
        let dayStart = calendar.startOfDay(for: now)
        let clippedStart = max(start, dayStart)
        let clippedEnd = min(end, now)
        guard clippedEnd > clippedStart else { return nil }
        return DateInterval(start: clippedStart, end: clippedEnd)
    }

    static func dayInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
    }

    /// Share of today that has passed, using the real length of the day (23 or 25 hours across DST changes).
    static func fractionOfDayElapsed(_ now: Date, calendar: Calendar = .current) -> Double {
        let day = dayInterval(containing: now, calendar: calendar)
        guard day.duration > 0 else { return 0 }
        return min(max(now.timeIntervalSince(day.start) / day.duration, 0), 1)
    }

    static func overlap(_ a: DateInterval, _ b: DateInterval) -> TimeInterval {
        max(min(a.end, b.end).timeIntervalSince(max(a.start, b.start)), 0)
    }

    private static func calories(_ workout: WorkoutEnergy) -> Double {
        max(workout.reportedCalories ?? 0, workout.sampledCaloriesInWindow)
    }
}
