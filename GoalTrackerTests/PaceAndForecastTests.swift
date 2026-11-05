import Foundation
import Testing
@testable import GoalTracker

struct RequiredPaceTests {
    private func plan(current: Double, target: Double, deadline: Date, now: Date = Fixture.date(2026, 11, 4)) -> GoalPlan {
        WeightGoalEngine.plan(.init(
            targetWeight: target, targetDate: deadline, currentWeight: current, latestWeightDate: now, now: now, calendar: Fixture.calendar
        ))
    }

    @Test func normalTarget() {
        // 24 lb over 120 days.
        #expect(abs(plan(current: 224, target: 200, deadline: Fixture.date(2027, 3, 4)).requiredPoundsPerWeek - 24.0 / 120 * 7) < 1e-9)
    }

    @Test func aggressiveTarget() {
        let now = Fixture.date(2026, 11, 5, hour: 9)
        #expect(abs(plan(current: 330, target: 300.7, deadline: Fixture.date(2026, 12, 14), now: now).requiredPoundsPerWeek - 29.3 / 39 * 7) < 1e-9)
    }

    @Test func targetAchievedIsNeverNegative() {
        let result = plan(current: 195, target: 200, deadline: Fixture.date(2027, 3, 4))
        #expect(result.requiredPoundsPerWeek == 0)
        #expect(result.feasibility == .achieved)
    }

    @Test func deadlineTodayStillHasToday() {
        let result = plan(current: 202, target: 200, deadline: Fixture.date(2026, 11, 4, hour: 20))
        #expect(result.daysRemaining == 0)
        #expect(result.feasibility != .deadlinePassed)
        #expect(abs(result.requiredPoundsPerWeek - 14) < 1e-9)
    }

    @Test func deadlinePassed() {
        let result = plan(current: 210, target: 200, deadline: Fixture.date(2026, 11, 3))
        #expect(result.feasibility == .deadlinePassed)
        #expect(result.requiredPoundsPerWeek == 0)
    }

    @Test func weightGainRaisesRequiredPace() {
        let deadline = Fixture.date(2027, 3, 4)
        #expect(plan(current: 230, target: 200, deadline: deadline).requiredPoundsPerWeek > plan(current: 224, target: 200, deadline: deadline).requiredPoundsPerWeek)
    }

    @Test func modifiedDeadlineAndTargetRecalculate() {
        let original = plan(current: 224, target: 200, deadline: Fixture.date(2027, 3, 4))
        let laterDate = plan(current: 224, target: 200, deadline: Fixture.date(2027, 7, 4))
        let lowerTarget = plan(current: 224, target: 190, deadline: Fixture.date(2027, 3, 4))
        #expect(laterDate.requiredPoundsPerWeek < original.requiredPoundsPerWeek)
        #expect(lowerTarget.requiredPoundsPerWeek > original.requiredPoundsPerWeek)
        #expect(lowerTarget.targetWeight == 190)
    }
}

struct PaceAndForecastTests {
    private let now = Fixture.date(2026, 11, 4)
    private let morning = Fixture.date(2026, 11, 4, hour: 7)

    private func evaluate(
        history: [WeightPoint],
        current: Double,
        target: Double = 200,
        deadline: Date = Fixture.date(2027, 3, 4),
        now: Date? = nil
    ) -> (pace: PaceAssessment, forecast: GoalForecast, plan: GoalPlan) {
        let now = now ?? self.now
        let plan = WeightGoalEngine.plan(.init(
            targetWeight: target, targetDate: deadline, currentWeight: current, latestWeightDate: history.last?.date,
            intensity: .aggressive, now: now, calendar: Fixture.calendar
        ))
        let trend = WeightTrendService.trend(history, now: now, calendar: Fixture.calendar)
        return (
            GoalForecastService.assessPace(plan: plan, trend: trend),
            GoalForecastService.forecast(plan: plan, trend: trend, currentWeight: current, now: now, calendar: Fixture.calendar),
            plan
        )
    }

    @Test func fourteenDayHistoryProjects() throws {
        let result = evaluate(history: Fixture.history(endingAt: morning, days: 10, from: 226, perDay: 0.2), current: 224.2)
        #expect(result.forecast.state == .projected)
        let date = try #require(result.forecast.projectedGoalDate)
        #expect(date > Fixture.date(2027, 1, 1) && date < Fixture.date(2027, 10, 1))
        #expect(result.forecast.confidence <= .medium)
        #expect(result.forecast.projectedWeightAtDeadline != nil)
    }

