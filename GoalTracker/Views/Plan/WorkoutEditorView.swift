import SwiftData
import SwiftUI

struct WorkoutEditorView: View {
    let routine: WorkoutRoutine?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var focus = ""
    @State private var minutes = 45
    @State private var weekdays: Set<Int> = []
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Fasted Morning Burn)", text: $name)
                    TextField("Focus (e.g. HIIT, Legs, Zone 2)", text: $focus)
                    Stepper("\(minutes) minutes", value: $minutes, in: 5...240, step: 5)
                }
                Section("Days") {
                    HStack {
                        ForEach(1...7, id: \.self) { day in
                            let isOn = weekdays.contains(day)
                            Button {
                                if isOn { weekdays.remove(day) } else { weekdays.insert(day) }
                            } label: {
                                Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                                    .font(.subheadline.weight(.bold))
                                    .frame(width: 34, height: 34)
                                    .background(isOn ? Theme.gold : Color.white.opacity(0.08), in: Circle())
                                    .foregroundStyle(isOn ? .black : .primary)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                Section("Notes") {
                    TextField("Exercises, sets, reps…", text: $notes, axis: .vertical)
                        .lineLimit(4...12)
                }
            }
            .themedList()
            .navigationTitle(routine == nil ? "New Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let routine else { return }
                name = routine.name
                focus = routine.focus
                minutes = routine.durationMinutes
                weekdays = Set(routine.weekdays)
                notes = routine.notes
            }
        }
    }

    private func save() {
        let days = weekdays.sorted()
        if let routine {
            routine.name = name
            routine.focus = focus
            routine.durationMinutes = minutes
            routine.weekdays = days
            routine.notes = notes
        } else {
            context.insert(WorkoutRoutine(name: name, focus: focus, durationMinutes: minutes, weekdays: days, notes: notes))
        }
        dismiss()
    }
}

struct MilestoneEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var targetWeight: Double?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title (e.g. Under 200)", text: $title)
                LabeledContent("Target weight (lb)") {
                    TextField("0.0", value: $targetWeight, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            .themedList()
            .navigationTitle("New Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let targetWeight else { return }
                        context.insert(WeightMilestone(title: title, targetWeightLbs: targetWeight))
                        dismiss()
                    }
                    .disabled(title.isEmpty || (targetWeight ?? 0) <= 0)
                }
            }
        }
    }
}
