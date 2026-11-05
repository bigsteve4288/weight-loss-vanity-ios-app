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
    /// - Parameter includeHealthHistory: pass `false` for anything that could end up on the Lock Screen
    ///   (check-in notes). Even when `true`, history is only included if the user opted in.
    static func clientContext(
        profile: GoalProfile?,
        health: HealthKitManager,
        previous: CoachCritique?,
        includeHealthHistory: Bool = true,
        now: Date = .now
    ) -> String {
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
            lines.append(contentsOf: paceLines(snapshot, acknowledgedRequiredPace: profile.intensity == .aggressive ? profile.aggressiveAcknowledgedRequiredPace : nil))
            lines.append(contentsOf: planLines(plan))
            if includeHealthHistory, profile.shareHealthHistoryWithCoach {
                lines.append(contentsOf: healthHistoryLines(profile.healthHistory))
            }
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

    /// The user's own goal against their measured trend. The goal is reported as-is in every mode.
    nonisolated static func paceLines(_ snapshot: TargetSnapshot, acknowledgedRequiredPace: Double? = nil) -> [String] {
        let lbs = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        let whole = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        let plan = snapshot.plan
        let pace = snapshot.pace
        let forecast = snapshot.forecast
        var lines = ["- Goal mode: \(plan.intensity.label). \(plan.intensity.explanation)"]

        switch pace.status {
        case .goalReached:
            lines.append("- Goal trajectory: GOAL REACHED.")
            return lines
        case .deadlinePassed:
            lines.append("- Goal trajectory: DEADLINE PASSED. Don't calculate a catch-up pace; they can set a new date if they want.")
        case .insufficientData:
            lines.append("- Required pace for their deadline: \(pace.requiredPoundsPerWeek.formatted(lbs)) lb/week. Actual pace: not enough weigh-ins for a reliable trend, so don't guess one.")
        default:
            let actual = pace.actualPoundsPerWeek ?? 0
            let actualText = pace.isGaining ? "gaining about \(abs(actual).formatted(lbs)) lb/week" : "\(actual.formatted(lbs)) lb/week"
            lines.append("- Required pace for their deadline: \(pace.requiredPoundsPerWeek.formatted(lbs)) lb/week. Actual measured pace: \(actualText) (from weigh-ins, \(snapshot.trend.confidence.rawValue) confidence).")
            lines.append("- Goal trajectory: \(pace.status.title)\(pace.differenceSummary.map { " — \($0)" } ?? "").")
        }

        switch forecast.state {
        case .projected:
            if let date = forecast.projectedGoalDate {
                lines.append("- Projected goal date at the observed pace: around \(date.formatted(.dateTime.month(.wide).year())) (estimate, \(forecast.confidence.rawValue) confidence). Say it at month precision.")
            }
        case let .notProjected(reason):
            lines.append("- Projected goal date: \(reason)")
        case .goalReached:
            break
        }
        if let weight = forecast.projectedWeightAtDeadline {
            lines.append("- Projected weight on their deadline: about \(weight.lowerBound.formatted(whole))–\(weight.upperBound.formatted(whole)) lb (estimate).")
        }

        if plan.intensity != .standard {
            lines.append("- They chose to keep their exact target and deadline. Report the gap honestly and don't tell them to change the goal. Never suggest closing the gap with more restriction or extra exercise; coach consistent logging, planned workouts and recovery.")
            if plan.risk > .none {
                let risen = acknowledgedRequiredPace.map { plan.requiredPoundsPerWeek - $0 >= AggressiveMode.newWarningPaceIncrease } ?? false
                lines.append(risen
                    ? "- The required pace has risen meaningfully since they acknowledged the aggressive target. Briefly suggest reviewing the target with their healthcare professional."
                    : "- They've already acknowledged that this pace is above common guidance. Mention it at most once, briefly; don't repeat the warning.")
            }
        }
        return lines
    }

    /// Optional health background, sent only with consent. Emphasis shifts; the safe pace never rises because of it.
    nonisolated static func healthHistoryLines(_ history: HealthHistoryContext) -> [String] {
        guard history.hasAnything else { return [] }
        var lines = ["- Health background (shared by the user, treat as private):"]
        if history.bariatric == .yes {
            var surgery = "  • Previous bariatric surgery"
            if let type = history.surgeryType { surgery += ": \(type.label.lowercased())" }
            if let date = history.surgeryDate { surgery += ", around \(date.formatted(.dateTime.month(.wide).year()))" }
            lines.append(surgery + ".")
            lines.append("  • Put extra weight on adequate protein, hydration, nutritional adequacy, recovery and physical symptoms, and on follow-up with their bariatric care team. Rapid loss right after surgery doesn't mean the same pace is safe now.")
        }
        if let protein = history.clinicianProteinGrams {
            lines.append("  • Clinician protein target: \(Int(protein)) g/day.")
        }
        if !history.clinicianNutritionGoals.isEmpty {
            lines.append("  • Clinician nutrition goals: \(history.clinicianNutritionGoals)")
        }
        if !history.clinicianExerciseRestrictions.isEmpty {
            lines.append("  • Exercise restrictions from their clinician (respect these in every order): \(history.clinicianExerciseRestrictions)")
        }
        if let review = history.lastClinicalReview {
            lines.append("  • Last clinical review: \(review.formatted(.dateTime.month(.wide).year())).")
        }
        if !history.notes.isEmpty {
            lines.append("  • Their notes: \(history.notes)")
        }
        return lines
    }
}
