import Foundation
import Testing
@testable import GoalTracker

struct EnergyBalanceTests {
    private let evening = Fixture.date(2026, 11, 4, hour: 18)

    private func summarize(
        basal: Double = 1500,
        active: Double = 300,
        workouts: [WorkoutEnergy] = [],
        now: Date? = nil
    ) -> EnergySummary {
        EnergyBalance.summarize(.init(
            basalObserved: basal, activeObserved: active, workouts: workouts,
            restingCaloriesPerDay: 1800, now: now ?? evening, calendar: Fixture.calendar
        ))
    }

    @Test func pelotonCaloriesStoredOnlyOnTheWorkoutAreAdded() {
        let ride = Fixture.workout(Fixture.date(2026, 11, 4, hour: 7), minutes: 30, reported: 400, sampled: 0)
        let summary = summarize(workouts: [ride])
        #expect(summary.workoutSupplement == 400)
        #expect(summary.active == 700)
        #expect(summary.issues.contains(.workoutCaloriesAdded(count: 1)))
    }

    @Test func nikeRunWithSamplesIsNotCountedTwice() {
        let run = Fixture.workout(Fixture.date(2026, 11, 4, hour: 6), minutes: 35, reported: 350, sampled: 350, source: "Nike Run Club")
        let summary = summarize(workouts: [run])
        #expect(summary.workoutSupplement == 0)
        #expect(summary.active == 300)
    }

    @Test func sameRideRecordedByWatchAndPelotonCountsOnce() {
        let watch = Fixture.workout(Fixture.date(2026, 11, 4, hour: 7), minutes: 45, reported: 420, sampled: 420, source: "Apple Watch")
        let peloton = Fixture.workout(Fixture.date(2026, 11, 4, hour: 7, minute: 1), minutes: 45, reported: 480, sampled: 420)
        let summary = summarize(active: 600, workouts: [watch, peloton])
        // Keeps the higher of the two estimates for the session, adding only what samples don't already cover.
        #expect(summary.duplicateWorkoutIDs == [watch.id])
        #expect(abs(summary.workoutSupplement - 60) < 0.001)
        #expect(summary.issues.contains(.duplicateWorkoutsMerged(count: 1)))
    }

    @Test func partlyOverlappingWorkoutsShareTheOverlap() {
        let walk = Fixture.workout(Fixture.date(2026, 11, 4, hour: 10), minutes: 30, reported: 120, sampled: 0, source: "Apple Watch")
        let run = Fixture.workout(Fixture.date(2026, 11, 4, hour: 10, minute: 20), minutes: 40, reported: 400, sampled: 0, source: "Nike Run Club")
        let summary = summarize(workouts: [walk, run])
        #expect(summary.duplicateWorkoutIDs.isEmpty)
        // The run's first 10 of 40 minutes were already counted with the walk.
        #expect(abs(summary.workoutSupplement - (120 + 300)) < 0.001)
    }

    @Test func lateSyncingSamplesReplaceTheSupplementInsteadOfAddingToIt() {
        let start = Fixture.date(2026, 11, 4, hour: 7)
        let beforeSync = summarize(active: 300, workouts: [Fixture.workout(start, minutes: 30, reported: 400, sampled: 0)])
        // The watch's samples for the ride arrive later: the daily sum rises and the supplement falls to zero.
        let afterSync = summarize(active: 700, workouts: [Fixture.workout(start, minutes: 30, reported: 400, sampled: 400)])
        #expect(beforeSync.active == 700)
        #expect(afterSync.active == 700)
        #expect(afterSync.workoutSupplement == 0)
    }

    @Test func missingBasalIsEstimatedAndFlagged() {
        let summary = summarize(basal: 0)
        // 6 PM is 75% of the day.
        #expect(abs(summary.basal - 1350) < 0.5)
        #expect(summary.basalSource == .estimated)
        #expect(summary.includesEstimates)
        #expect(!summary.isReliable)
        #expect(summary.issues.contains(.noBasalData))
    }

    @Test func partialBasalIsToppedUpAndFlagged() {
        let summary = summarize(basal: 300)
        #expect(summary.basalSource == .observedPartial)
        #expect(abs(summary.basal - 1350) < 0.5)
        #expect(summary.basalObserved == 300)
        #expect(summary.issues.contains(.partialBasalData))
    }

    @Test func completeBasalIsUsedAsObserved() {
        let summary = summarize(basal: 1400)
        #expect(summary.basal == 1400)
        #expect(summary.basalSource == .observed)
        #expect(summary.isReliable)
    }

    @Test func noActiveEnergyLateInTheDayIsFlagged() {
        #expect(summarize(active: 0).issues.contains(.noActiveData))
        #expect(!summarize(active: 0, now: Fixture.date(2026, 11, 4, hour: 8)).issues.contains(.noActiveData))
    }

    @Test func workoutAcrossMidnightCountsOnlyTodaysPart() {
        let start = Fixture.date(2026, 11, 3, hour: 23, minute: 30)
        let summary = summarize(workouts: [Fixture.workout(start, minutes: 60, reported: 300, sampled: 0)], now: Fixture.date(2026, 11, 4, hour: 9))
        #expect(abs(summary.workoutSupplement - 150) < 0.001)
    }

    @Test func yesterdaysWorkoutIsIgnored() {
        let summary = summarize(workouts: [Fixture.workout(Fixture.date(2026, 11, 3, hour: 7), minutes: 30, reported: 400, sampled: 0)])
        #expect(summary.workoutSupplement == 0)
    }

    @Test func dayLengthFollowsDaylightSavingTime() {
        // Clocks fall back on Nov 1, 2026: midnight to noon is 13 real hours of a 25-hour day.
        let fraction = EnergyBalance.fractionOfDayElapsed(Fixture.date(2026, 11, 1, hour: 12), calendar: Fixture.calendar)
        #expect(abs(fraction - 13.0 / 25.0) < 0.0001)
    }
}
