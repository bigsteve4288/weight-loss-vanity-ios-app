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
}
