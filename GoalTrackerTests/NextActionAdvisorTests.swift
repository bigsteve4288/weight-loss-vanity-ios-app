import Foundation
import Testing
@testable import GoalTracker

/// One next action, in priority order: safety and missing data first, routine last. Never "eat less" or "exercise more".
struct NextActionAdvisorTests {
    private let noon = Fixture.date(2026, 11, 4)
    private let morningWeighIn = Fixture.date(2026, 11, 4, hour: 7)
    private var yesterday: Date { Fixture.calendar.date(byAdding: .day, value: -1, to: morningWeighIn)! }

    private func advise(
        current: Double? = 224,
        history: [WeightPoint]? = nil,
        latestWeightDate: Date? = nil,
        targetDate: Date = Fixture.date(2027, 3, 4),
        consumed: Double = 500,
        entries: [Date]? = nil,
        now: Date? = nil
    ) -> NextAction {
        let now = now ?? noon
        let history = history ?? Fixture.history(endingAt: morningWeighIn, days: 14, from: 226.6, perDay: 0.2)
        let input = TargetEngine.Input(
            startWeight: 234,
            lossGoal: 34,
            targetDate: targetDate,
            currentWeight: current,
            latestWeightDate: latestWeightDate ?? history.last?.date,
            history: history,
            nutrition: Fixture.log(calories: consumed, entries: entries ?? (consumed > 0 ? [Fixture.date(2026, 11, 4, hour: 11)] : [])),
            activeBurn: 0,
            basalBurn: 0,
            restingCaloriesPerDay: 1800,
            rhythm: Fixture.rhythm,
            now: now,
            calendar: Fixture.calendar
        )
        return NextActionAdvisor.advise(TargetEngine.snapshot(input), now: now, calendar: Fixture.calendar)
    }

    @Test func noWeightAsksForTheFirstWeighIn() {
        let action = advise(current: nil, history: [])
        #expect(action.kind == .logWeight)
        #expect(action.title == "Log your first weigh-in")
    }

    @Test func goalReachedPointsToSettings() {
        let action = advise(current: 199.5, history: Fixture.history(endingAt: morningWeighIn, days: 14, from: 202, perDay: 0.2))
        #expect(action.kind == .openGoalSettings)
        #expect(action.title == "Set your next goal")
    }

    @Test func passedDeadlineAsksForANewDate() {
        let action = advise(targetDate: Fixture.date(2026, 10, 1))
        #expect(action.kind == .openGoalSettings)
        #expect(action.title == "Choose a new target date")
    }

    @Test func lowIntakeComesBeforeTheScale() {
        let stale = Fixture.history(endingAt: Fixture.calendar.date(byAdding: .day, value: -10, to: morningWeighIn)!, days: 14, from: 228, perDay: 0.2)
        let action = advise(
            history: stale,
            consumed: 900,
            entries: [8, 12, 18].map { Fixture.date(2026, 11, 4, hour: $0) },
            now: Fixture.date(2026, 11, 4, hour: 21)
        )
        #expect(action.title == "Check today's intake")
        #expect(action.kind == .logFood)
    }

    @Test func staleWeightAsksForAWeighIn() {
        let ended = Fixture.calendar.date(byAdding: .day, value: -10, to: morningWeighIn)!
        let action = advise(history: Fixture.history(endingAt: ended, days: 14, from: 228, perDay: 0.2))
        #expect(action.kind == .logWeight)
        #expect(action.title == "Weigh in")
        #expect(action.detail.hasPrefix("Your last weigh-in was 10 days ago."))
    }

    @Test func unrealisticDateInStandardModeAsksForAReview() {
        let action = advise(
            history: Fixture.history(endingAt: morningWeighIn, days: 14, from: 224.7, perDay: 0.05),
            targetDate: Fixture.date(2026, 12, 1)
        )
        #expect(action.kind == .openGoalSettings)
        #expect(action.title == "Review your target date")
    }

    @Test func missingMealsAskToLog() {
        let action = advise(consumed: 0, now: Fixture.date(2026, 11, 4, hour: 15))
        #expect(action.kind == .logFood)
        #expect(action.title == "Log today's meals")
    }

