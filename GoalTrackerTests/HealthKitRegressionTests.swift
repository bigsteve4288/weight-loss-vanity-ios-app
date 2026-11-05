import Foundation
import HealthKit
import Testing
@testable import GoalTracker

/// Guards the Apple Health → WorkoutSummary mapping that Peloton and Nike Run Club workouts go through.
/// HKWorkout's initializers are deprecated in favour of HKWorkoutBuilder, which needs a live, authorized
/// store; the plain initializer is the only way to build a workout in a unit test.
struct HealthKitRegressionTests {
    private func workout(_ type: HKWorkoutActivityType, minutes: Double, kcal: Double, miles: Double?) -> HKWorkout {
        let start = Fixture.date(2026, 11, 4, hour: 7)
        let end = start.addingTimeInterval(minutes * 60)
        return HKWorkout(
            activityType: type, start: start, end: end, duration: minutes * 60,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
            totalDistance: miles.map { HKQuantity(unit: .mile(), doubleValue: $0) },
            metadata: nil
        )
    }

    @Test func pelotonStyleRideUsesTheWorkoutsOwnTotals() throws {
        let summary = WorkoutSummary(workout(.cycling, minutes: 45, kcal: 480, miles: 12.3))
        #expect(summary.activityName == "Ride")
        #expect(summary.duration == 45 * 60)
        #expect(summary.end.timeIntervalSince(summary.start) == 45 * 60)
        #expect(abs(try #require(summary.calories) - 480) < 0.001)
        #expect(abs(try #require(summary.distanceMiles) - 12.3) < 0.001)
        // Source attribution comes from the saved sample's sourceRevision, which an unsaved test workout doesn't have.
        #expect(summary.detailLine == "45 min · 12.30 mi · 480 kcal")
    }

    @Test func nikeRunClubStyleRun() throws {
        let summary = WorkoutSummary(workout(.running, minutes: 32, kcal: 410, miles: 3.1))
        #expect(summary.activityName == "Run")
        #expect(summary.symbolName == "figure.run")
        #expect(abs(try #require(summary.distanceMiles) - 3.1) < 0.001)
    }

    @Test func strengthWorkoutWithoutDistance() {
        let summary = WorkoutSummary(workout(.traditionalStrengthTraining, minutes: 20, kcal: 150, miles: nil))
        #expect(summary.activityName == "Strength")
        #expect(summary.distanceMiles == nil)
        #expect(summary.detailLine == "20 min · 150 kcal")
    }

    @Test func workoutFeedsTheEnergyMergeOnce() {
        // The same mapped workout seen with and without its samples synced is counted once either way.
        let summary = WorkoutSummary(workout(.cycling, minutes: 45, kcal: 480, miles: 12.3))
        func energy(sampled: Double, active: Double) -> EnergySummary {
            EnergyBalance.summarize(.init(
                basalObserved: 1500, activeObserved: active,
                workouts: [WorkoutEnergy(id: summary.id, start: summary.start, end: summary.end, source: summary.source, reportedCalories: summary.calories, sampledCaloriesInWindow: sampled)],
                restingCaloriesPerDay: 1800, now: Fixture.date(2026, 11, 4, hour: 18), calendar: Fixture.calendar
            ))
        }
        #expect(energy(sampled: 0, active: 200).active == 680)
        #expect(energy(sampled: 480, active: 680).active == 680)
    }
}
