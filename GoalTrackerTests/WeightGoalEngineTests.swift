import Foundation
import Testing
@testable import GoalTracker

struct WeightGoalEngineTests {
    private func plan(
        target: Double,
        current: Double,
        deadline: Date,
        now: Date = Fixture.date(2026, 11, 4),
        weighedIn: Date? = Fixture.date(2026, 11, 4, hour: 7)
    ) -> GoalPlan {
        WeightGoalEngine.plan(.init(
            targetWeight: target, targetDate: deadline, currentWeight: current,
            latestWeightDate: weighedIn, now: now, calendar: Fixture.calendar
        ))
    }

    @Test func normalAchievableGoal() {
        // 24 lb in 120 days = 1.4 lb/week: above the steady 1 lb/week, within the 2 lb/week maximum.
        let plan = plan(target: 200, current: 224, deadline: Fixture.date(2027, 3, 4))
        #expect(plan.daysRemaining == 120)
        #expect(plan.feasibility == .ambitious)
        #expect(abs(plan.requiredPoundsPerWeek - 1.4) < 0.0001)
        #expect(abs(plan.recommendedPoundsPerWeek - 1.4) < 0.0001)
        #expect(abs(plan.recommendedDailyDeficitEstimate - 700) < 0.01)
        #expect(plan.suggestedTargetDate == nil)
        #expect(!plan.needsAdjustment)
    }

    @Test func comfortableGoal() {
        let plan = plan(target: 214, current: 224, deadline: Fixture.date(2027, 3, 4))
        #expect(plan.feasibility == .comfortable)
        #expect(plan.recommendedPoundsPerWeek < 1)
    }

    /// The real case from the brief: 330 → 300.7 lb by Dec 14, 2026.
    @Test func aggressiveDeadlineIsCappedNotChased() throws {
        let now = Fixture.date(2026, 11, 5, hour: 9)
        let deadline = Fixture.date(2026, 12, 14)
        let plan = plan(target: 300.7, current: 330, deadline: deadline, now: now, weighedIn: now)

        #expect(plan.daysRemaining == 39)
        #expect(abs(plan.requiredPoundsPerWeek - 5.26) < 0.01)
        #expect(abs(plan.requiredDailyDeficitEstimate - 2629) < 1)
        #expect(plan.feasibility == .exceedsSustainable)
        #expect(plan.needsAdjustment)

        // The plan never exceeds the sustainable maximum or the deficit cap.
        #expect(plan.recommendedPoundsPerWeek == 2.0)
        #expect(plan.recommendedDailyDeficitEstimate == 1000)

        let atDeadline = try #require(plan.projectedWeightAtDeadline)
        #expect(abs(atDeadline.lowerBound - (330 - 2.0 * 39 / 7)) < 0.01)
        #expect(abs(atDeadline.upperBound - (330 - 1.0 * 39 / 7)) < 0.01)

        let dates = try #require(plan.projectedTargetDate)
        #expect(dates.lowerBound > deadline)
        #expect(dates.upperBound > dates.lowerBound)
        #expect(plan.suggestedTargetDate == dates.upperBound)
    }

    @Test func pastDeadlineSuggestsANewDate() {
        let plan = plan(target: 200, current: 220, deadline: Fixture.date(2026, 10, 1))
        #expect(plan.feasibility == .deadlinePassed)
        #expect(plan.requiredPoundsPerWeek == 0)
        #expect(plan.projectedWeightAtDeadline == nil)
        #expect(plan.recommendedPoundsPerWeek == 1.0)
        #expect((plan.suggestedTargetDate ?? .distantPast) > Fixture.date(2026, 11, 4))
    }

    @Test func goalAlreadyAchieved() {
        let plan = plan(target: 200, current: 199, deadline: Fixture.date(2027, 3, 4))
        #expect(plan.feasibility == .achieved)
        #expect(plan.poundsRemaining == 0)
        #expect(plan.recommendedPoundsPerWeek == 0)
        #expect(plan.recommendedDailyDeficitEstimate == 0)
        #expect(plan.projectedTargetDate == nil)
    }

    @Test func weightGainRaisesRemainingWithoutRaisingTheCap() {
        // Gained past the start weight: more to lose, but the plan still caps at the sustainable maximum.
        let plan = plan(target: 200, current: 240, deadline: Fixture.date(2026, 12, 4))
        #expect(plan.poundsRemaining == 40)
        #expect(plan.feasibility == .exceedsSustainable)
        #expect(plan.recommendedPoundsPerWeek == 2.0)
    }

    @Test func lighterBodiesGetALowerCap() {
        // 1% of 140 lb is 1.4 lb/week.
        let plan = plan(target: 120, current: 140, deadline: Fixture.date(2026, 12, 4))
        #expect(abs(plan.sustainablePace.upperBound - 1.4) < 0.0001)
        #expect(plan.recommendedPoundsPerWeek <= 1.4 + 1e-9)
        #expect(plan.recommendedDailyDeficitEstimate <= 700.0001)
    }

    @Test(arguments: [150.0, 200, 250, 330, 450])
    func neverRecommendsMoreThanTheCaps(current: Double) {
        for days in [1, 7, 14, 30, 90, 365] {
            let deadline = Fixture.calendar.date(byAdding: .day, value: days, to: Fixture.date(2026, 11, 4))!
            let plan = plan(target: current - 60, current: current, deadline: deadline)
            #expect(plan.recommendedPoundsPerWeek <= PacePolicy.standard.maximumPoundsPerWeek)
            #expect(plan.recommendedPoundsPerWeek <= plan.sustainablePace.upperBound)
            #expect(plan.recommendedDailyDeficitEstimate <= PacePolicy.standard.maximumDailyDeficit)
        }
    }

    @Test func staleOrMissingWeighInsLowerConfidence() {
        let deadline = Fixture.date(2027, 3, 4)
        #expect(plan(target: 200, current: 224, deadline: deadline, weighedIn: Fixture.date(2026, 10, 20)).weightIsStale)
        #expect(plan(target: 200, current: 224, deadline: deadline, weighedIn: nil).weightIsStale)
        #expect(!plan(target: 200, current: 224, deadline: deadline, weighedIn: Fixture.date(2026, 11, 1)).weightIsStale)
    }
}
