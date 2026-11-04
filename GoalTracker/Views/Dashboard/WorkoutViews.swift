import SwiftUI

struct WorkoutSummaryRow: View {
    let workout: WorkoutSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.symbolName)
                .font(.title3)
                .foregroundStyle(Theme.gold)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activityName).font(.subheadline.weight(.bold))
                Text(workout.detailLine).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(workout.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption.weight(.semibold))
                Text(workout.source).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct WorkoutsCard: View {
    let workouts: [WorkoutSummary]

    private var today: [WorkoutSummary] { workouts.filter { Calendar.current.isDateInToday($0.start) } }
    private var lastSevenDays: [WorkoutSummary] {
        let cutoff = Date.now.addingTimeInterval(-7 * 86_400)
        return workouts.filter { $0.start >= cutoff }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Training", systemImage: "figure.run")
                if today.isEmpty {
                    Text("No workout logged today. Nike Run Club and Peloton sessions show up here once they sync to Apple Health.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.red)
                } else {
                    ForEach(today) { WorkoutSummaryRow(workout: $0) }
                }
                Divider().overlay(Theme.gold.opacity(0.3))
                let minutes = Int(lastSevenDays.reduce(0) { $0 + $1.duration } / 60)
                let calories = Int(lastSevenDays.compactMap(\.calories).reduce(0, +))
                Text("Last 7 days: \(lastSevenDays.count) workouts · \(minutes) min · \(calories) kcal")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
