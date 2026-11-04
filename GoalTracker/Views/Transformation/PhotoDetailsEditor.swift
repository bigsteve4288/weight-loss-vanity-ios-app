import SwiftUI

/// Lets the user correct when a photo was taken and what they weighed then, which the AI Coach relies on.
struct PhotoDetailsEditor: View {
    @Bindable var photo: ProgressPhoto
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now
    @State private var weight: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotoImage(photo: photo)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .listRowBackground(Color.clear)
                }
                Section {
                    DatePicker("Date taken", selection: $date, in: ...Date.now, displayedComponents: .date)
                    LabeledContent("Weight then (lb)") {
                        TextField("Unknown", value: $weight, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("The AI Coach uses these to judge how far you've come. Leave weight blank if you don't know it.")
                }
            }
            .themedList()
            .navigationTitle("Photo Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        photo.date = date
                        photo.weightLbs = (weight ?? 0) > 0 ? weight : nil
                        dismiss()
                    }
                }
            }
            .onAppear {
                date = photo.date
                weight = photo.weightLbs
            }
        }
    }
}
