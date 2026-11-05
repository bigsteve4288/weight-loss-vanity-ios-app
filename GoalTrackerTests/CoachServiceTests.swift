import Foundation
import Testing
@testable import GoalTracker

struct CoachServiceTests {
    private let verdictJSON = #"{"grade":"D","headline":"That gut didn't build itself.","observations":["Midsection is softer"],"progressSinceThen":"About 30 lb away.","focusAreas":["Protein"],"ordersForToday":["Walk","Water","Log food"]}"#

    private func response(_ blocks: String, stopReason: String = "end_turn", stopDetails: String = "null") -> Data {
        Data(#"{"content":[\#(blocks)],"stop_reason":"\#(stopReason)","stop_details":\#(stopDetails)}"#.utf8)
    }

    private func textBlock(_ text: String) -> String {
        let escaped = String(data: try! JSONEncoder().encode(text), encoding: .utf8)!
        return #"{"type":"text","text":\#(escaped)}"#
    }

    @Test func parsesVerdictAndSkipsThinking() throws {
        let data = response(#"{"type":"thinking","thinking":""},"# + textBlock(verdictJSON))
        let verdict = try CoachService.parseVerdict(from: data)
        #expect(verdict.grade == "D")
        #expect(verdict.ordersForToday.count == 3)
    }

    @Test func usesTextAfterLastFallbackBoundary() throws {
        let data = response(textBlock("{\"partial") + #",{"type":"fallback"},"# + textBlock(verdictJSON))
        #expect(try CoachService.parseVerdict(from: data).headline == "That gut didn't build itself.")
    }

    @Test func surfacesRefusal() {
        let data = response("", stopReason: "refusal", stopDetails: #"{"type":"refusal","category":null,"explanation":"Nope."}"#)
        #expect(throws: CoachError.refused("Nope.")) { try CoachService.parseVerdict(from: data) }
    }

    @Test func surfacesTruncation() {
        #expect(throws: CoachError.truncated) { try CoachService.parseVerdict(from: response(textBlock("{"), stopReason: "max_tokens")) }
    }

    @Test func requestBodyCarriesBothImagesInOrder() throws {
        let photo = CoachPhoto(jpeg: Data([0xFF, 0xD8]), date: .now, weightLbs: 200)
        let body = CoachService.requestBody(then: photo, now: photo, context: "CLIENT DATA", tone: .drillSergeant)
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["fallbacks"] as? String == "default")
        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == ["text", "image", "text", "image", "text"])
        #expect(JSONSerialization.isValidJSONObject(body))
    }

    @Test func savedCredentialPicksDirectKeyOrProxyCode() {
        #expect(CoachService.Credential("sk-ant-abc") == .apiKey("sk-ant-abc"))
        #expect(CoachService.Credential("tiger-42") == .accessCode("tiger-42"))
    }
}

struct CoachSafetyTests {
    @Test(arguments: CoachTone.allCases)
    func everyToneCarriesTheSameSafetyRules(tone: CoachTone) throws {
        let photo = CoachPhoto(jpeg: Data([0xFF, 0xD8]), date: .now, weightLbs: 200)
        let verdict = try #require(CoachService.requestBody(then: photo, now: photo, context: "CLIENT DATA", tone: tone)["system"] as? String)
        let notes = try #require(CoachService.notesRequestBody(
            for: [NoteRequest(dayOffset: 1, slot: .wake, minutes: 330)], context: "CLIENT DATA", tone: tone,
            skipsBreakfast: false, recentlyUsed: []
        )["system"] as? String)
        #expect(verdict.contains(CoachSafety.rules))
        #expect(notes.contains(CoachSafety.rules))
    }

    @Test func drillSergeantChallengesHabitsNotBodies() {
        let instructions = CoachTone.drillSergeant.instructions
        #expect(!instructions.localizedCaseInsensitiveContains("gut"))
        #expect(!instructions.localizedCaseInsensitiveContains("roast"))
        #expect(instructions.contains("never at their body"))
    }

    private func snapshot(current: Double, deadline: Date, consumed: Double, now: Date) -> TargetSnapshot {
        TargetEngine.snapshot(.init(
            startWeight: 334.7, lossGoal: 34, targetDate: deadline, currentWeight: current, latestWeightDate: now,
            history: [], nutrition: Fixture.log(calories: consumed, protein: 7, entries: [now.addingTimeInterval(-1800)]),
            activeBurn: 80, basalBurn: 700, restingCaloriesPerDay: 2200, rhythm: Fixture.rhythm,
            now: now, calendar: Fixture.calendar
        ))
    }

    @Test func coachSeesTheSustainablePlanNotTheDeadlineDeficit() {
        let now = Fixture.date(2026, 11, 5, hour: 9)
        let snapshot = snapshot(current: 330, deadline: Fixture.date(2026, 12, 14), consumed: 190, now: now)
        let lines = CoachViewModel.planLines(snapshot.plan).joined(separator: "\n")
        #expect(lines.contains("context only, not an instruction"))
        #expect(lines.contains("Don't push a bigger deficit"))
        #expect(lines.contains("Sustainable plan to coach toward: 2.0 lb/week"))
        #expect(!lines.contains("2,629"))
        #expect(!lines.contains("2629"))
    }

    @Test func coachIsToldAMorningLogIsPartial() {
        let now = Fixture.date(2026, 11, 5, hour: 9)
        let snapshot = snapshot(current: 330, deadline: Fixture.date(2027, 6, 1), consumed: 190, now: now)
        let lines = CoachViewModel.todayLines(snapshot, nutrition: Fixture.log(calories: 190, protein: 7, entries: [now]), now: now)
            .joined(separator: "\n")
        #expect(lines.contains("This is a partial day"))
        #expect(lines.contains("IN PROGRESS"))
        #expect(!lines.contains("Today's estimated deficit"))
    }
}
