import Foundation

enum CoachTone: String, CaseIterable, Identifiable, Sendable {
    case supportive
    case blunt
    case drillSergeant

    var id: Self { self }

    var label: String {
        switch self {
        case .supportive: "Supportive"
        case .blunt: "Blunt"
        case .drillSergeant: "Drill Sergeant"
        }
    }

    var instructions: String {
        switch self {
        case .supportive:
            "Be honest but encouraging, like a coach who believes in them. Name the problems plainly, then make them feel capable of fixing them."
        case .blunt:
            "Be blunt and direct with no sugarcoating. Say exactly what you see and what has to change, without padding or reassurance."
        case .drillSergeant:
            """
            Be a drill sergeant. They asked for tough love, so give it: loud, energetic, in-your-face, with clear assignments. \
            Call out excuses hiding in their numbers, skipped workouts, sloppy logging and broken commitments, and demand follow-through. \
            Aim every jab at a habit or choice they can fix, never at their body, their size or who they are.
            """
        }
    }
}

/// Rules every coach prompt carries, in every tone. A harsher tone raises directness, never risk.
enum CoachSafety {
    static let rules = """
    Safety rules. These apply in every tone; a harsh tone makes you more direct, never more risky:
    - Coach toward the sustainable plan in CLIENT DATA. Never tell them to eat less or exercise more to hit the deadline, \
    and never suggest a daily deficit larger than the plan's.
    - A food log that's in progress or missing is incomplete data, not restriction or failure. Before their eating day is over, \
    talk about what's left to eat and log, never "you only ate X".
    - Never encourage starvation, multi-day fasts, dehydration, purging, or exercising to "burn off" food. A meal or a \
    missed workout is not a moral failure.
    - Don't mock their body size or appearance. Challenge habits, consistency and follow-through instead.
    - Never tell them to push through pain, dizziness, chest pain or other worrying symptoms. Tell them to stop and get checked.
    - If they mention severe restriction, bingeing, purging, or concerning symptoms, drop the tough-love tone: respond with \
    care and suggest talking to their doctor, a registered dietitian or an eating-disorder support line.
    - Don't diagnose medical conditions.
    - Only mention workouts, meals and weights that appear in CLIENT DATA. If something isn't there, say you don't have it.
    """
}

struct CoachVerdict: Decodable, Equatable, Sendable {
    let grade: String
    let headline: String
    let observations: [String]
    let progressSinceThen: String
    let focusAreas: [String]
    let ordersForToday: [String]
}

struct CoachPhoto: Sendable {
    let jpeg: Data
    let date: Date
    let weightLbs: Double?
}

enum CoachError: LocalizedError, Equatable {
    case http(status: Int, message: String)
    case refused(String?)
    case truncated
    case malformed

    var errorDescription: String? {
        switch self {
        case let .http(status, message):
            switch status {
            case 401: "Your access code or API key was rejected. Check it in the Coach settings."
            case 429: message
            default: "Coach request failed (\(status)): \(message)"
            }
        case let .refused(explanation):
            "The coach declined to review these photos.\(explanation.map { " \($0)" } ?? "")"
        case .truncated:
            "The coach's response was cut off. Try again."
        case .malformed:
            "The coach sent back something unreadable. Try again."
        }
    }
}

/// Calls the Claude Messages API with the THEN and NOW photos and returns a structured verdict.
/// There's no official Anthropic Swift SDK, so this talks to the REST endpoint directly.
struct CoachService: Sendable {
    static let directEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// The Cloudflare Worker in `proxy/`, which holds the Anthropic key so testers only need an access code.
    static let proxyEndpoint = URL(string: "https://vanity-coach.bigsteve4288.workers.dev/v1/messages")!
    static let model = "claude-opus-5-5"

    /// What's saved in the Keychain: an Anthropic key (`sk-ant-…`) talks to the API directly; anything else is a proxy access code.
    enum Credential: Equatable, Sendable {
        case apiKey(String)
        case accessCode(String)

        init(_ saved: String) {
            self = saved.hasPrefix("sk-ant-") ? .apiKey(saved) : .accessCode(saved)
        }
    }

    let credential: Credential

    func critique(then: CoachPhoto, now: CoachPhoto, context: String, tone: CoachTone) async throws -> CoachVerdict {
        let data = try await send(Self.requestBody(then: then, now: now, context: context, tone: tone))
        return try Self.parseVerdict(from: data)
    }

