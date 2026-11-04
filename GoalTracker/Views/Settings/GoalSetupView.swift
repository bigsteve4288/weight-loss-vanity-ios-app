import SwiftData
import SwiftUI

/// First-run goal setup, also reused for editing the goal later.
struct GoalSetupView: View {
    let profile: GoalProfile?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitManager.self) private var health

    @State private var startWeight: Double?
    @State private var lossGoal: Double = 34
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 4, to: .now) ?? .now
    @State private var restingCalories: Double = 1800

    private let decimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))

    var body: some View {
        NavigationStack {
            Form {
                if profile == nil {
                    Section {
                        Text("Lock in the target. Every number on the dashboard is measured against it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Starting Point") {
                    LabeledContent("Starting weight (lb)") {
                        TextField("0.0", value: $startWeight, format: decimal)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if let latest = health.latestWeightLbs, latest != startWeight {
                        Button("Use latest from Apple Health (\(latest.formatted(decimal)) lb)") { startWeight = latest }
                    }
                }

                Section("Target") {
                    LabeledContent("Pounds to lose") {
                        TextField("34", value: $lossGoal, format: decimal)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("Target birthday", selection: $targetDate, in: Date.now..., displayedComponents: .date)
                    if let startWeight {
                        LabeledContent("Target weight", value: "\((startWeight - lossGoal).formatted(decimal)) lb")
                            .foregroundStyle(Theme.gold)
                    }
                }

                Section {
                    LabeledContent("Resting calories / day") {
                        TextField("1800", value: $restingCalories, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Only used when Apple Health has no resting energy data (for example, without an Apple Watch).")
                }

                if health.isAvailable && !health.hasRequestedAuthorization {
                    Section {
                        Button("Connect Apple Health") { Task { await health.start() } }
                    }
                }
            }
            .themedList()
            .navigationTitle(profile == nil ? "Set Your Goal" : "Goal Settings")
            .toolbar {
                if profile != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(profile == nil ? "Start" : "Save", action: save)
                        .disabled((startWeight ?? 0) <= 0 || lossGoal <= 0)
                }
            }
            .onAppear(perform: load)
            .onChange(of: health.latestWeightLbs) { _, latest in
                if profile == nil, startWeight == nil { startWeight = latest }
            }
        }
    }

    private func load() {
        if let profile {
            startWeight = profile.startWeightLbs
            lossGoal = profile.lossGoalLbs
            targetDate = profile.targetDate
            restingCalories = profile.restingCaloriesPerDay
        } else {
            startWeight = health.latestWeightLbs
        }
    }

    private func save() {
        guard let startWeight, startWeight > 0 else { return }
        if let profile {
            profile.startWeightLbs = startWeight
            profile.lossGoalLbs = lossGoal
            profile.targetDate = targetDate
            profile.restingCaloriesPerDay = restingCalories
        } else {
            context.insert(GoalProfile(startWeightLbs: startWeight, lossGoalLbs: lossGoal, targetDate: targetDate, restingCaloriesPerDay: restingCalories))
            for fraction in [0.25, 0.5, 0.75, 1.0] {
                let title = fraction == 1 ? "Birthday Goal" : "\(Int(fraction * 100))% Milestone"
                context.insert(WeightMilestone(title: title, targetWeightLbs: startWeight - lossGoal * fraction))
            }
        }
        dismiss()
    }
}
