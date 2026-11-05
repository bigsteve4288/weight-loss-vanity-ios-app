import Foundation
import Testing
@testable import GoalTracker

struct TargetEngineTests {
    private let calendar = Fixture.calendar
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Fixture.date(year, month, day, hour: hour)
    }

    private func input(
        current: Double?,
        consumed: Double = 500,
        entries: [Date]? = nil,
        active: Double = 0,
        basal: Double = 0,
        history: [WeightPoint] = [],
        now: Date? = nil
    ) -> TargetEngine.Input {
        let now = now ?? date(2026, 11, 4)
        return TargetEngine.Input(
            startWeight: 234,
            lossGoal: 34,
            targetDate: date(2027, 3, 4),
            currentWeight: current,
            latestWeightDate: now,
            history: history,
            nutrition: Fixture.log(calories: consumed, entries: entries ?? (consumed > 0 ? [now.addingTimeInterval(-3600)] : [])),
            activeBurn: active,
            basalBurn: basal,
            restingCaloriesPerDay: 1800,
            rhythm: Fixture.rhythm,
            now: now,
            calendar: calendar
        )
    }

    @Test func targetWeightAndRemaining() {
        let snapshot = TargetEngine.snapshot(input(current: 224))
        #expect(snapshot.targetWeight == 200)
        #expect(snapshot.poundsLost == 10)
        #expect(snapshot.poundsRemaining == 24)
        #expect(abs(snapshot.progress - 10.0 / 34.0) < 0.0001)
    }

    @Test func daysAndRequiredDeficitStayAsContext() {
        let snapshot = TargetEngine.snapshot(input(current: 224))
        #expect(snapshot.daysRemaining == 120)
        #expect(abs(snapshot.requiredDailyDeficit - 24 * 3500 / 120) < 0.0001)
        #expect(abs(snapshot.requiredPoundsPerWeek - 24 / (120.0 / 7)) < 0.0001)
        #expect(!snapshot.exceedsSafePace)
    }

    /// The brief's example. The old engine said PUSH HARDER against a 2,629 kcal/day target.
    @Test func unrealisticDeadlineAsksForAdjustmentNotAHarderDeficit() {
        var rushed = input(current: 330, consumed: 190, now: Fixture.date(2026, 11, 5, hour: 9))
        rushed.startWeight = 334.7
        rushed.lossGoal = 34
        rushed.targetDate = date(2026, 12, 14)
        let snapshot = TargetEngine.snapshot(rushed)
        #expect(snapshot.status == .goalNeedsAdjustment)
        #expect(snapshot.exceedsSafePace)
        #expect(abs(snapshot.requiredDailyDeficit - 2629) < 1)
        #expect(snapshot.plan.recommendedDailyDeficitEstimate <= 1000)
        #expect(!snapshot.status.message.localizedCaseInsensitiveContains("tighten"))
    }

    @Test func morningPartialLogIsNotGraded() {
        // 9 AM with 190 kcal logged: the old engine graded this partial day against the full-day deficit.
        let snapshot = TargetEngine.snapshot(input(current: 224, consumed: 190, entries: [date(2026, 11, 4, hour: 8)], now: date(2026, 11, 4, hour: 9)))
        #expect(snapshot.intake.state == .inProgress)
        #expect(!snapshot.intake.canJudgeDeficit)
        #expect(snapshot.status == .buildingMomentum)
    }

    @Test func todaysDeficitNoLongerDrivesTheStatus() {
        // Same trend, wildly different days: the verdict doesn't swing with a partial day's deficit.
        let history = Fixture.history(endingAt: date(2026, 11, 4, hour: 7), days: 10, from: 226, perDay: 0.2)
        let light = TargetEngine.snapshot(input(current: 224.2, consumed: 1000, active: 500, basal: 1300, history: history))
        let heavy = TargetEngine.snapshot(input(current: 224.2, consumed: 2500, active: 300, basal: 1300, history: history))
        #expect(light.status == heavy.status)
    }

    @Test func trendMeetingThePlanIsOnTrack() {
        // 1.4 lb/week (0.2/day) against a 1.4 lb/week plan.
        let history = Fixture.history(endingAt: date(2026, 11, 4, hour: 7), days: 10, from: 226, perDay: 0.2)
        let snapshot = TargetEngine.snapshot(input(current: 224.2, history: history))
        #expect(snapshot.status == .onTrack)
        #expect(!snapshot.paceAboveSustainable)
    }

    @Test func slowerLossIsBuildingMomentum() {
        let history = Fixture.history(endingAt: date(2026, 11, 4, hour: 7), days: 10, from: 225, perDay: 0.08)
        #expect(TargetEngine.snapshot(input(current: 224.3, history: history)).status == .buildingMomentum)
    }

    @Test func flatOrRisingTrendNeedsAttention() {
        let flat = Fixture.history(endingAt: date(2026, 11, 4, hour: 7), days: 10, from: 224, perDay: 0)
        let rising = Fixture.history(endingAt: date(2026, 11, 4, hour: 7), days: 10, from: 222, perDay: -0.2)
        #expect(TargetEngine.snapshot(input(current: 224, history: flat)).status == .needsAttention)
        #expect(TargetEngine.snapshot(input(current: 224, history: rising)).status == .needsAttention)
    }

    @Test func missingMealsShowLoggingIncompleteUnlessTheTrendIsGood() {
        let afternoon = date(2026, 11, 4, hour: 15)
        #expect(TargetEngine.snapshot(input(current: 224, consumed: 0, now: afternoon)).status == .loggingIncomplete)
        let good = Fixture.history(endingAt: date(2026, 11, 4, hour: 7), days: 10, from: 226, perDay: 0.2)
        #expect(TargetEngine.snapshot(input(current: 224.2, consumed: 0, history: good, now: afternoon)).status == .onTrack)
    }

    @Test func veryFastTrendIsFlaggedNotRewarded() {
        // Before the Nov 1 DST change, so every gap is exactly 24 hours.
        let history = (0..<8).map { WeightPoint(date: date(2026, 10, 22 + $0), pounds: 228 - Double($0) * 0.5) }
        let snapshot = TargetEngine.snapshot(input(current: 224, consumed: 3000, basal: 1300, history: history))
        #expect(abs((snapshot.actualPoundsPerWeek ?? 0) - 3.5) < 0.0001)
        #expect(snapshot.status == .onTrack)
        #expect(snapshot.paceAboveSustainable)
    }

    @Test func specialStatuses() {
        #expect(TargetEngine.snapshot(input(current: nil)).status == .needsData)
        #expect(TargetEngine.snapshot(input(current: 199)).status == .goalReached)
        var late = input(current: 220)
        late.now = date(2027, 3, 5)
        #expect(TargetEngine.snapshot(late).status == .deadlinePassed)
    }

    @Test func weightGainShowsNoNegativeProgress() {
        let snapshot = TargetEngine.snapshot(input(current: 238))
        #expect(snapshot.progress == 0)
        #expect(snapshot.poundsLost == -4)
        #expect(snapshot.poundsRemaining == 38)
    }

    @Test func flagsUnsafePace() {
        var rushed = input(current: 234)
        rushed.targetDate = date(2026, 12, 4)
        #expect(TargetEngine.snapshot(rushed).exceedsSafePace)
    }

    @Test func fallsBackToProratedRestingCalories() {
        // Noon: half of the 1800 kcal fallback has been burned.
        let snapshot = TargetEngine.snapshot(input(current: 224, consumed: 400, basal: 0))
        #expect(abs(snapshot.todayBurn - 900) < 0.5)
        #expect(abs(snapshot.todayDeficit - 500) < 0.5)
        #expect(snapshot.energy.basalSource == .estimated)
    }

    @Test func trendNeedsEnoughSpread() {
        let now = date(2026, 11, 4)
        let close = [WeightPoint(date: date(2026, 11, 3), pounds: 225), WeightPoint(date: now, pounds: 224)]
        #expect(WeightTrendService.trend(close, now: now, calendar: calendar).actualPoundsPerWeek == nil)
    }

    @Test func irregularWeighInsDontProduceAStatusTrend() {
        // Two readings ten days apart are too few to grade a trend on.
        let sparse = [WeightPoint(date: date(2026, 10, 25), pounds: 228), WeightPoint(date: date(2026, 11, 4, hour: 7), pounds: 224)]
        let snapshot = TargetEngine.snapshot(input(current: 224, history: sparse))
        #expect(snapshot.actualPoundsPerWeek == nil)
        #expect(snapshot.status == .buildingMomentum)
    }

    @Test func unsortedHistoryGivesTheSameTrend() throws {
        let history = Fixture.history(endingAt: date(2026, 11, 4, hour: 7), days: 10, from: 226, perDay: 0.2)
        let now = date(2026, 11, 4)
        let forward = try #require(WeightTrendService.trend(history, now: now, calendar: calendar).actualPoundsPerWeek)
        let backward = try #require(WeightTrendService.trend(history.reversed(), now: now, calendar: calendar).actualPoundsPerWeek)
        #expect(abs(forward - backward) < 1e-9)
    }
}

struct NotificationContentTests {
    @Test func countdownShowsLiveNumbers() {
        #expect(NotificationContent.countdown(daysLeft: 120, poundsLeft: 24) == "120 days · 24.0 lb to go")
        #expect(NotificationContent.countdown(daysLeft: 1, poundsLeft: nil) == "1 day")
        #expect(NotificationContent.countdown(daysLeft: 5, poundsLeft: 0) == "5 days · goal weight reached")
    }

    @Test func fastingMorningsGetFastingPrompts() {
        let body = NotificationContent.body(slot: .beforeBreakfast, skipsBreakfast: true, quote: nil, index: 0)
        #expect(body.contains("fasting window"))
    }
}
