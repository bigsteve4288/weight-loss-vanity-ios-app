import Foundation
import Testing
@testable import GoalTracker

struct ReminderSlotTests {
    private let day = DailyRhythm(wake: 330, breakfast: 450, lunch: 720, dinner: 1110, bed: 1320)

    @Test func timesFollowTheUsersDay() {
        #expect(ReminderSlot.wake.derivedMinutes(for: day) == 330)            // 5:30
        #expect(ReminderSlot.beforeBreakfast.derivedMinutes(for: day) == 435) // 7:15
        #expect(ReminderSlot.midMorning.derivedMinutes(for: day) == 585)      // 9:45
        #expect(ReminderSlot.beforeLunch.derivedMinutes(for: day) == 705)     // 11:45
        #expect(ReminderSlot.afternoon.derivedMinutes(for: day) == 915)       // 3:15
        #expect(ReminderSlot.evening.derivedMinutes(for: day) == 1230)        // 8:30
    }

    @Test func skippingBreakfastKeepsMorningCheckIns() {
        var fasting = day
        fasting.breakfast = nil
        #expect(ReminderSlot.beforeBreakfast.derivedMinutes(for: fasting) == 420)
        #expect(ReminderSlot.midMorning.derivedMinutes(for: fasting) == 525)
        #expect(fasting.isInOrder)
    }

    @Test func bedtimeAfterMidnightStillMeansTonight() {
        var lateNight = day
        lateNight.bed = 30 // 12:30 AM
        #expect(ReminderSlot.evening.derivedMinutes(for: lateNight) == 1380) // 11:00 PM
        lateNight.bed = 1410 // 11:30 PM
        #expect(ReminderSlot.evening.derivedMinutes(for: lateNight) == 1320)
    }

    @Test func mealsOutOfOrderAreRejected() {
        var backwards = day
        backwards.lunch = 1200
        #expect(!backwards.isInOrder)
    }
}

struct CoachNotesTests {
    private let slots: [(slot: ReminderSlot, minutes: Int)] = [(.wake, 330), (.beforeLunch, 705), (.evening, 1230)]

    @Test func writesRestOfTodayAndAllOfTomorrow() {
        let requests = CoachNotesManager.requests(slots: slots, nowMinutes: 600)
        #expect(requests == [
            NoteRequest(dayOffset: 0, slot: .beforeLunch, minutes: 705),
            NoteRequest(dayOffset: 0, slot: .evening, minutes: 1230),
            NoteRequest(dayOffset: 1, slot: .wake, minutes: 330),
            NoteRequest(dayOffset: 1, slot: .beforeLunch, minutes: 705),
            NoteRequest(dayOffset: 1, slot: .evening, minutes: 1230),
        ])
    }

    @Test func requestUsesSonnetAndListsEachCheckIn() throws {
        let requests = CoachNotesManager.requests(slots: slots, nowMinutes: 600)
        let body = CoachService.notesRequestBody(
            for: requests, context: "CLIENT DATA", tone: .blunt, skipsBreakfast: false, recentlyUsed: ["scripture: Old"]
        )
        #expect(body["model"] as? String == "claude-sonnet-5-5")
        let message = try #require((body["messages"] as? [[String: Any]])?.first?["content"] as? String)
        #expect(message.contains("dayOffset 0"))
        #expect(message.contains("slot evening"))
        #expect(message.contains("scripture: Old"))
        let system = try #require(body["system"] as? String)
        #expect(system.contains("Philippians 4:13"))
    }

    @Test func decodesWrittenNotes() throws {
        let notes = #"{"messages":[{"dayOffset":1,"slot":"wake","category":"scripture","title":"Up and at it","body":"Move."}]}"#
        let escaped = try String(data: JSONEncoder().encode(notes), encoding: .utf8)!
        let response = Data(#"{"content":[{"type":"text","text":\#(escaped)}],"stop_reason":"end_turn"}"#.utf8)
        struct Batch: Decodable { let messages: [CoachNoteDraft] }
        let batch = try CoachService.decodeOutput(Batch.self, from: response)
        #expect(batch.messages == [CoachNoteDraft(dayOffset: 1, slot: .wake, category: "scripture", title: "Up and at it", body: "Move.")])
    }
}
