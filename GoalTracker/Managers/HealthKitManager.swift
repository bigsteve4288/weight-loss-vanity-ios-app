import Foundation
import HealthKit
import Observation

/// Central HealthKit hub. Weight arrives from the Feelfit scale and nutrition from Carb Manager,
/// both of which write into Apple Health; this manager reads it back and keeps it fresh.
@MainActor
@Observable
final class HealthKitManager {
    private(set) var latestWeightLbs: Double?
    private(set) var latestWeightDate: Date?
    private(set) var weightHistory: [WeightPoint] = []
    /// Today's food log, including entry times so the engine can tell a partial day from a finished one.
    private(set) var nutrition: NutritionLog = .empty
    /// Active energy from Apple Health samples today, as HealthKit de-duplicates them across sources.
    /// Workout calories that exist only on the workout are merged in later by `EnergyBalance`.
    private(set) var activeEnergyBurned: Double = 0
    private(set) var basalEnergyBurned: Double = 0
    private(set) var recentWorkouts: [WorkoutSummary] = []
    /// Today's workouts with the active energy Apple Health holds for each one's window.
    private(set) var workoutEnergyToday: [WorkoutEnergy] = []

    var caloriesConsumed: Double { nutrition.calories }
    var carbsGrams: Double { nutrition.carbsGrams }
    var proteinGrams: Double { nutrition.proteinGrams }
    var fatGrams: Double { nutrition.fatGrams }
    private(set) var lastUpdated: Date?
    private(set) var hasRequestedAuthorization = false
    var errorMessage: String?

    let isAvailable = HKHealthStore.isHealthDataAvailable()

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var observerQueries: [HKObserverQuery] = []
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

    private static let bodyMass = HKQuantityType(.bodyMass)
    private static let energyConsumed = HKQuantityType(.dietaryEnergyConsumed)
    private static let carbohydrates = HKQuantityType(.dietaryCarbohydrates)
    private static let protein = HKQuantityType(.dietaryProtein)
    private static let fat = HKQuantityType(.dietaryFatTotal)
    private static let activeEnergy = HKQuantityType(.activeEnergyBurned)
    private static let basalEnergy = HKQuantityType(.basalEnergyBurned)
    private static let runningDistance = HKQuantityType(.distanceWalkingRunning)
    private static let cyclingDistance = HKQuantityType(.distanceCycling)
    private static let workouts = HKObjectType.workoutType()

    private static var readTypes: Set<HKObjectType> {
        [bodyMass, energyConsumed, carbohydrates, protein, fat, activeEnergy, basalEnergy, runningDistance, cyclingDistance, workouts]
    }

    /// Write access is only used for manual weigh-ins.
    private static var shareTypes: Set<HKSampleType> { [bodyMass] }

