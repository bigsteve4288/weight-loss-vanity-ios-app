import SwiftData
import SwiftUI

struct MindsetView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(UserNotificationManager.self) private var notifications

    @Query private var profiles: [GoalProfile]
    @Query(sort: \SpiritualQuote.createdAt, order: .reverse) private var quotes: [SpiritualQuote]
    @Query(filter: #Predicate<ProgressPhoto> { $0.isBaseline == true }) private var baselines: [ProgressPhoto]

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
        await notifications.reschedule(
            profile: profiles.first,
            currentWeight: health.latestWeightLbs,
            quotes: quotes,
            baselineImageData: baselines.first?.imageData
        )
    }

    private func sendTest(_ profile: GoalProfile) {
        Task {
            await notifications.sendTestNotification(
                profile: profile,
                currentWeight: health.latestWeightLbs,
                quotes: quotes,
                baselineImageData: baselines.first?.imageData
            )
        }
    }
}

private struct NotificationSettingsSection: View {
    @Bindable var profile: GoalProfile
    let reschedule: () async -> Void
    let sendTest: () -> Void
    @Environment(UserNotificationManager.self) private var notifications

    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: profile.notificationHour, minute: profile.notificationMinute, second: 0, of: .now) ?? .now
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            profile.notificationHour = components.hour ?? 7
            profile.notificationMinute = components.minute ?? 0
        }
    }

    private var enabled: Binding<Bool> {
        Binding {
            profile.notificationsEnabled
        } set: { isOn in
            Task {
                profile.notificationsEnabled = isOn ? await notifications.requestAuthorization() : false
                await reschedule()
            }
        }
    }

    var body: some View {
        Section {
            Toggle("Daily Accountability", isOn: enabled)
            if profile.notificationsEnabled {
                DatePicker("Delivery Time", selection: time, displayedComponents: .hourAndMinute)
                LabeledContent("Scheduled", value: "\(notifications.scheduledCount) days ahead")
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
            Text("Lock-Screen Notifications")
        } footer: {
            Text("Each notification carries your live countdown, a quote and your baseline photo. Lock your phone after tapping Test to see it.")
        }
        .onChange(of: profile.notificationHour) { Task { await reschedule() } }
        .onChange(of: profile.notificationMinute) { Task { await reschedule() } }
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
