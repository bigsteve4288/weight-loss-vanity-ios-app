import Foundation
import HealthKit

/// A workout read from Apple Health (Nike Run Club, Peloton, Apple Watch, …).
struct WorkoutSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let activityName: String
    let symbolName: String
    let start: Date
    let duration: TimeInterval
    let calories: Double?
    let distanceMiles: Double?
    let source: String

    var detailLine: String {
        var parts = ["\(Int((duration / 60).rounded())) min"]
        if let distanceMiles, distanceMiles > 0.05 { parts.append(String(format: "%.2f mi", distanceMiles)) }
        if let calories, calories > 0 { parts.append("\(Int(calories.rounded())) kcal") }
        return parts.joined(separator: " · ")
    }
}

extension WorkoutSummary {
    init(_ workout: HKWorkout) {
        // Some apps (e.g. Peloton) store totals on the workout itself instead of as separate samples,
        // so fall back to the workout's own totals when there are no per-sample statistics.
        let distance = [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)]
            .lazy
            .compactMap { workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .mile()) }
            .first ?? workout.totalDistance?.doubleValue(for: .mile())
        let calories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            ?? workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        self.init(
            id: workout.uuid,
            activityName: workout.workoutActivityType.displayName,
            symbolName: workout.workoutActivityType.symbolName,
            start: workout.startDate,
            duration: workout.duration,
            calories: calories,
            distanceMiles: distance,
            source: workout.sourceRevision.source.name
        )
    }
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: "Run"
        case .walking: "Walk"
        case .hiking: "Hike"
        case .cycling: "Ride"
        case .rowing: "Row"
        case .elliptical: "Elliptical"
        case .stairClimbing, .stairs: "Stairs"
        case .swimming: "Swim"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength"
        case .highIntensityIntervalTraining: "HIIT"
        case .coreTraining: "Core"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .flexibility, .cooldown: "Stretch"
        case .mindAndBody: "Meditation"
        case .boxing, .kickboxing: "Boxing"
        case .dance, .cardioDance: "Dance"
        default: "Workout"
        }
    }

    var symbolName: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .cycling: "figure.outdoor.cycle"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .stairClimbing, .stairs: "figure.stair.stepper"
        case .swimming: "figure.pool.swim"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "dumbbell.fill"
        case .highIntensityIntervalTraining: "bolt.heart.fill"
        case .coreTraining: "figure.core.training"
        case .yoga, .mindAndBody: "figure.mind.and.body"
        case .pilates, .flexibility, .cooldown: "figure.flexibility"
        case .boxing, .kickboxing: "figure.boxing"
        case .dance, .cardioDance: "figure.dance"
        default: "figure.mixed.cardio"
        }
    }
}
