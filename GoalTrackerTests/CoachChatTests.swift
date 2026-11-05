import Foundation
import Testing
@testable import GoalTracker

struct CoachHistoryTests {
    private let now = Fixture.date(2026, 11, 18, hour: 15)
    private var calendar: Calendar { Fixture.calendar }

    private func day(_ offset: Int, hour: Int = 7) -> Date {
        calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!)!
    }

    private func ride(_ start: Date, minutes: Double = 45, source: String = "Peloton") -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(), activityName: "Ride", symbolName: "figure.outdoor.cycle", start: start,
            end: start.addingTimeInterval(minutes * 60), duration: minutes * 60, calories: 400, distanceMiles: 12, source: source
        )
    }

    private func lines(
        weights: [WeightPoint] = [],
        daily: [DailyHealthTotals] = [],
        workouts: [WorkoutSummary] = [],
        verdicts: [VerdictRecord] = [],
        changes: [GoalChangeRecord] = []
    ) -> [String] {
        CoachHistory.lines(.init(weights: weights, daily: daily, workouts: workouts, goalChanges: changes, verdicts: verdicts, now: now, calendar: calendar))
    }

    @Test func missingDataIsSaidOutright() {
        let text = lines().joined(separator: "\n")
        #expect(text.contains("No weigh-ins in the last 12 weeks."))
        #expect(text.contains("no food logged; no workouts"))
        #expect(text.contains("Workouts this month (November 1 to today): none recorded."))
        #expect(text.contains("Not available to you: sleep, steps"))
    }

    @Test func weeklyWeightsUseOnlyRealReadings() {
        let weights = Fixture.history(endingAt: day(0), days: 10, from: 225, perDay: 0.2)
        let weekly = lines(weights: weights).filter { $0.contains("weigh-in day") }
        // 10 days of readings span two 7-day blocks and nothing older.
        #expect(weekly.count == 2)
        #expect(weekly.last?.contains("(7 weigh-in days)") == true)
        #expect(weekly.first?.contains("(3 weigh-in days)") == true)
    }

    @Test func dayByDayShowsFoodWorkoutsAndWeighIns() throws {
        let daily = [DailyHealthTotals(day: calendar.startOfDay(for: day(-1)), caloriesConsumed: 1850, proteinGrams: 140, activeEnergy: 620)]
        let all = lines(weights: [WeightPoint(date: day(-1), pounds: 224.2)], daily: daily, workouts: [ride(day(-1, hour: 6))])
        let yesterday = try #require(all.first { $0.contains("1,850 kcal logged") })
        #expect(yesterday.contains("140 g protein"))
        #expect(yesterday.contains("620 active kcal"))
        #expect(yesterday.contains("Ride 45 min (Peloton)"))
        #expect(yesterday.contains("weighed 224.2 lb"))
        #expect(all.contains { $0.contains("(today, in progress)") })
    }

    @Test func monthCountsAreExactAndDeduplicated() {
        // Two rides this month, one of them recorded by both the Watch and Peloton.
        let workouts = [
            ride(day(-2, hour: 6)), ride(day(-2, hour: 6), source: "Apple Watch"),
            ride(day(-5, hour: 6), minutes: 30),
        ]
        let month = lines(workouts: workouts).first { $0.hasPrefix("- Workouts this month") }
        #expect(month == "- Workouts this month (November 1 to today): 2 workouts, 1 h 15 min total (2 ride).")
    }

    @Test func lastMonthOnlyWhenTheHistoryCoversIt() {
        let partial = lines(workouts: [ride(Fixture.date(2026, 10, 20, hour: 6))])
        #expect(!partial.contains { $0.hasPrefix("- Workouts last month") })

        let covered = lines(workouts: [ride(Fixture.date(2026, 10, 1, hour: 6)), ride(Fixture.date(2026, 10, 20, hour: 6))])
        #expect(covered.contains("- Workouts last month (October): 2 workouts, 1 h 30 min total (2 ride)."))
    }

    @Test func recentVerdictsAndGoalChangesAreIncluded() {
        let text = lines(
            verdicts: [VerdictRecord(date: day(-3), grade: "B", headline: "Solid week.", actions: ["Log dinner"])],
            changes: [GoalChangeRecord(date: day(-20), targetWeight: 200, targetDate: Fixture.date(2027, 3, 4), intensity: .aggressive)]
        ).joined(separator: "\n")
        #expect(text.contains("grade B, \"Solid week.\". Actions given: Log dinner"))
        #expect(text.contains("target 200.0 lb"))
        #expect(text.contains("Aggressive"))
    }
}