    @Test func twentyEightDayHistoryRaisesConfidence() {
        let result = evaluate(history: Fixture.history(endingAt: morning, days: 28, from: 229.6, perDay: 0.2), current: 224.2)
        #expect(result.forecast.state == .projected)
        #expect(result.forecast.confidence >= .medium)
    }

    @Test func limitedHistoryIsNotProjected() {
        let result = evaluate(history: [WeightPoint(date: morning, pounds: 224)], current: 224)
        #expect(result.pace.status == .insufficientData)
        #expect(result.pace.actualPoundsPerWeek == nil)
        #expect(result.forecast.projectedGoalDate == nil)
        guard case .notProjected = result.forecast.state else { Issue.record("expected notProjected"); return }
    }

    @Test func zeroLossIsNotProjected() throws {
        let result = evaluate(history: Fixture.history(endingAt: morning, days: 14, from: 224, perDay: 0), current: 224)
        #expect(result.forecast.state == .notProjected(reason: "Not currently projected: your weight is holding steady."))
        #expect(result.pace.status == .behindPace)
        let atDeadline = try #require(result.forecast.projectedWeightAtDeadline)
        #expect(abs(atDeadline.lowerBound - 224) < 0.5)
    }

    @Test func increasingWeightIsReportedAsGain() throws {
        let result = evaluate(history: Fixture.history(endingAt: morning, days: 14, from: 222, perDay: -0.15), current: 224)
        #expect(result.pace.isGaining)
        #expect(result.pace.status == .behindPace)
        #expect(result.forecast.state == .notProjected(reason: "Not currently projected: your weight is trending up."))
        #expect(try #require(result.forecast.projectedWeightAtDeadline).lowerBound > 224)
    }

    /// The brief's example: 5.3 lb/week required, about 2.1 lb/week observed.
    @Test func veryAggressiveRequiredPace() throws {
        let today = Fixture.date(2026, 11, 5, hour: 9)
        let history = Fixture.history(endingAt: Fixture.date(2026, 11, 5, hour: 7), days: 14, from: 334, perDay: 0.3)
        let result = evaluate(history: history, current: history.last!.pounds, target: 300.7, deadline: Fixture.date(2026, 12, 14), now: today)
        #expect(result.pace.status == .behindPace)
        #expect(abs((result.pace.actualPoundsPerWeek ?? 0) - 2.1) < 0.01)
        #expect((result.pace.paceDifference ?? 0) < -3)
        #expect(result.pace.differenceSummary?.contains("below required pace") == true)
        #expect(result.forecast.reachesTargetByDeadline == false)
        #expect(try #require(result.forecast.projectedGoalDate) > Fixture.date(2026, 12, 14))
        // The goal itself is untouched.
        #expect(result.plan.targetWeight == 300.7)
        #expect(result.plan.targetDate == Fixture.date(2026, 12, 14))
    }

    @Test func goalReached() {
        let result = evaluate(history: Fixture.history(endingAt: morning, days: 14, from: 202, perDay: 0.2), current: 199.4)
        #expect(result.pace.status == .goalReached)
        #expect(result.forecast.state == .goalReached)
        #expect(result.pace.requiredPoundsPerWeek == 0)
    }

    @Test func staleDataIsNotProjected() {
        let ended = Fixture.calendar.date(byAdding: .day, value: -12, to: morning)!
        let result = evaluate(history: Fixture.history(endingAt: ended, days: 14, from: 228, perDay: 0.2), current: 225.4)
        #expect(result.pace.status == .insufficientData)
        #expect(result.forecast.state == .notProjected(reason: "Not currently projected: no weigh-ins in the last week."))
    }

    @Test func paceStatusUsesTolerance() {
        // Required is 1.4 lb/week; tolerance is 0.25.
        let ahead = evaluate(history: Fixture.history(endingAt: morning, days: 14, from: 228, perDay: 0.3), current: 224)
        let onPace = evaluate(history: Fixture.history(endingAt: morning, days: 14, from: 226.6, perDay: 0.19), current: 224)
        let behind = evaluate(history: Fixture.history(endingAt: morning, days: 14, from: 225.3, perDay: 0.1), current: 224)
        #expect(ahead.pace.status == .aheadOfPace)
        #expect(onPace.pace.status == .onPace)
        #expect(behind.pace.status == .behindPace)
    }

    @Test func oneTemporaryGainDoesntFlipToBehind() {
        var history = Fixture.history(endingAt: morning, days: 14, from: 226.6, perDay: 0.2)
        history[12] = WeightPoint(date: history[12].date, pounds: history[12].pounds + 3)
        #expect(evaluate(history: history, current: 224, target: 200).pace.status != .behindPace)
    }
}
