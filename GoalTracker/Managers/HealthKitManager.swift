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
    private(set) var caloriesConsumed: Double = 0
    private(set) var carbsGrams: Double = 0
    private(set) var proteinGrams: Double = 0
    private(set) var fatGrams: Double = 0
    private(set) var activeEnergyBurned: Double = 0
    private(set) var basalEnergyBurned: Double = 0
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

    private static var readTypes: Set<HKObjectType> {
        [bodyMass, energyConsumed, carbohydrates, protein, fat, activeEnergy, basalEnergy]
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
        weightHistory = await fetchWeightHistory(days: 90)
        if let latest = await fetchLatestWeight() {
            latestWeightLbs = latest.pounds
            latestWeightDate = latest.date
        }
        caloriesConsumed = await todaySum(Self.energyConsumed, unit: .kilocalorie())
        carbsGrams = await todaySum(Self.carbohydrates, unit: .gram())
        proteinGrams = await todaySum(Self.protein, unit: .gram())
        fatGrams = await todaySum(Self.fat, unit: .gram())
        activeEnergyBurned = await todaySum(Self.activeEnergy, unit: .kilocalorie())
        basalEnergyBurned = await todaySum(Self.basalEnergy, unit: .kilocalorie())
        lastUpdated = .now
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
        for type in [Self.bodyMass, Self.energyConsumed, Self.carbohydrates, Self.protein, Self.fat, Self.activeEnergy] {
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

    private func todaySum(_ type: HKQuantityType, unit: HKUnit) async -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: .now)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        let statistics = try? await descriptor.result(for: store)
        return statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
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
