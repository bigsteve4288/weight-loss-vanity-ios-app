import SwiftData
import SwiftUI

struct PlanView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Query(sort: \WeightMilestone.targetWeightLbs, order: .reverse) private var milestones: [WeightMilestone]
    @Query(sort: \WorkoutRoutine.createdAt) private var workouts: [WorkoutRoutine]

    @State private var editingWorkout: WorkoutRoutine?
    @State private var isAddingWorkout = false
    @State private var isAddingMilestone = false

    var body: some View {
        NavigationStack {
            List {
                Section("Weight Milestones") {
                    ForEach(milestones) { milestone in
                        HStack {
                            Image(systemName: milestone.achievedDate == nil ? "circle.dashed" : "checkmark.seal.fill")
                                .foregroundStyle(milestone.achievedDate == nil ? Color.secondary : Theme.gold)
                            VStack(alignment: .leading) {
                                Text(milestone.title).font(.headline)
                                if let achieved = milestone.achievedDate {
                                    Text("Hit \(achieved, format: .dateTime.month().day())").font(.caption).foregroundStyle(Theme.gold)
                                }
                            }
                            Spacer()
                            Text("\(milestone.targetWeightLbs, format: .number.precision(.fractionLength(1))) lb")
                                .font(.headline.monospacedDigit())
                        }
                    }
                    .onDelete { offsets in offsets.forEach { context.delete(milestones[$0]) } }
                }

                Section {
                    if health.recentWorkouts.isEmpty {
                        Text("No workouts in the last 14 days. Turn on Apple Health sync in Nike Run Club and Peloton.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(health.recentWorkouts) { WorkoutSummaryRow(workout: $0) }
                } header: {
                    Text("Recent Workouts · Apple Health")
                }

                Section("Workout Routines") {
                    if workouts.isEmpty {
                        Text("No routines yet. Tap + to build one.").foregroundStyle(.secondary)
                    }
                    ForEach(workouts) { workout in
                        Button { editingWorkout = workout } label: { WorkoutRow(workout: workout) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in offsets.forEach { context.delete(workouts[$0]) } }
                }
            }
            .themedList()
            .navigationTitle("Plan")
            .toolbar {
                Menu {
                    Button("New Workout Routine", systemImage: "dumbbell.fill") { isAddingWorkout = true }
                    Button("New Milestone", systemImage: "flag.checkered") { isAddingMilestone = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $isAddingWorkout) { WorkoutEditorView(routine: nil) }
            .sheet(item: $editingWorkout) { WorkoutEditorView(routine: $0) }
            .sheet(isPresented: $isAddingMilestone) { MilestoneEditorView() }
        }
    }
}

private struct WorkoutRow: View {
    let workout: WorkoutRoutine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workout.name).font(.headline)
                Spacer()
                Text("\(workout.durationMinutes) min").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.gold)
            }
            if !workout.focus.isEmpty {
                Text(workout.focus).font(.subheadline).foregroundStyle(.secondary)
            }
            if !workout.weekdays.isEmpty {
                Text(workout.weekdays.sorted().map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.red)
            }
        }
        .contentShape(Rectangle())
    }
}
