import Foundation
import Observation
import SwiftData
import UserNotifications

/// Schedules the day's coach check-ins on the Lock Screen. Local notifications can't change their
/// content once scheduled, so the next week is scheduled as individual notifications and rebuilt
/// whenever the app becomes active or the coach writes new messages.
@MainActor
@Observable
final class UserNotificationManager {
    private(set) var isAuthorized = false
    private(set) var scheduledCount = 0
    private(set) var isDenied = false
    private(set) var testStatus: String?

    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    static let daysAhead = 7
    private static let prefix = "goaltracker.checkin."
    private static let legacyPrefix = "goaltracker.daily."

    func refreshAuthorizationStatus() async {
        let status = await center.notificationSettings().authorizationStatus
        isAuthorized = status == .authorized || status == .provisional
        isDenied = status == .denied
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorizationStatus()
        return isAuthorized
    }

    func reschedule(context: ModelContext, currentWeight: Double?, now: Date = .now) async {
        let stale = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(Self.prefix) || $0.hasPrefix(Self.legacyPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        scheduledCount = 0
        guard let profile = try? context.fetch(FetchDescriptor<GoalProfile>()).first, profile.notificationsEnabled else { return }
        await refreshAuthorizationStatus()
        guard isAuthorized else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let quotes = Self.quotes(in: context)
        let notes = Self.notesBySlot(in: context, from: today)
        let poundsLeft = currentWeight.map { max($0 - profile.targetWeightLbs, 0) }
        let slots = ReminderSlot.enabled(for: profile)

        days: for offset in 0..<Self.daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for (slotIndex, entry) in slots.enumerated() {
                let fireDate = entry.minutes.asTime(on: day, calendar: calendar)
                guard fireDate > now else { continue }
                let daysLeft = TargetEngine.daysRemaining(from: fireDate, to: profile.targetDate, calendar: calendar)
                guard daysLeft >= 0 else { break days }

                let content = makeContent(
                    slot: entry.slot,
                    note: notes[Self.key(day, entry.slot)],
                    profile: profile,
                    countdown: NotificationContent.countdown(daysLeft: daysLeft, poundsLeft: poundsLeft),
                    index: (calendar.ordinality(of: .day, in: .era, for: day) ?? offset) + slotIndex,
                    quotes: quotes
                )
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let request = UNNotificationRequest(
                    identifier: Self.prefix + "\(offset).\(entry.slot.rawValue)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
                if (try? await center.add(request)) != nil {
                    scheduledCount += 1
                }
            }
        }
    }

    /// Sends the next check-in the user would get, so they can preview the coach's voice.
    func sendTestNotification(context: ModelContext, currentWeight: Double?, now: Date = .now) async {
        guard await requestAuthorization() else {
            testStatus = "Notifications are turned off for Vanity. Turn them on in Settings to receive them."
            return
        }
        guard let profile = try? context.fetch(FetchDescriptor<GoalProfile>()).first else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let notes = Self.notesBySlot(in: context, from: today)
        let slots = ReminderSlot.enabled(for: profile)
        let upcoming = slots.first { $0.minutes.asTime(on: today, calendar: calendar) > now } ?? slots.first
        let slot = upcoming?.slot ?? .wake
        let note = upcoming.flatMap { entry in
            notes[Self.key(today, entry.slot)] ?? notes[Self.key(calendar.date(byAdding: .day, value: 1, to: today) ?? today, entry.slot)]
        }

        let content = makeContent(
            slot: slot,
            note: note,
            profile: profile,
            countdown: NotificationContent.countdown(
                daysLeft: TargetEngine.daysRemaining(from: now, to: profile.targetDate),
                poundsLeft: currentWeight.map { max($0 - profile.targetWeightLbs, 0) }
            ),
            index: Int.random(in: 0..<100),
            quotes: Self.quotes(in: context)
        )
        let request = UNNotificationRequest(
            identifier: "goaltracker.test",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        do {
            try await center.add(request)
            testStatus = "Sent your \(slot.label) check-in. It arrives in 5 seconds; lock your phone to see it on the Lock Screen."
        } catch {
            testStatus = "Couldn't schedule the test: \(error.localizedDescription)"
        }
    }

    private func makeContent(
        slot: ReminderSlot,
        note: CoachNote?,
        profile: GoalProfile,
        countdown: String,
        index: Int,
        quotes: [(text: String, source: String)]
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = note?.title ?? slot.label
        content.subtitle = countdown
        content.body = note?.body ?? NotificationContent.body(
            slot: slot,
            skipsBreakfast: profile.breakfastMinutes == nil,
            quote: quotes.isEmpty ? nil : quotes[index % quotes.count],
            index: index
        )
        content.sound = .default
        content.threadIdentifier = "vanity.checkins"
        return content
    }

    private static func key(_ day: Date, _ slot: ReminderSlot) -> String {
        "\(Int(day.timeIntervalSinceReferenceDate)).\(slot.rawValue)"
    }

    private static func notesBySlot(in context: ModelContext, from today: Date) -> [String: CoachNote] {
        let notes = (try? context.fetch(FetchDescriptor<CoachNote>(predicate: #Predicate { $0.day >= today }))) ?? []
        var bySlot: [String: CoachNote] = [:]
        for note in notes {
            guard let slot = note.slot else { continue }
            let key = key(note.day, slot)
            if let existing = bySlot[key], existing.createdAt > note.createdAt { continue }
            bySlot[key] = note
        }
        return bySlot
    }

    private static func quotes(in context: ModelContext) -> [(text: String, source: String)] {
        ((try? context.fetch(FetchDescriptor<SpiritualQuote>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
            .map { (text: $0.text, source: $0.source) }
    }
}
