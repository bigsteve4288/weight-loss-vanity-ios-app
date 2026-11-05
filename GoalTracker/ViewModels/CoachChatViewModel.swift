import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CoachChatViewModel {
    var draft = ""
    var isSending = false
    var errorMessage: String?

    static let suggestions = [
        "What should I focus on today?",
        "Why has my weight stalled?",
        "What did I do differently last week?",
        "How many workouts did I complete this month?",
        "How realistic is my goal?",
    ]

    /// Workouts are fetched far enough back to cover last calendar month in full.
    static let workoutHistoryDays = 62

    func send(
        _ question: String,
        tone: CoachTone,
        profile: GoalProfile?,
        health: HealthKitManager,
        conversation: [CoachMessage],
        context: ModelContext
    ) async {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        guard let saved = KeychainStore.read(KeychainStore.anthropicAPIKey) else {
            errorMessage = "Add your coach access code in AI Coach first."
            return
        }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let history = conversation.sorted { $0.date < $1.date }.map { ChatTurn(role: $0.role, text: $0.text) }
        context.insert(CoachMessage(role: .user, text: question))
        draft = ""

        let briefing = await Self.briefing(profile: profile, health: health, context: context)
        do {
            let answer = try await CoachService(credential: .init(saved)).ask(question, history: history, context: briefing, tone: tone)
            context.insert(CoachMessage(role: .assistant, text: answer))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear(_ conversation: [CoachMessage], context: ModelContext) {
        conversation.forEach(context.delete)
        errorMessage = nil
    }

    /// Today's numbers plus a summarized history, built fresh for each question.
    static func briefing(profile: GoalProfile?, health: HealthKitManager, context: ModelContext, now: Date = .now) async -> String {
        let critiques = (try? context.fetch(FetchDescriptor<CoachCritique>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let changes = (try? context.fetch(FetchDescriptor<GoalChange>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let milestones = (try? context.fetch(FetchDescriptor<WeightMilestone>())) ?? []

        async let daily = health.dailyTotals(days: CoachHistory.daysOfDetail, now: now)
        async let workouts = health.workouts(days: workoutHistoryDays)

        let today = CoachViewModel.clientContext(profile: profile, health: health, previous: critiques.first, now: now)
        let history = CoachHistory.lines(.init(
            weights: health.weightHistory,
            daily: await daily,
            workouts: await workouts,
            goalChanges: changes.map { GoalChangeRecord(date: $0.date, targetWeight: $0.targetWeightLbs, targetDate: $0.targetDate, intensity: $0.intensity) },
            verdicts: critiques.prefix(3).map { VerdictRecord(date: $0.date, grade: $0.grade, headline: $0.headline, actions: $0.ordersForToday) },
            milestones: milestones.map { MilestoneRecord(title: $0.title, weight: $0.targetWeightLbs, achieved: $0.achievedDate) },
            now: now
        ))
        return ([today, "Current time: \(now.formatted(date: .complete, time: .shortened))."] + history).joined(separator: "\n")
    }
}