    func start() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
            hasRequestedAuthorization = true
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        startObserving()
        await refresh()
    }

    func refresh() async {
        guard isAvailable, hasRequestedAuthorization else { return }
        // One clock and calendar for the whole refresh so every number describes the same "today".
        let now = Date.now
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)

        // 90 days on screen, plus a week before so the 7-day average has data at the left edge.
        weightHistory = await fetchWeightHistory(days: 97)
        if let latest = await fetchLatestWeight() {
            latestWeightLbs = latest.pounds
            latestWeightDate = latest.date
        }

        let calories = await sum(Self.energyConsumed, unit: .kilocalorie(), from: dayStart, to: now)
        let protein = await sum(Self.protein, unit: .gram(), from: dayStart, to: now)
        let carbs = await sum(Self.carbohydrates, unit: .gram(), from: dayStart, to: now)
        let fat = await sum(Self.fat, unit: .gram(), from: dayStart, to: now)
        let weekBefore = calendar.date(byAdding: .day, value: -7, to: dayStart) ?? dayStart
        nutrition = NutritionLog(
            calories: calories ?? 0,
            proteinGrams: protein ?? 0,
            carbsGrams: carbs ?? 0,
            fatGrams: fat ?? 0,
            entryTimes: await sampleStartDates(Self.energyConsumed, from: dayStart, to: now),
            hasProteinData: protein != nil,
            loggedInPastWeek: await hasSamples(Self.energyConsumed, from: weekBefore, to: dayStart)
        )

        activeEnergyBurned = await sum(Self.activeEnergy, unit: .kilocalorie(), from: dayStart, to: now) ?? 0
        basalEnergyBurned = await sum(Self.basalEnergy, unit: .kilocalorie(), from: dayStart, to: now) ?? 0
        recentWorkouts = await fetchRecentWorkouts(days: 14)
        workoutEnergyToday = await workoutEnergy(for: recentWorkouts, now: now, calendar: calendar)
        lastUpdated = now
    }

    func saveWeight(pounds: Double, date: Date) async throws {
        let quantity = HKQuantity(unit: .pound(), doubleValue: pounds)
        let sample = HKQuantitySample(type: Self.bodyMass, quantity: quantity, start: date, end: date)
        try await store.save(sample)
        await refresh()
    }

    // MARK: - Live updates

    private func startObserving() {
        guard observerQueries.isEmpty else { return }
        let observed: [HKSampleType] = [Self.bodyMass, Self.energyConsumed, Self.carbohydrates, Self.protein, Self.fat, Self.activeEnergy, Self.basalEnergy, Self.workouts]
        for type in observed {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, _ in
                completionHandler()
                Task { @MainActor in self?.scheduleRefresh() }
            }
            store.execute(query)
            observerQueries.append(query)
        }
    }

    /// Observer callbacks tend to arrive in bursts (a meal logs several nutrients at once), so coalesce them.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    // MARK: - Queries

    /// Cumulative sum over a window, or `nil` when Apple Health has no samples there. HealthKit's statistics
    /// query merges overlapping samples from different sources by the user's source priority, so an Apple
    /// Watch and a Peloton recording the same minutes are counted once.
    private func sum(_ type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        let statistics = try? await descriptor.result(for: store)
        return statistics?.sumQuantity()?.doubleValue(for: unit)
    }

    private func sampleStartDates(_ type: HKQuantityType, from start: Date, to end: Date) async -> [Date] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return ((try? await descriptor.result(for: store)) ?? []).map(\.startDate)
    }

    private func hasSamples(_ type: HKQuantityType, from start: Date, to end: Date) async -> Bool {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [],
            limit: 1
        )
        return !((try? await descriptor.result(for: store)) ?? []).isEmpty
    }

    /// For each workout that overlaps today, the active energy Apple Health already holds for today's part
    /// of it, so `EnergyBalance` only adds app-reported calories that aren't in the daily sum yet.
    private func workoutEnergy(for workouts: [WorkoutSummary], now: Date, calendar: Calendar) async -> [WorkoutEnergy] {
        var result: [WorkoutEnergy] = []
        for workout in workouts {
            guard let window = EnergyBalance.todayPortion(start: workout.start, end: workout.end, now: now, calendar: calendar) else { continue }
            let sampled = await sum(Self.activeEnergy, unit: .kilocalorie(), from: window.start, to: window.end) ?? 0
            result.append(WorkoutEnergy(
                id: workout.id,
                start: workout.start,
                end: workout.end,
                source: workout.source,
                reportedCalories: workout.calories,
                sampledCaloriesInWindow: sampled
            ))
        }
        return result
    }

    // MARK: - On-demand history (for the AI Coach; not part of the regular refresh)

    /// Daily food, protein and active-energy totals for the last `days` days, oldest first.
    /// A day with no samples for a type has `nil` for it (not logged), not zero.
    func dailyTotals(days: Int, now: Date = .now, calendar: Calendar = .current) async -> [DailyHealthTotals] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        async let calories = dailySums(Self.energyConsumed, unit: .kilocalorie(), from: start, to: now, calendar: calendar)
        async let protein = dailySums(Self.protein, unit: .gram(), from: start, to: now, calendar: calendar)
        async let active = dailySums(Self.activeEnergy, unit: .kilocalorie(), from: start, to: now, calendar: calendar)
        let (food, grams, burn) = await (calories, protein, active)
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DailyHealthTotals(day: day, caloriesConsumed: food[day], proteinGrams: grams[day], activeEnergy: burn[day])
        }
    }

    /// Workouts from the last `days` days, newest first, fetched on demand.
    func workouts(days: Int) async -> [WorkoutSummary] {
        await fetchRecentWorkouts(days: days)
    }

    private func dailySums(_ type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date, calendar: Calendar) async -> [Date: Double] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [:] }
        var result: [Date: Double] = [:]
        for statistics in collection.statistics() {
            if let value = statistics.sumQuantity()?.doubleValue(for: unit) {
                result[calendar.startOfDay(for: statistics.startDate)] = value
            }
        }
        return result
    }

    private func fetchWeightHistory(days: Int) async -> [WeightPoint] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.bodyMass, predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.endDate)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map { WeightPoint(date: $0.endDate, pounds: $0.quantity.doubleValue(for: .pound())) }
    }

    /// Workouts from any source app (Nike Run Club, Peloton, Apple Watch), newest first.
    private func fetchRecentWorkouts(days: Int) async -> [WorkoutSummary] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let workouts = (try? await descriptor.result(for: store)) ?? []
        return workouts.map(WorkoutSummary.init)
    }

    private func fetchLatestWeight() async -> WeightPoint? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.bodyMass)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return WeightPoint(date: sample.endDate, pounds: sample.quantity.doubleValue(for: .pound()))
    }
}