    @Test func thinHistoryCountsTheWeighInsStillNeeded() {
        let action = advise(history: Fixture.history(endingAt: yesterday, days: 2, from: 224.4, perDay: 0.2))
        #expect(action.kind == .logWeight)
        #expect(action.title == "Weigh in today")
        #expect(action.detail == "2 more weigh-in days unlock your measured pace.")
    }

    @Test func flatTrendSuggestsOneHabitNotRestriction() {
        let action = advise(history: Fixture.history(endingAt: morningWeighIn, days: 14, from: 224, perDay: 0))
        #expect(action.kind == .reflect)
        #expect(action.detail.contains("No crash fixes"))
    }

    @Test func noWeighInTodayIsAGentleNudge() {
        let action = advise(history: Fixture.history(endingAt: yesterday, days: 14, from: 226.8, perDay: 0.2))
        #expect(action.kind == .logWeight)
        #expect(action.title == "Weigh in today")
        #expect(action.detail == "Regular weigh-ins make your 7-day average more reliable.")
    }

    @Test func midDayWithWeighInSaysLogAsYouGo() {
        let action = advise()
        #expect(action.title == "Log meals as you go")
    }

    @Test func completeDaySaysDone() {
        let action = advise(
            consumed: 1800,
            entries: [8, 12, 18].map { Fixture.date(2026, 11, 4, hour: $0) },
            now: Fixture.date(2026, 11, 4, hour: 21)
        )
        #expect(action.kind == .none)
        #expect(action.title == "You're done for today")
    }

    @Test func noActionEverAsksToEatLessOrExerciseMore() {
        let actions = [
            advise(current: nil, history: []),
            advise(history: Fixture.history(endingAt: morningWeighIn, days: 14, from: 224, perDay: 0)),
            advise(history: Fixture.history(endingAt: morningWeighIn, days: 14, from: 224.7, perDay: 0.05), targetDate: Fixture.date(2026, 12, 1)),
            advise(consumed: 900, entries: [8, 12, 18].map { Fixture.date(2026, 11, 4, hour: $0) }, now: Fixture.date(2026, 11, 4, hour: 21)),
        ]
        let banned = ["eat less", "cut", "skip", "burn", "workout", "exercise more", "harder"]
        for action in actions {
            let text = (action.title + " " + action.detail).lowercased()
            #expect(!banned.contains { text.contains($0) }, "\(action.title): \(action.detail)")
        }
    }
}

struct SummaryDataTests {
    private let morningWeighIn = Fixture.date(2026, 11, 4, hour: 7)

    private func snapshot(history: [WeightPoint], basal: Double = 1500, loggedFood: Bool = true) -> TargetSnapshot {
        TargetEngine.snapshot(TargetEngine.Input(
            startWeight: 234, lossGoal: 34, targetDate: Fixture.date(2027, 3, 4),
            currentWeight: history.last?.pounds, latestWeightDate: history.last?.date, history: history,
            nutrition: loggedFood ? Fixture.log(calories: 500, entries: [Fixture.date(2026, 11, 4, hour: 11)]) : .empty,
            activeBurn: 200, basalBurn: basal, restingCaloriesPerDay: 1800, rhythm: Fixture.rhythm,
            now: Fixture.date(2026, 11, 4), calendar: Fixture.calendar
        ))
    }

    @Test func solidDataHasNoGapsAndAProjection() {
        let solid = snapshot(history: Fixture.history(endingAt: morningWeighIn, days: 28, from: 229.4, perDay: 0.2), basal: 1000)
        #expect(solid.dataGaps.isEmpty)
        #expect(solid.projectionSummary?.hasPrefix("Goal projected") == true)
    }

    @Test func gapsAreNamed() {
        let thin = snapshot(history: Fixture.history(endingAt: morningWeighIn, days: 2, from: 224.2, perDay: 0.2), basal: 0, loggedFood: false)
        #expect(thin.dataGaps == ["Too few weigh-ins for a pace", "Food not tracked in Apple Health", "Burn partly estimated"])
        #expect(thin.projectionSummary == "Goal date not projected yet")

        let stale = snapshot(history: Fixture.history(endingAt: Fixture.calendar.date(byAdding: .day, value: -10, to: morningWeighIn)!, days: 14, from: 228, perDay: 0.2))
        #expect(stale.dataGaps.first == "Weigh-in over a week old")
    }
}
