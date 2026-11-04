import Foundation
import SwiftData

/// One AI-written check-in for a specific day and reminder slot.
@Model
final class CoachNote {
    /// Start of the day this note is for.
    var day: Date
    var slotRaw: String
    var category: String
    var title: String
    var body: String
    var createdAt: Date

    init(day: Date, slot: ReminderSlot, category: String, title: String, body: String, createdAt: Date = .now) {
        self.day = day
        self.slotRaw = slot.rawValue
        self.category = category
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }

    var slot: ReminderSlot? { ReminderSlot(rawValue: slotRaw) }
}
