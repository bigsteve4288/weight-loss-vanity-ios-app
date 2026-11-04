import Foundation
import Testing
@testable import GoalTracker

struct TargetEngineTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func input(current: Double?, consumed: Double = 0, active: Double = 0, basal: Double = 0, history: [WeightPoint] = []) -> TargetEngine.Input {
        TargetEngine.Input(
            startWeight: 234,
            lossGoal: 34,
            targetDate: date(2027, 3, 4),
            currentWeight: current,
            history: history,
            caloriesConsumed: consumed,
            activeBurn: active,
            basalBurn: basal,
            restingCaloriesPerDay: 1800,
            now: date(2026, 11, 4),
            calendar: calendar
        )
    }

    @Test func targetWeightAndRemaining() {
        let snapshot = TargetEngine.snapshot(input(current: 224))
        #expect(snapshot.targetWeight == 200)
        #expect(snapshot.poundsLost == 10)
        #expect(snapshot.poundsRemaining == 24)
        #expect(abs(snapshot.progress - 10.0 / 34.0) < 0.0001)
    }

    @Test func daysAndRequiredDeficit() {
        let snapshot = TargetEngine.snapshot(input(current: 224))
        #expect(snapshot.daysRemaining == 120)
        #expect(abs(snapshot.requiredDailyDeficit - 24 * 3500 / 120) < 0.0001)
        #expect(abs(snapshot.requiredPoundsPerWeek - 24 / (120.0 / 7)) < 0.0001)
        #expect(!snapshot.exceedsSafePace)
    }

    @Test func statusFollowsTodaysDeficitWithoutTrend() {
        // Required daily deficit is 700 kcal.
        #expect(TargetEngine.snapshot(input(current: 224, consumed: 1000, active: 500, basal: 1300)).status == .onTrack)
        #expect(TargetEngine.snapshot(input(current: 224, consumed: 1500, active: 300, basal: 1300)).status == .pushHarder)
        #expect(TargetEngine.snapshot(input(current: 224, consumed: 2500, active: 300, basal: 1300)).status == .deficitNeeded)
    }

    @Test func fastEnoughTrendIsOnTrackEvenOnAHeavyDay() {
        let history = (0..<8).map { WeightPoint(date: date(2026, 10, 22 + $0), pounds: 228 - Double($0) * 0.5) }
        let snapshot = TargetEngine.snapshot(input(current: 224, consumed: 3000, basal: 1300, history: history))
        #expect(abs((snapshot.actualPoundsPerWeek ?? 0) - 3.5) < 0.0001)
        #expect(snapshot.status == .onTrack)
    }

    @Test func specialStatuses() {
        #expect(TargetEngine.snapshot(input(current: nil)).status == .needsData)
        #expect(TargetEngine.snapshot(input(current: 199)).status == .goalReached)
        var late = input(current: 220)
        late.now = date(2027, 3, 5)
        #expect(TargetEngine.snapshot(late).status == .deadlinePassed)
    }

    @Test func flagsUnsafePace() {
        var rushed = input(current: 234)
        rushed.targetDate = date(2026, 12, 4)
        #expect(TargetEngine.snapshot(rushed).exceedsSafePace)
    }

    @Test func fallsBackToProratedRestingCalories() {
        // Noon: half of the 1800 kcal fallback has been burned.
        let snapshot = TargetEngine.snapshot(input(current: 224, consumed: 400, basal: 0))
        #expect(abs(snapshot.todayBurn - 900) < 0.5)
        #expect(abs(snapshot.todayDeficit - 500) < 0.5)
    }

    @Test func trendNeedsEnoughSpread() {
        let now = date(2026, 11, 4)
        let close = [WeightPoint(date: date(2026, 11, 3), pounds: 225), WeightPoint(date: now, pounds: 224)]
        #expect(TargetEngine.weeklyLossRate(close, now: now) == nil)
    }
}

struct NotificationContentTests {
    @Test func fireDateRollsToTomorrowWhenTimeHasPassed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        let first = NotificationContent.fireDate(dayOffset: 0, hour: 7, minute: 0, now: now, calendar: calendar)!
        #expect(calendar.component(.day, from: first) == 5)
        let later = NotificationContent.fireDate(dayOffset: 0, hour: 20, minute: 30, now: now, calendar: calendar)!
        #expect(calendar.component(.day, from: later) == 4)
    }

    @Test func titleIncludesLiveNumbers() {
        #expect(NotificationContent.title(daysLeft: 120, poundsLeft: 24, index: 0) == "120 days. 24.0 lbs. No excuses.")
    }
}
