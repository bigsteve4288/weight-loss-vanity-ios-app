import SwiftData
import SwiftUI

struct MindsetView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(UserNotificationManager.self) private var notifications

    @Query private var profiles: [GoalProfile]
    @Query(sort: \SpiritualQuote.createdAt, order: .reverse) private var quotes: [SpiritualQuote]

    @State private var isShowingReset = false
    @State private var isAddingQuote = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    EmergencyResetButton { isShowingReset = true }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                if let profile = profiles.first {
                    NotificationSettingsSection(profile: profile, reschedule: reschedule, sendTest: { sendTest(profile) })
                }

                Section {
                    ForEach(quotes) { quote in
                        QuoteRow(quote: quote)
                    }
                    .onDelete { offsets in
                        offsets.forEach { context.delete(quotes[$0]) }
                    }
                } header: {
                    Text("Spiritual Quote Log")
                } footer: {
                    Text("Favorites are shown first during an Emergency Reset. All quotes rotate through daily notifications.")
                }
            }
            .themedList()
            .navigationTitle("Mindset")
            .toolbar {
                Button("Add Quote", systemImage: "plus") { isAddingQuote = true }
            }
            .sheet(isPresented: $isAddingQuote) { QuoteEditorView() }
            .fullScreenCover(isPresented: $isShowingReset) { EmergencyResetView() }
        }
    }

    private func reschedule() async {
        await notifications.reschedule(context: context, currentWeight: health.latestWeightLbs)
    }

    private func sendTest(_ profile: GoalProfile) {
        Task {
            await notifications.sendTestNotification(context: context, currentWeight: health.latestWeightLbs)
        }
    }
}

private struct NotificationSettingsSection: View {
    @Bindable var profile: GoalProfile
    let reschedule: () async -> Void
    let sendTest: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(UserNotificationManager.self) private var notifications
    @Environment(CoachNotesManager.self) private var coachNotes

    private var enabled: Binding<Bool> {
        Binding {
            profile.notificationsEnabled
        } set: { isOn in
            Task {
                profile.notificationsEnabled = isOn ? await notifications.requestAuthorization() : false
                await reschedule()
                if profile.notificationsEnabled, await coachNotes.refreshIfNeeded(context: context, health: health) {
                    await reschedule()
                }
            }
        }
    }

    private var daySummary: String {
        let time = Date.FormatStyle.dateTime.hour().minute()
        return "Wake \(profile.wakeMinutes.asTime().formatted(time)) · Bed \(profile.bedMinutes.asTime().formatted(time))"
    }

    var body: some View {
        Section {
            Toggle("Coach Check-ins", isOn: enabled)
            if profile.notificationsEnabled {
                NavigationLink {
                    DailyRhythmView(profile: profile, isOnboarding: false)
                } label: {
                    LabeledContent("Your Day", value: daySummary)
                }
                ForEach(ReminderSlot.allCases) { slot in
                    ReminderSlotRow(profile: profile, slot: slot)
                }
                CoachNotesStatus(reschedule: reschedule)
                LabeledContent("Scheduled", value: "\(notifications.scheduledCount) check-ins this week")
            }
            Button("Send Test Notification (5s)", systemImage: "bell.badge", action: sendTest)
            if let status = notifications.testStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(notifications.isDenied ? Theme.red : .secondary)
            }
            if notifications.isDenied {
                Button("Open Notification Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } header: {
            Text("Lock-Screen Check-ins")
        } footer: {
            Text("Your coach writes today's and tomorrow's check-ins and refreshes them about every 12 hours, using your latest numbers. Built-in messages fill in when it can't. Each one shows your live countdown.")
        }
        .onChange(of: profile.reminderOverrides) { Task { await reschedule() } }
    }
}

/// One check-in: on/off, and its time (derived from the user's day unless they change it).
private struct ReminderSlotRow: View {
    @Bindable var profile: GoalProfile
    let slot: ReminderSlot

    private var isOn: Binding<Bool> {
        Binding {
            slot.minutes(for: profile) != nil
        } set: { on in
            if on { profile.reminderOverrides[slot.rawValue] = nil } else { profile.reminderOverrides[slot.rawValue] = -1 }
        }
    }

    private var time: Binding<Date> {
        Binding {
            (slot.minutes(for: profile) ?? slot.derivedMinutes(for: profile.dailyRhythm)).asTime()
        } set: { date in
            let minutes = date.minutesAfterMidnight
            profile.reminderOverrides[slot.rawValue] = minutes == slot.derivedMinutes(for: profile.dailyRhythm) ? nil : minutes
        }
    }

    var body: some View {
        HStack {
            Label(slot.label, systemImage: slot.systemImage)
                .foregroundStyle(isOn.wrappedValue ? .primary : .secondary)
            Spacer()
            if isOn.wrappedValue {
                DatePicker(slot.label, selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            Toggle(slot.label, isOn: isOn)
                .labelsHidden()
        }
    }
}

/// Whether the coach or the built-in library is writing the check-ins, and a way to rewrite now.
private struct CoachNotesStatus: View {
    let reschedule: () async -> Void
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(CoachNotesManager.self) private var coachNotes
    @Query(sort: \CoachNote.day, order: .reverse) private var notes: [CoachNote]

    private var hasAccessCode: Bool { KeychainStore.read(KeychainStore.anthropicAPIKey) != nil }

    var body: some View {
        if coachNotes.isWriting {
            HStack(spacing: 10) {
                ProgressView()
                Text("Your coach is writing your check-ins…").font(.subheadline).foregroundStyle(.secondary)
            }
        } else if !hasAccessCode {
            Text("Using built-in messages. Add your access code in AI Coach (Transform tab) and your coach will write them for you.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let error = coachNotes.lastError {
                    Text("Couldn't write new check-ins: \(error)").font(.caption).foregroundStyle(Theme.red)
                }
                if let last = notes.first, let written = notes.map(\.createdAt).max() {
                    Text("Written by your coach through \(last.day.formatted(.dateTime.weekday(.wide))) · updated \(written.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Rewrite Now", systemImage: "arrow.clockwise") {
                    Task {
                        if await coachNotes.refreshIfNeeded(context: context, health: health, force: true) {
                            await reschedule()
                        }
                    }
                }
            }
        }
    }
}

private struct QuoteRow: View {
    @Bindable var quote: SpiritualQuote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(quote.text).font(.subheadline)
                Text(quote.source).font(.caption.weight(.bold)).foregroundStyle(Theme.gold)
            }
            Spacer()
            Button {
                quote.isFavorite.toggle()
            } label: {
                Image(systemName: quote.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(Theme.gold)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

private struct QuoteEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var source = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Quote, verse or reflection", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Source (e.g. Psalm 23:1)", text: $source)
            }
            .themedList()
            .navigationTitle("New Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(SpiritualQuote(text: text.trimmingCharacters(in: .whitespacesAndNewlines), source: source))
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
