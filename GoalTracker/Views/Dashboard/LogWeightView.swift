import SwiftUI

struct LogWeightView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dismiss) private var dismiss

    @State private var pounds: Double?
    @State private var date = Date.now
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Weight (lb)") {
                        TextField("0.0", value: $pounds, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now)
                } footer: {
                    Text("Saved to Apple Health. Your Feelfit scale syncs automatically — use this for manual weigh-ins.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.red)
                }
            }
            .themedList()
            .navigationTitle("Log Weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled((pounds ?? 0) <= 0 || isSaving)
                }
            }
            .onAppear { pounds = pounds ?? health.latestWeightLbs }
        }
    }

    private func save() {
        guard let pounds, pounds > 0 else { return }
        isSaving = true
        Task {
            do {
                try await health.saveWeight(pounds: pounds, date: date)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
