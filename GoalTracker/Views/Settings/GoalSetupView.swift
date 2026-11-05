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
    @State private var intensity: GoalIntensity = .standard
    @State private var clinicianMaxPace: Double?
    @State private var isConfirmingAggressive = false
    /// Set when the user accepts the acknowledgment in this session; written to the profile on save.
    @State private var acknowledgedAggressive = false

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

                goalModeSection

                Section {
                    LabeledContent("Resting calories / day") {
                        TextField("1800", value: $restingCalories, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Only used when Apple Health has no resting energy data (for example, without an Apple Watch).")
                }

                if let profile {
                    Section {
                        NavigationLink("Weight-Loss History (optional)") { WeightLossHistoryView(profile: profile) }
                    } footer: {
                        Text("Optional background such as bariatric surgery or clinician guidance. Stored only on this iPhone.")
                    }
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
            .alert(AggressiveMode.acknowledgmentTitle, isPresented: $isConfirmingAggressive) {
                Button("Continue with Aggressive Goal") {
                    acknowledgedAggressive = true
                    intensity = .aggressive
                }
                Button("Return to Standard Mode", role: .cancel) { intensity = .standard }
            } message: {
                Text(AggressiveMode.acknowledgmentText)
            }
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
            intensity = profile.intensity
            clinicianMaxPace = profile.clinicianMaxPoundsPerWeek
        } else {
            startWeight = health.latestWeightLbs
        }
    }

    private func save() {
        guard let startWeight, startWeight > 0 else { return }
        let saved: GoalProfile
        if let profile {
            saved = profile
            profile.startWeightLbs = startWeight
            profile.lossGoalLbs = lossGoal
            profile.targetDate = targetDate
            profile.restingCaloriesPerDay = restingCalories
        } else {
            saved = GoalProfile(startWeightLbs: startWeight, lossGoalLbs: lossGoal, targetDate: targetDate, restingCaloriesPerDay: restingCalories)
            context.insert(saved)
            for fraction in [0.25, 0.5, 0.75, 1.0] {
                let title = fraction == 1 ? "Birthday Goal" : "\(Int(fraction * 100))% Milestone"
                context.insert(WeightMilestone(title: title, targetWeightLbs: startWeight - lossGoal * fraction))
            }
        }
        GoalSettings.apply(
            intensity: intensity,
            clinicianMaxPace: clinicianMaxPace,
            acknowledgedAggressive: acknowledgedAggressive,
            requiredPace: requiredPace(for: saved),
            to: saved,
            context: context
        )
        dismiss()
    }

    private var goalModeSection: some View {
        Section {
            Picker("Goal mode", selection: Binding(get: { intensity }, set: select)) {
                ForEach(GoalIntensity.allCases) { Text($0.label).tag($0) }
            }
            if intensity == .clinicianGuided {
                LabeledContent("Clinician pace limit (lb/week)") {
                    TextField("optional", value: $clinicianMaxPace, format: decimal)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("Goal Mode")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(intensity.explanation)
                if intensity == .clinicianGuided {
                    Text("Only enter a limit your clinician actually gave you. Without one, general guidance is used. Vanity never suggests a deficit above 1,000 kcal/day in any mode.")
                }
            }
        }
    }

    /// Aggressive mode needs the one-time acknowledgment (per text version); other modes switch straight away.
    private func select(_ newValue: GoalIntensity) {
        let alreadyAcknowledged = acknowledgedAggressive || (profile?.hasAcknowledgedAggressiveMode ?? false)
        if newValue == .aggressive, !alreadyAcknowledged {
            isConfirmingAggressive = true
        } else {
            intensity = newValue
        }
    }

    private func requiredPace(for profile: GoalProfile) -> Double? {
        guard let current = health.latestWeightLbs else { return nil }
        return WeightGoalEngine.plan(.init(
            targetWeight: profile.targetWeightLbs, targetDate: profile.targetDate, currentWeight: current, latestWeightDate: health.latestWeightDate
        )).requiredPoundsPerWeek
    }
}

/// Saving goal-mode settings, kept out of the view so it can be tested.
enum GoalSettings {
    static func apply(
        intensity: GoalIntensity,
        clinicianMaxPace: Double?,
        acknowledgedAggressive: Bool,
        requiredPace: Double?,
        to profile: GoalProfile,
        context: ModelContext,
        now: Date = .now
    ) {
        profile.intensity = intensity
        profile.clinicianMaxPoundsPerWeek = clinicianMaxPace.flatMap { $0 > 0 ? $0 : nil }
        if intensity == .aggressive, acknowledgedAggressive {
            profile.acknowledgeAggressiveMode(requiredPace: requiredPace, now: now)
        }
        recordGoalChangeIfNeeded(profile, context: context, now: now)
    }

    /// Appends to the goal history only when the goal itself changed. Earlier entries are never edited.
    static func recordGoalChangeIfNeeded(_ profile: GoalProfile, context: ModelContext, now: Date = .now) {
        var latest = FetchDescriptor<GoalChange>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        latest.fetchLimit = 1
        if let last = try? context.fetch(latest).first, !last.differs(from: profile) { return }
        context.insert(GoalChange(profile: profile, date: now))
    }
}
