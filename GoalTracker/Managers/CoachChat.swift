import Foundation

/// One earlier turn of the conversation, as plain values.
struct ChatTurn: Equatable, Sendable {
    let role: CoachMessage.Role
    let text: String
}

/// Ask the Coach: questions about the user's own progress, answered from their real data.
extension CoachService {
    /// Earlier turns sent with each question. Older ones stay on the device but aren't re-sent, to keep requests small.
    static let chatHistoryLimit = 10

    func ask(_ question: String, history: [ChatTurn], context: String, tone: CoachTone) async throws -> String {
        let answer = try Self.decodeText(from: try await send(Self.chatRequestBody(question: question, history: history, context: context, tone: tone)))
        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func chatRequestBody(question: String, history: [ChatTurn], context: String, tone: CoachTone) -> [String: Any] {
        var turns = Array(history.suffix(chatHistoryLimit))
        // The API needs turns to start with the user and alternate; drop anything that would break that.
        while turns.first?.role == .assistant { turns.removeFirst() }
        var messages: [[String: Any]] = []
        for turn in turns {
            if let last = messages.last, last["role"] as? String == turn.role.rawValue {
                messages[messages.count - 1]["content"] = "\(last["content"] as? String ?? "")\n\n\(turn.text)"
            } else {
                messages.append(["role": turn.role.rawValue, "content": turn.text])
            }
        }
        // Fresh data rides with the newest question only, so earlier turns don't repeat it.
        let latest = "\(context)\n\nQUESTION: \(question)"
        if messages.last?["role"] as? String == CoachMessage.Role.user.rawValue {
            messages[messages.count - 1]["content"] = "\(messages[messages.count - 1]["content"] as? String ?? "")\n\n\(latest)"
        } else {
            messages.append(["role": "user", "content": latest])
        }
        return [
            "model": model,
            "max_tokens": 8_000,
            "thinking": ["type": "adaptive"],
            "fallbacks": "default",
            "output_config": ["effort": "medium"],
            "system": chatSystemPrompt(tone: tone),
            "messages": messages,
        ]
    }

    static func chatSystemPrompt(tone: CoachTone) -> String {
        """
        You are the user's weight-loss and fitness coach inside the Vanity app. They're asking about their own progress. \
        Answer from CLIENT DATA and HISTORY, which come from their Apple Health data and the app.

        \(tone.instructions)

        \(CoachSafety.rules)

        How to answer:
        - Use their real numbers: dates, weights, workouts, logged food. Never invent a workout, meal, weigh-in or trend. \
        If the data needed isn't there, say exactly what's missing and what they could log or connect to answer it next time.
        - Day-to-day weight swings are mostly water. Talk about trends (the weekly weights, the measured pace), not single readings.
        - For "why has my weight stalled?" or "what changed?", compare specific weeks or days from HISTORY and name the \
        concrete differences you can see (logging gaps, fewer workouts, intake changes). Say when a difference is too small to mean much.
        - For "how realistic is my goal?", use the required pace, measured pace and projection from CLIENT DATA, stated as \
        estimates. Don't push a bigger deficit to close a gap.
        - Partial days (today) are in progress, not a full day's intake.
        - Keep it short: usually 2 to 5 sentences or a few bullets. End with one specific next step when it helps.
        - Plain text only. No markdown headings or tables; simple "- " bullets are fine.
        """
    }
}