struct CoachChatRequestTests {
    private func messages(_ body: [String: Any]) -> [[String: Any]] {
        body["messages"] as? [[String: Any]] ?? []
    }

    @Test func dataRidesOnlyWithTheNewestQuestion() throws {
        let history = [ChatTurn(role: .user, text: "Hi"), ChatTurn(role: .assistant, text: "Hello.")]
        let body = CoachService.chatRequestBody(question: "Why the stall?", history: history, context: "CLIENT DATA\n- x", tone: .blunt)
        let turns = messages(body)
        #expect(turns.map { $0["role"] as? String } == ["user", "assistant", "user"])
        #expect(turns[0]["content"] as? String == "Hi")
        let last = try #require(turns.last?["content"] as? String)
        #expect(last.hasPrefix("CLIENT DATA"))
        #expect(last.hasSuffix("QUESTION: Why the stall?"))
    }

    @Test func historyIsTrimmedAndStartsWithTheUser() {
        var history: [ChatTurn] = []
        for index in 0..<15 {
            history.append(ChatTurn(role: .user, text: "q\(index)"))
            history.append(ChatTurn(role: .assistant, text: "a\(index)"))
        }
        let turns = messages(CoachService.chatRequestBody(question: "Now?", history: history, context: "", tone: .supportive))
        // The last 10 turns, then the new question.
        #expect(turns.count == 11)
        #expect(turns.first?["content"] as? String == "q10")

        // A trimmed window that would start with an answer drops it so the user speaks first.
        let odd = messages(CoachService.chatRequestBody(question: "Now?", history: Array(history.dropLast()), context: "", tone: .supportive))
        #expect(odd.first?["role"] as? String == "user")
        #expect(odd.first?["content"] as? String == "q10")
    }

    @Test func unansweredQuestionMergesWithTheNewOne() {
        // A failed request leaves a user turn with no reply; roles must still alternate.
        let history = [ChatTurn(role: .user, text: "First try")]
        let turns = messages(CoachService.chatRequestBody(question: "Second try", history: history, context: "DATA", tone: .supportive))
        #expect(turns.count == 1)
        #expect((turns[0]["content"] as? String)?.hasPrefix("First try\n\nDATA") == true)
    }

    @Test func everyToneCarriesTheSafetyRulesAndNoInventionRule() {
        for tone in CoachTone.allCases {
            let prompt = CoachService.chatSystemPrompt(tone: tone)
            #expect(prompt.contains(CoachSafety.rules))
            #expect(prompt.contains("Never invent a workout, meal, weigh-in or trend"))
        }
    }

    @Test func textAnswerIsDecodedAfterTheLastFallback() throws {
        let json = """
        {"content":[{"type":"text","text":"old"},{"type":"fallback"},{"type":"thinking"},{"type":"text","text":"You did 6 rides."}],"stop_reason":"end_turn"}
        """
        #expect(try CoachService.decodeText(from: Data(json.utf8)) == "You did 6 rides.")
    }

    @Test func emptyAnswerIsMalformed() {
        let json = #"{"content":[{"type":"text","text":"  "}],"stop_reason":"end_turn"}"#
        #expect(throws: CoachError.malformed) { try CoachService.decodeText(from: Data(json.utf8)) }
    }
}