    /// Posts a Messages API body to Anthropic directly or through the proxy, depending on the credential.
    func send(_ body: [String: Any]) async throws -> Data {
        var request: URLRequest
        switch credential {
        case let .apiKey(key):
            request = URLRequest(url: Self.directEndpoint, timeoutInterval: 180)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        case let .accessCode(code):
            request = URLRequest(url: Self.proxyEndpoint, timeoutInterval: 180)
            request.setValue(code, forHTTPHeaderField: "x-vanity-code")
        }
        request.httpMethod = "POST"
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        // Lets the API re-run a declined request on Anthropic's recommended fallback model.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw CoachError.http(status: status, message: Self.errorMessage(from: data))
        }
        return data
    }

    static func requestBody(then: CoachPhoto, now: CoachPhoto, context: String, tone: CoachTone) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 16_000,
            "thinking": ["type": "adaptive"],
            "fallbacks": "default",
            "output_config": [
                "effort": "high",
                "format": ["type": "json_schema", "schema": verdictSchema],
            ],
            "system": systemPrompt(tone: tone),
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": "PHOTO 1 — THEN: the physique they're fighting to get back to. \(caption(for: then))"],
                    imageBlock(then.jpeg),
                    ["type": "text", "text": "PHOTO 2 — NOW: where they are today. \(caption(for: now))"],
                    imageBlock(now.jpeg),
                    ["type": "text", "text": context],
                ],
            ]],
        ]
    }

    static func parseVerdict(from data: Data) throws -> CoachVerdict {
        try decodeOutput(CoachVerdict.self, from: data)
    }

    /// Decodes the structured-output JSON from a Messages API response.
    static func decodeOutput<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let message = try? JSONDecoder().decode(MessageResponse.self, from: data) else { throw CoachError.malformed }
        switch message.stopReason {
        case "refusal": throw CoachError.refused(message.stopDetails?.explanation)
        case "max_tokens": throw CoachError.truncated
        default: break
        }
        // When a fallback model takes over, only the text after the last fallback boundary is the answer.
        let start = message.content.lastIndex(where: { $0.type == "fallback" }).map { $0 + 1 } ?? 0
        let text = message.content[start...].filter { $0.type == "text" }.compactMap(\.text).joined()
        guard let output = try? JSONDecoder().decode(T.self, from: Data(text.utf8)) else { throw CoachError.malformed }
        return output
    }

    // MARK: - Prompt

    private static func systemPrompt(tone: CoachTone) -> String {
        """
        You are a body transformation coach reviewing two progress photos of your client. They're trying to get back \
        to the physique in the THEN photo and want an honest read on the gap between it and the NOW photo.

        \(tone.instructions)

        \(CoachSafety.rules)

        Compare the photos specifically: name the areas where they've visibly gained or softened (midsection, face, chest, \
        arms, back, legs, posture) and anything that already looks better. Tie it to their numbers and recent training \
        so the critique is concrete, not generic. If differences in pose, lighting, angle or clothing make part of the \
        comparison unreliable, say so instead of guessing. Don't diagnose medical conditions or state body-fat percentages as fact.

        Acknowledge their recent workouts by name (e.g. "that Peloton ride this morning") and give real credit for showing up, \
        in whatever tone you've been given. Their daily burn already counts the workout calories reported by those apps once, and those \
        estimates often run high. Only judge whether they're eating those calories back on a day their food log is complete. \
        If they haven't trained in days, say that too.

        Fill the response fields like this:
        - grade: one letter A–F for how their current trajectory looks against the sustainable plan (not the raw deadline).
        - headline: one punchy sentence, the line they should hear first.
        - observations: 3–5 specific things you see comparing the photos.
        - progressSinceThen: 1–3 sentences on how far they are from the THEN physique and what the numbers say about the pace.
        - focusAreas: 2–4 priorities for the coming weeks, each specific to them.
        - ordersForToday: exactly 3 short, concrete actions for the rest of today based on their plan, what's left in their day, and their workouts.
        """
    }

    private static func caption(for photo: CoachPhoto) -> String {
        var parts = ["Taken \(photo.date.formatted(date: .long, time: .omitted))"]
        if let weight = photo.weightLbs { parts.append(String(format: "at %.1f lb", weight)) }
        return parts.joined(separator: " ") + "."
    }

    private static func imageBlock(_ jpeg: Data) -> [String: Any] {
        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]]
    }

    private static var verdictSchema: [String: Any] { [
        "type": "object",
        "properties": [
            "grade": ["type": "string", "enum": ["A", "B", "C", "D", "F"]],
            "headline": ["type": "string"],
            "observations": ["type": "array", "items": ["type": "string"]],
            "progressSinceThen": ["type": "string"],
            "focusAreas": ["type": "array", "items": ["type": "string"]],
            "ordersForToday": ["type": "array", "items": ["type": "string"]],
        ],
        "required": ["grade", "headline", "observations", "progressSinceThen", "focusAreas", "ordersForToday"],
        "additionalProperties": false,
    ] }

    // MARK: - Response decoding

    private struct MessageResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        struct StopDetails: Decodable {
            let explanation: String?
        }

        let content: [Block]
        let stopReason: String?
        let stopDetails: StopDetails?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
            case stopDetails = "stop_details"
        }
    }

    static func errorMessage(from data: Data) -> String {
        struct ErrorEnvelope: Decodable {
            struct Detail: Decodable { let message: String }
            let error: Detail
        }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
            ?? String(data: data, encoding: .utf8)
            ?? "Unknown error"
    }
}
