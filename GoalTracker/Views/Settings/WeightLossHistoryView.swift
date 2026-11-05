import SwiftUI

/// Optional weight-loss background. Nothing here is required for any goal mode. Stored on this iPhone,
/// shared with the AI Coach only when the user turns that on, and never used in notifications.
struct WeightLossHistoryView: View {
    @Bindable var profile: GoalProfile

    private let decimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))

    var body: some View {
        Form {
            Section {
                Picker("Bariatric surgery", selection: $profile.bariatricHistory) {
                    ForEach(BariatricHistory.allCases) { Text($0.label).tag($0) }
                }
                if profile.bariatricHistory == .yes {
                    Picker("Surgery type", selection: $profile.surgeryType) {
                        Text("Not set").tag(SurgeryType?.none)
                        ForEach(SurgeryType.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                    OptionalDateRow(title: "Approximate surgery date", date: $profile.surgeryDate)
                }
            } header: {
                Text("Surgery History")
            } footer: {
                Text("Used only to tailor safety explanations and coaching emphasis (protein, hydration, recovery, follow-up). It never raises the pace Vanity treats as safe.")
            }

            Section {
                TextField("Nutrition goals from your clinician", text: $profile.clinicianNutritionGoals, axis: .vertical)
                LabeledContent("Protein target (g/day)") {
                    TextField("optional", value: $profile.clinicianProteinGrams, format: decimal)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Exercise restrictions", text: $profile.clinicianExerciseRestrictions, axis: .vertical)
                OptionalDateRow(title: "Last clinical review", date: $profile.lastClinicalReviewDate)
            } header: {
                Text("Clinician Guidance")
            } footer: {
                Text("Record what your care team told you. Vanity doesn't verify it and doesn't provide medical supervision.")
            }

            Section("Notes") {
                TextField("Anything else about your weight-loss history", text: $profile.weightLossNotes, axis: .vertical)
            }

            Section {
                Toggle("Include in AI Coach requests", isOn: $profile.shareHealthHistoryWithCoach)
            } footer: {
                Text("When on, this information is sent to Anthropic's API with your AI Coach verdicts so coaching can account for it. It's never included in check-in notifications or anything you share.")
            }
        }
        .themedList()
        .navigationTitle("Weight-Loss History")
    }
}

private struct OptionalDateRow: View {
    let title: String
    @Binding var date: Date?

    var body: some View {
        Toggle(title, isOn: Binding(get: { date != nil }, set: { date = $0 ? (date ?? .now) : nil }))
        if let current = date {
            DatePicker(title, selection: Binding(get: { current }, set: { date = $0 }), in: ...Date.now, displayedComponents: .date)
                .labelsHidden()
        }
    }
}
