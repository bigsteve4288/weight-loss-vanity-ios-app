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
        guard let saved = KeychainStore.read(KeychainStore.anthropicAPIKey) else {
            hasAPIKey = false
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let summary = Self.clientContext(profile: profile, health: health, previous: previous)
        do {
            let verdict = try await CoachService(credential: .init(saved)).critique(
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
            let snapshot = TargetEngine.snapshot(profile: profile, health: health, now: now)
            let plan = snapshot.plan
            lines.append("- Goal: lose \(profile.lossGoalLbs.formatted(lbs)) lb (start \(profile.startWeightLbs.formatted(lbs)) → target \(snapshot.targetWeight.formatted(lbs)) lb) by their birthday, \(profile.targetDate.formatted(date: .long, time: .omitted)) — \(snapshot.daysRemaining) days left.")
            if let current = snapshot.currentWeight {
                var line = "- Current weight: \(current.formatted(lbs)) lb (\(snapshot.poundsLost.formatted(lbs)) lb lost, \(snapshot.poundsRemaining.formatted(lbs)) lb to go)."
                if let date = health.latestWeightDate {
                    line += " Last weigh-in \(date.formatted(date: .abbreviated, time: .omitted))\(plan.weightIsStale ? ", over a week ago" : "")."
                }
                lines.append(line)
            } else {
                lines.append("- Current weight: no weigh-ins in Apple Health yet.")
            }
            lines.append(contentsOf: planLines(plan))
            let actual = snapshot.actualPoundsPerWeek.map { "\($0.formatted(lbs)) lb/week" } ?? "not enough weigh-ins yet (needs 3+ over 5+ days)"
            lines.append("- Measured 14-day trend: \(actual).\(snapshot.paceAboveSustainable ? " That's faster than sustainable; make sure they're eating enough rather than praising the speed." : "")")
            lines.append("- Dashboard status: \(snapshot.status.title).")
            lines.append(contentsOf: todayLines(snapshot, nutrition: health.nutrition, now: now))
        }

        // A session recorded by two apps (e.g. Apple Watch and Peloton) is listed and counted once.
        let duplicateIDs = Set(EnergyBalance.removeDuplicates(health.workoutEnergyToday).duplicates.map(\.id))
        let todaysWorkouts = health.recentWorkouts.filter {
            Calendar.current.isDate($0.start, inSameDayAs: now) && !duplicateIDs.contains($0.id)
        }
        if todaysWorkouts.isEmpty {
            lines.append("- Workouts today: none yet.")
        } else {
            let calories = todaysWorkouts.compactMap(\.calories).reduce(0, +)
            let names = todaysWorkouts.map { "\($0.activityName) via \($0.source)" }.joined(separator: ", ")
            lines.append("- Workouts today: \(names) — \(calories.formatted(kcal)) kcal reported by the apps, counted once in today's burn.")
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

    /// The goal, the deadline's demand and the sustainable plan, kept separate so the coach plans around the last one.
    nonisolated static func planLines(_ plan: GoalPlan) -> [String] {
        let lbs = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        let kcal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        guard plan.feasibility != .achieved else { return ["- Goal feasibility: target weight reached."] }
        var lines: [String] = []
        if plan.daysRemaining > 0 {
            lines.append("- Deadline math (context only, not an instruction): reaching the target by the date would take \(plan.requiredPoundsPerWeek.formatted(lbs)) lb/week.")
        }
        lines.append("- Goal feasibility: \(plan.feasibility.label).")
        lines.append("- Sustainable plan to coach toward: \(plan.recommendedPoundsPerWeek.formatted(lbs)) lb/week (their sustainable range is \(plan.sustainablePace.lowerBound.formatted(lbs))–\(plan.sustainablePace.upperBound.formatted(lbs)) lb/week), roughly a \(plan.recommendedDailyDeficitEstimate.formatted(kcal)) kcal/day deficit by the 3,500 kcal/lb rule of thumb (a rough estimate).")
        if plan.needsAdjustment {
            if let atDeadline = plan.projectedWeightAtDeadline {
                lines.append("- At a sustainable pace they'd be about \(atDeadline.lowerBound.formatted(kcal))–\(atDeadline.upperBound.formatted(kcal)) lb on the date.")
            }
            if let dates = plan.projectedTargetDate {
                lines.append("- At a sustainable pace they'd reach the target between \(dates.lowerBound.formatted(date: .abbreviated, time: .omitted)) and \(dates.upperBound.formatted(date: .abbreviated, time: .omitted)).")
            }
            lines.append("- The date doesn't fit a sustainable pace. Coach them to keep the steady plan and suggest moving the date. Don't push a bigger deficit to hit it.")
        }
        return lines
    }

    /// Today's food log and burn, labeled with how complete they are so a partial day isn't read as the whole day.
    nonisolated static func todayLines(_ snapshot: TargetSnapshot, nutrition: NutritionLog, now: Date) -> [String] {
        let kcal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        let intake = snapshot.intake
        let energy = snapshot.energy
        var lines: [String] = []
        let time = now.formatted(date: .omitted, time: .shortened)
        switch intake.state {
        case .notTracking:
            lines.append("- Food log: they haven't logged food in Apple Health this week. Don't comment on intake or a deficit.")
        default:
            lines.append("- Food log as of \(time): \(intake.state.label). \(nutrition.calories.formatted(kcal)) kcal logged so far (carbs \(nutrition.carbsGrams.formatted(kcal)) g, protein \(nutrition.proteinGrams.formatted(kcal)) g, fat \(nutrition.fatGrams.formatted(kcal)) g) across \(intake.mealsLogged) eating occasion(s); \(intake.mealsDue) meal(s) likely due by now.")
            if !intake.canJudgeDeficit {
                lines.append("- This is a partial day. Don't treat it as their full intake or as restriction; talk about what's left to eat and log.")
            }
            if intake.lowIntakeConcern {
                lines.append("- The full day's logged intake is low. Check in kindly: either meals are missing from the log, or they should make sure they're eating enough. Don't praise it.")
            }
            if intake.proteinDataMissing {
                lines.append("- Protein data didn't reach Apple Health today, so don't judge their protein.")
            }
        }
        let basalNote = switch energy.basalSource {
        case .observed: "measured"
        case .observedPartial: "partly estimated"
        case .estimated: "estimated"
        }
        lines.append("- Burn so far today: \(energy.total.formatted(kcal)) kcal (resting \(energy.basal.formatted(kcal)), \(basalNote); active \(energy.active.formatted(kcal))).")
        if !energy.issues.isEmpty {
            lines.append("- Data notes: " + energy.issues.map(\.message).joined(separator: " "))
        }
        if intake.canJudgeDeficit {
            lines.append("- Today's estimated deficit: \(snapshot.todayDeficit.formatted(kcal)) kcal vs a plan of about \(snapshot.plan.recommendedDailyDeficitEstimate.formatted(kcal)).")
        }
        return lines
    }
}
