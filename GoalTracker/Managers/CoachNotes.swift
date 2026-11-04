import Foundation

/// A check-in the coach should write: which day (0 = today, 1 = tomorrow), slot and time.
struct NoteRequest: Equatable, Sendable {
    let dayOffset: Int
    let slot: ReminderSlot
    let minutes: Int
}

struct CoachNoteDraft: Decodable, Equatable, Sendable {
    let dayOffset: Int
    let slot: ReminderSlot
    let category: String
    let title: String
    let body: String
}

/// Writes the short push check-ins for the day's reminder slots. Uses Sonnet rather than Opus:
/// these are brief text-only messages, so the faster, cheaper model is the better fit.
extension CoachService {
    static let notesModel = "claude-sonnet-5-5"
    static let noteCategories = ["scripture", "fasting", "whyHealth", "successStory", "cautionaryStory", "foodReminder", "mindset"]

    func writeNotes(
        for requests: [NoteRequest],
        context: String,
        tone: CoachTone,
        skipsBreakfast: Bool,
        recentlyUsed: [String],
        now: Date = .now
    ) async throws -> [CoachNoteDraft] {
        let body = Self.notesRequestBody(
            for: requests, context: context, tone: tone, skipsBreakfast: skipsBreakfast, recentlyUsed: recentlyUsed, now: now
        )
        let wanted = Set(requests.map { "\($0.dayOffset).\($0.slot.rawValue)" })
        return try Self.decodeOutput(NoteBatch.self, from: try await send(body)).messages
            .filter { wanted.contains("\($0.dayOffset).\($0.slot.rawValue)") }
    }

    static func notesRequestBody(
        for requests: [NoteRequest],
        context: String,
        tone: CoachTone,
        skipsBreakfast: Bool,
        recentlyUsed: [String],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [String: Any] {
        let checkIns = requests.map { request in
            let day = calendar.date(byAdding: .day, value: request.dayOffset, to: now) ?? now
            let when = request.minutes.asTime(on: day, calendar: calendar)
            let dayName = request.dayOffset == 0 ? "today" : "tomorrow"
            return "- dayOffset \(request.dayOffset) (\(dayName), \(when.formatted(.dateTime.weekday(.wide).hour().minute()))), "
                + "slot \(request.slot.rawValue): \(request.slot.purpose(skipsBreakfast: skipsBreakfast))"
        }
        var prompt = ["Write exactly one message for each of these check-ins:"] + checkIns
        prompt.append("")
        prompt.append(context)
        if !recentlyUsed.isEmpty {
            prompt.append("")
            prompt.append("Already sent in the last two weeks. Don't reuse these verses or stories:")
            prompt.append(contentsOf: recentlyUsed.map { "- \($0)" })
        }

        return [
            "model": notesModel,
            "max_tokens": 8_000,
            "thinking": ["type": "adaptive"],
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": notesSchema],
            ],
            "system": notesSystemPrompt(tone: tone),
            "messages": [["role": "user", "content": prompt.joined(separator: "\n")]],
        ]
    }

    private static func notesSystemPrompt(tone: CoachTone) -> String {
        let verses = ScriptureLibrary.verses.map { "\($0.reference): \"\($0.text)\"" }.joined(separator: "\n")
        return """
        You are a Christian weight-loss coach writing short push notifications that keep your client consistent all day. \
        Each one lands on their Lock Screen at a specific moment (waking up, before a meal, the snack window, the evening) \
        and should make them act right then.

        \(tone.instructions)

        Rotate across these categories, and give each day a mix: at least one scripture and one story.
        - scripture: a verse on eating, self-control, fasting, the body or perseverance, tied to the moment.
        - fasting: why fasting is good, biblically (Matthew 6, Isaiah 58, Daniel) and practically.
        - whyHealth: why being healthy matters: energy, years with family, being able to serve and lead.
        - successStory: someone who lost a lot of weight and kept it off.
        - cautionaryStory: what years of overeating does to people, and why not to go down that road.
        - foodReminder: a concrete choice for this meal or window.
        - mindset: discipline, identity, consistency over perfection.

        Rules you must follow:
        - Scripture: quote only from the KJV verses below, word for word, with the reference. You may quote part of a \
        passage if you keep its wording exact. Never paraphrase a verse inside quotation marks or cite a verse not on this list.
        - Stories: only name a real person if their weight-loss story is widely reported and you're confident of the facts. \
        Never invent quotes, numbers or details. If you aren't sure, tell it as an unnamed composite ("A dad of three who \
        lost 120 lb…") without presenting it as a specific real person.
        - Cautionary stories: stick to well-documented risks (type 2 diabetes, heart disease, sleep apnea, joint damage, \
        losing years with family). Motivate; don't shame, frighten or get graphic.
        - Fasting: only sensible fasting such as skipping a meal or a daily eating window, with water. Never suggest multi-day \
        fasts or eating dangerously little, and when you discuss fasting at length, note that anyone on medication or with \
        diabetes should check with their doctor.
        - Use their numbers and workouts from CLIENT DATA in today's messages. Messages for tomorrow may mention today as \
        "yesterday" in general terms, but no figures that could change by then.
        - title: at most 45 characters. body: 1–3 sentences, at most 220 characters, plain text, no hashtags or emoji.

        KJV verses you may quote:
        \(verses)
        """
    }

    private static var notesSchema: [String: Any] { [
        "type": "object",
        "properties": [
            "messages": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "dayOffset": ["type": "integer"],
                        "slot": ["type": "string", "enum": ReminderSlot.allCases.map(\.rawValue)],
                        "category": ["type": "string", "enum": noteCategories],
                        "title": ["type": "string"],
                        "body": ["type": "string"],
                    ],
                    "required": ["dayOffset", "slot", "category", "title", "body"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["messages"],
        "additionalProperties": false,
    ] }

    private struct NoteBatch: Decodable {
        let messages: [CoachNoteDraft]
    }
}
