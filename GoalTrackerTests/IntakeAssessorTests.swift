import Foundation
import Testing
@testable import GoalTracker

struct IntakeAssessorTests {
    private func assess(_ log: NutritionLog, at hour: Int, minute: Int = 0, rhythm: DailyRhythm = Fixture.rhythm) -> IntakeAssessment {
        IntakeAssessor.assess(log, rhythm: rhythm, now: Fixture.date(2026, 11, 4, hour: hour, minute: minute), calendar: Fixture.calendar)
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date { Fixture.date(2026, 11, 4, hour: hour, minute: minute) }

    /// The case from the brief: 190 kcal and 7 g protein at 9 AM is a started log, not a starving day.
    @Test func earlyMorningPartialLogging() {
        let result = assess(Fixture.log(calories: 190, protein: 7, entries: [at(8, 30)]), at: 9)
        #expect(result.state == .inProgress)
        #expect(!result.canJudgeDeficit)
        #expect(!result.lowIntakeConcern)
        #expect(result.summary.contains("started logging"))
        #expect(!result.summary.localizedCaseInsensitiveContains("only"))
        #expect(!result.summary.localizedCaseInsensitiveContains("starv"))
    }

    @Test func nothingLoggedBeforeAnyMealIsDue() {
        let result = assess(Fixture.log(), at: 7)
        #expect(result.state == .noEntriesYet)
        #expect(result.mealsDue == 0)
    }

    @Test func afterMidnightBeforeWakeNothingIsDue() {
        #expect(assess(Fixture.log(), at: 1).state == .noEntriesYet)
    }

    @Test func noFoodDataAtAll() {
        let result = assess(Fixture.log(loggedInPastWeek: false), at: 14)
        #expect(result.state == .notTracking)
        #expect(!result.canJudgeDeficit)
    }

    @Test func zeroEntriesWhenMealsHavePassedIsMissingNotRestriction() {
        let result = assess(Fixture.log(), at: 14)
        #expect(result.state == .missingLogs)
        #expect(result.mealsDue == 2)
        #expect(!result.lowIntakeConcern)
        #expect(result.summary.contains("aren't logged yet"))
    }

    @Test func lateDayIncompleteLogging() {
        let result = assess(Fixture.log(calories: 400, entries: [at(8)]), at: 21)
        #expect(result.isEatingDayOver)
        #expect(result.state == .missingLogs)
        #expect(!result.canJudgeDeficit)
        #expect(!result.lowIntakeConcern)
    }

    @Test func fullyLoggedDay() {
        let entries = [at(7, 30), at(12, 5), at(12, 20), at(18, 30)]
        let result = assess(Fixture.log(calories: 2100, protein: 160, entries: entries), at: 21)
        #expect(result.mealsLogged == 3)
        #expect(result.state == .complete)
        #expect(result.canJudgeDeficit)
        #expect(!result.lowIntakeConcern)
        #expect(result.confidence == .high)
    }

    @Test func actualLowIntakeGetsASupportiveCheckIn() {
        let entries = [at(7, 30), at(12), at(18, 30)]
        let result = assess(Fixture.log(calories: 900, protein: 50, entries: entries), at: 21)
        #expect(result.state == .complete)
        #expect(result.lowIntakeConcern)
        #expect(result.summary.contains("eating enough"))
    }

    @Test func missingMacroSamples() {
        let result = assess(Fixture.log(calories: 600, entries: [at(8)], hasProteinData: false), at: 10)
        #expect(result.proteinDataMissing)
        #expect(!assess(Fixture.log(loggedInPastWeek: true), at: 10).proteinDataMissing)
    }

    @Test func skippedBreakfastIsNotAMissingMeal() {
        var fasting = Fixture.rhythm
        fasting.breakfast = nil
        let result = assess(Fixture.log(calories: 700, entries: [at(12, 15)]), at: 14, rhythm: fasting)
        #expect(result.mealsDue == 1)
        #expect(result.state == .inProgress)
    }

    @Test func foodsLoggedTogetherCountAsOneMeal() {
        #expect(IntakeAssessor.occasions(in: []) == 0)
        #expect(IntakeAssessor.occasions(in: [at(12), at(12, 10), at(12, 40)]) == 1)
        #expect(IntakeAssessor.occasions(in: [at(18), at(7), at(12)]) == 3)
    }
}
