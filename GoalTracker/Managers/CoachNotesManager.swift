import BackgroundTasks
import Foundation
import Observation
import SwiftData

/// Keeps the coach's check-ins fresh: writes the rest of today and all of tomorrow, and rewrites
/// them once they're more than `refreshInterval` old so they reflect the latest numbers.
@MainActor
@Observable
final class CoachNotesManager {
    private(set) var isWriting = false
    private(set) var lastError: String?

    static let refreshInterval: TimeInterval = 12 * 3600
    static let backgroundTaskID = "com.bigsteve4288.goaltracker.coach-notes"
    private static let rememberedCategories: Set<String> = ["scripture", "successStory", "cautionaryStory"]

    /// Writes new check-ins if they're missing or stale. Returns `true` when new ones were saved.
    @discardableResult
    func refreshIfNeeded(context: ModelContext, health: HealthKitManager, force: Bool = false, now: Date = .now) async -> Bool {
        guard !isWriting,
              let profile = try? context.fetch(FetchDescriptor<GoalProfile>()).first,
              profile.notificationsEnabled,
              let saved = KeychainStore.read(KeychainStore.anthropicAPIKey)
        else { return false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today) else { return false }
        let notes = (try? context.fetch(FetchDescriptor<CoachNote>())) ?? []

        if !force, notes.contains(where: { $0.day == tomorrow }),
           let newest = notes.map(\.createdAt).max(), now.timeIntervalSince(newest) < Self.refreshInterval {
            return false
        }
        let requests = Self.requests(slots: ReminderSlot.enabled(for: profile), nowMinutes: now.minutesAfterMidnight)
        guard !requests.isEmpty else { return false }

        isWriting = true
        lastError = nil
        defer { isWriting = false }

        let tone = UserDefaults.standard.string(forKey: "coachTone").flatMap(CoachTone.init) ?? .supportive
        var latestCritique = FetchDescriptor<CoachCritique>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        latestCritique.fetchLimit = 1
        let summary = CoachViewModel.clientContext(
            profile: profile, health: health, previous: try? context.fetch(latestCritique).first,
            includeHealthHistory: false, // check-ins land on the Lock Screen
            now: now
        )
        let recentlyUsed = notes
            .filter { $0.day >= twoWeeksAgo && Self.rememberedCategories.contains($0.category) }
            .sorted { $0.day > $1.day }
            .prefix(30)
            .map { "\($0.category): \($0.title) — \($0.body.prefix(100))" }

        do {
            let drafts = try await CoachService(credential: .init(saved)).writeNotes(
                for: requests,
                context: summary,
                tone: tone,
                skipsBreakfast: profile.breakfastMinutes == nil,
                recentlyUsed: Array(recentlyUsed),
                now: now
            )
            for draft in drafts {
                guard let day = calendar.date(byAdding: .day, value: draft.dayOffset, to: today) else { continue }
                notes.filter { $0.day == day && $0.slotRaw == draft.slot.rawValue }.forEach(context.delete)
                context.insert(CoachNote(day: day, slot: draft.slot, category: draft.category, title: draft.title, body: draft.body, createdAt: now))
            }
            notes.filter { $0.day < twoWeeksAgo }.forEach(context.delete)
            try? context.save()
            return !drafts.isEmpty
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// The check-ins still ahead today, plus every enabled one tomorrow.
    nonisolated static func requests(slots: [(slot: ReminderSlot, minutes: Int)], nowMinutes: Int) -> [NoteRequest] {
        let today = slots.filter { $0.minutes > nowMinutes }.map { NoteRequest(dayOffset: 0, slot: $0.slot, minutes: $0.minutes) }
        let tomorrow = slots.map { NoteRequest(dayOffset: 1, slot: $0.slot, minutes: $0.minutes) }
        return today + tomorrow
    }

    /// Asks iOS to wake the app overnight so tomorrow's check-ins are written even if it isn't opened.
    static func scheduleBackgroundRefresh(now: Date = .now) {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        let calendar = Calendar.current
        let threeAM = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: now) ?? now
        request.earliestBeginDate = threeAM > now ? threeAM : calendar.date(byAdding: .day, value: 1, to: threeAM)
        try? BGTaskScheduler.shared.submit(request)
    }
}
