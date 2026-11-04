import SwiftData
import SwiftUI

/// One check-in as the user will get it on a given day.
struct CheckInEntry: Identifiable {
    let slot: ReminderSlot
    let time: Date
    let title: String
    let body: String
    let isFromCoach: Bool

    var id: Date { time }

    /// Today's and tomorrow's check-ins, worded exactly as the notifications are.
    @MainActor
    static func schedule(
        profile: GoalProfile,
        notes: [CoachNote],
        quotes: [SpiritualQuote],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(day: Date, entries: [CheckInEntry])] {
        let today = calendar.startOfDay(for: now)
        let latest = UserNotificationManager.latestNotes(notes)
        let quoteList = quotes.map { (text: $0.text, source: $0.source) }
        let slots = ReminderSlot.enabled(for: profile)
        return (0...1).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let entries = slots.enumerated().map { slotIndex, entry in
                let message = UserNotificationManager.message(
                    slot: entry.slot, slotIndex: slotIndex, day: day, notes: latest, profile: profile, quotes: quoteList, calendar: calendar
                )
                return CheckInEntry(
                    slot: entry.slot,
                    time: entry.minutes.asTime(on: day, calendar: calendar),
                    title: message.title,
                    body: message.body,
                    isFromCoach: message.isFromCoach
                )
            }
            return (day, entries)
        }
    }
}

/// Every check-in for today and tomorrow, so a notification can be re-read after it's gone.
struct CheckInsView: View {
    @Query private var profiles: [GoalProfile]
    @Query private var notes: [CoachNote]
    @Query(sort: \SpiritualQuote.createdAt) private var quotes: [SpiritualQuote]

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            List {
                if let profile = profiles.first {
                    let schedule = CheckInEntry.schedule(profile: profile, notes: notes, quotes: quotes, now: timeline.date)
                    let next = schedule.flatMap(\.entries).first { $0.time > timeline.date }
                    ForEach(schedule, id: \.day) { day in
                        Section(Calendar.current.isDateInToday(day.day) ? "Today" : "Tomorrow") {
                            if day.entries.isEmpty {
                                Text("All check-ins are turned off.").foregroundStyle(.secondary)
                            }
                            ForEach(day.entries) { entry in
                                CheckInRow(entry: entry, isPast: entry.time <= timeline.date, isNext: entry.id == next?.id)
                            }
                        }
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Check-ins")
    }
}

struct CheckInRow: View {
    let entry: CheckInEntry
    var isPast = false
    var isNext = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: entry.slot.systemImage).foregroundStyle(Theme.gold)
                Text(entry.time, format: .dateTime.hour().minute()).font(.subheadline.weight(.semibold))
                Text(entry.slot.label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if isNext {
                    Text("NEXT").font(.caption2.weight(.heavy)).foregroundStyle(Theme.black)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.gold, in: Capsule())
                } else if isPast {
                    Text("SENT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            Text(entry.title).font(.headline)
            Text(entry.body).font(.subheadline)
            if !entry.isFromCoach {
                Text("Built-in message").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(isPast ? 0.55 : 1)
    }
}
