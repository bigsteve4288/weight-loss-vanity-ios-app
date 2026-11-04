import SwiftData
import SwiftUI

/// Asks when the user wakes, eats and sleeps, and shows the check-in times that come from it.
/// Shown once during onboarding and reachable later from the Mindset tab.
struct DailyRhythmView: View {
    let profile: GoalProfile
    let isOnboarding: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitManager.self) private var health
    @Environment(UserNotificationManager.self) private var notifications
    @Environment(CoachNotesManager.self) private var coachNotes

    @State private var wake = Date.now
    @State private var breakfast = Date.now
    @State private var skipsBreakfast = false
    @State private var lunch = Date.now
    @State private var dinner = Date.now
    @State private var bed = Date.now
    @State private var turnOnCheckIns = true
    @State private var isSaving = false

    private var rhythm: DailyRhythm {
        DailyRhythm(
            wake: wake.minutesAfterMidnight,
            breakfast: skipsBreakfast ? nil : breakfast.minutesAfterMidnight,
            lunch: lunch.minutesAfterMidnight,
            dinner: dinner.minutesAfterMidnight,
            bed: bed.minutesAfterMidnight
        )
    }

    var body: some View {
        content
            .themedList()
            .navigationTitle("Your Day")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isOnboarding ? "Done" : "Save") { Task { await save() } }
                        .disabled(!rhythm.isInOrder || isSaving)
                }
            }
            .onAppear(perform: load)
            .wrapInNavigationStack(isOnboarding)
    }

    private var content: some View {
        Form {
            if isOnboarding {
                Section {
                    Text("Your coach checks in at the moments that matter: when you wake up, before meals, in the snack window and at night. Tell it how your day runs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                DatePicker("Wake up", selection: $wake, displayedComponents: .hourAndMinute)
                Toggle("I skip breakfast", isOn: $skipsBreakfast)
                if !skipsBreakfast {
                    DatePicker("Breakfast", selection: $breakfast, displayedComponents: .hourAndMinute)
                }
                DatePicker("Lunch", selection: $lunch, displayedComponents: .hourAndMinute)
                DatePicker("Dinner", selection: $dinner, displayedComponents: .hourAndMinute)
                DatePicker("Bedtime", selection: $bed, displayedComponents: .hourAndMinute)
            } header: {
                Text("Your Day")
            } footer: {
                if !rhythm.isInOrder {
                    Text("Wake-up, breakfast, lunch and dinner need to be in order.").foregroundStyle(Theme.red)
                } else if skipsBreakfast {
                    Text("Your morning check-ins will help you hold your fasting window until lunch.")
                }
            }

            Section {
                ForEach(ReminderSlot.allCases) { slot in
                    LabeledContent {
                        Text(slot.derivedMinutes(for: rhythm).asTime(), format: .dateTime.hour().minute())
                    } label: {
                        Label(slot.label, systemImage: slot.systemImage)
                    }
                }
                if isOnboarding {
                    Toggle("Turn on check-ins", isOn: $turnOnCheckIns)
                }
            } header: {
                Text("Your Check-ins")
            } footer: {
                Text("You can fine-tune or turn off any of these later in the Mindset tab.")
            }
        }
    }

    private func load() {
        let current = profile.dailyRhythm
        wake = current.wake.asTime()
        skipsBreakfast = current.breakfast == nil
        breakfast = (current.breakfast ?? current.wake + 60).asTime()
        lunch = current.lunch.asTime()
        dinner = current.dinner.asTime()
        bed = current.bed.asTime()
    }

    private func save() async {
        isSaving = true
        // Fasting changes what the morning check-ins should say, so those get rewritten.
        let fastingChanged = (profile.breakfastMinutes == nil) != skipsBreakfast
        profile.dailyRhythm = rhythm
        // New times replace any fine-tuning, but reminders the user turned off stay off.
        profile.reminderOverrides = profile.reminderOverrides.filter { $0.value < 0 }
        if isOnboarding && turnOnCheckIns {
            profile.notificationsEnabled = await notifications.requestAuthorization()
        }
        profile.hasSetDailyRhythm = true
        if !isOnboarding { dismiss() }

        await notifications.reschedule(context: context, currentWeight: health.latestWeightLbs)
        if await coachNotes.refreshIfNeeded(context: context, health: health, force: fastingChanged) {
            await notifications.reschedule(context: context, currentWeight: health.latestWeightLbs)
        }
    }
}

private extension View {
    /// Onboarding presents this screen in a sheet, which needs its own navigation bar;
    /// from Mindset it's pushed onto an existing stack.
    @ViewBuilder
    func wrapInNavigationStack(_ wrap: Bool) -> some View {
        if wrap { NavigationStack { self } } else { self }
    }
}
