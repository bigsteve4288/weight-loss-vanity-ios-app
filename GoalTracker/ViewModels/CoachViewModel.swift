import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CoachViewModel {
    var isLoading = false
    var errorMessage: String?
    private(set) var hasAPIKey = KeychainStore.read(KeychainStore.anthropicAPIKey) != nil

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hasAPIKey = KeychainStore.save(trimmed, for: KeychainStore.anthropicAPIKey)
    }

    func removeAPIKey() {
        KeychainStore.delete(KeychainStore.anthropicAPIKey)
        hasAPIKey = false
    }

    func requestVerdict(
        then: ProgressPhoto,
        now: ProgressPhoto,
        tone: CoachTone,
        profile: GoalProfile?,
        health: HealthKitManager,
        previous: CoachCritique?,
        context: ModelContext
    ) async {
        guard let apiKey = KeychainStore.read(KeychainStore.anthropicAPIKey) else {
            hasAPIKey = false
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let summary = Self.clientContext(profile: profile, health: health, previous: previous)
        do {
            let verdict = try await CoachService(apiKey: apiKey).critique(
                then: CoachPhoto(jpeg: then.imageData, date: then.date, weightLbs: then.weightLbs),
                now: CoachPhoto(jpeg: now.imageData, date: now.date, weightLbs: now.weightLbs),
                context: summary,
                tone: tone
            )
            context.insert(CoachCritique(tone: tone, verdict: verdict))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Plain-text briefing of the client's numbers so the critique can reference real data.
    static func clientContext(profile: GoalProfile?, health: HealthKitManager, previous: CoachCritique?, now: Date = .now) -> String {
        var lines = ["CLIENT DATA"]
        let lbs = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        let kcal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))

        if let profile {
            let snapshot = TargetEngine.snapshot(.init(
                startWeight: profile.startWeightLbs,
                lossGoal: profile.lossGoalLbs,
                targetDate: profile.targetDate,
                currentWeight: health.latestWeightLbs,
                history: health.weightHistory,
                caloriesConsumed: health.caloriesConsumed,
                activeBurn: health.activeEnergyBurned,
                basalBurn: health.basalEnergyBurned,
                restingCaloriesPerDay: profile.restingCaloriesPerDay,
                now: now
            ))
            lines.append("- Goal: lose \(profile.lossGoalLbs.formatted(lbs)) lb (start \(profile.startWeightLbs.formatted(lbs)) → target \(snapshot.targetWeight.formatted(lbs)) lb) by their birthday, \(profile.targetDate.formatted(date: .long, time: .omitted)) — \(snapshot.daysRemaining) days left.")
            if let current = snapshot.currentWeight {
                lines.append("- Current weight: \(current.formatted(lbs)) lb (\(snapshot.poundsLost.formatted(lbs)) lb lost, \(snapshot.poundsRemaining.formatted(lbs)) lb to go).")
            }
            let actual = snapshot.actualPoundsPerWeek.map { "\($0.formatted(lbs)) lb/week" } ?? "not enough weigh-ins yet"
            lines.append("- Required pace: \(snapshot.requiredPoundsPerWeek.formatted(lbs)) lb/week. Measured 14-day pace: \(actual).")
            lines.append("- Dashboard status: \(snapshot.status.title).")
            lines.append("- Today so far: \(health.caloriesConsumed.formatted(kcal)) kcal eaten (carbs \(health.carbsGrams.formatted(kcal)) g, protein \(health.proteinGrams.formatted(kcal)) g, fat \(health.fatGrams.formatted(kcal)) g); \(snapshot.todayBurn.formatted(kcal)) kcal burned (\(health.activeEnergyBurned.formatted(kcal)) active). Deficit \(snapshot.todayDeficit.formatted(kcal)) vs \(snapshot.requiredDailyDeficit.formatted(kcal)) kcal required per day.")
        }

        let todaysWorkouts = health.recentWorkouts.filter { Calendar.current.isDate($0.start, inSameDayAs: now) }
        if todaysWorkouts.isEmpty {
            lines.append("- Workouts today: none yet.")
        } else {
            let calories = todaysWorkouts.compactMap(\.calories).reduce(0, +)
            let names = todaysWorkouts.map { "\($0.activityName) via \($0.source)" }.joined(separator: ", ")
            lines.append("- Workouts today: \(names) — \(calories.formatted(kcal)) kcal reported by the apps, already included in today's burn.")
        }

        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let week = health.recentWorkouts.filter { $0.start >= weekAgo }
        if week.isEmpty {
            lines.append("- Workouts in the last 7 days: none recorded.")
        } else {
            lines.append("- Workouts in the last 7 days (\(week.count)):")
            for workout in week {
                lines.append("  • \(workout.start.formatted(.dateTime.weekday(.abbreviated).month().day())): \(workout.activityName), \(workout.detailLine) (\(workout.source))")
            }
        }

        if let previous {
            lines.append("- Your previous verdict (\(previous.date.formatted(date: .abbreviated, time: .omitted))): grade \(previous.grade) — \"\(previous.headline)\". Note whether they've responded to it.")
        }
        return lines.joined(separator: "\n")
    }
}
