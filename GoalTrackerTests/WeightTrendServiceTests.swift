import Foundation
import Testing
@testable import GoalTracker

struct WeightTrendServiceTests {
    private let now = Fixture.date(2026, 11, 4)
    private let morning = Fixture.date(2026, 11, 4, hour: 7)

    private func trend(_ history: [WeightPoint]) -> WeightTrend {
        WeightTrendService.trend(history, now: now, calendar: Fixture.calendar)
    }

    private func day(_ offset: Int, _ pounds: Double, hour: Int = 7) -> WeightPoint {
        let base = Fixture.calendar.date(byAdding: .day, value: offset, to: morning)!
        return WeightPoint(date: Fixture.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base)!, pounds: pounds)
    }

    @Test func consistentLoss() throws {
        let result = trend(Fixture.history(endingAt: morning, days: 28, from: 240, perDay: 0.2))
        #expect(abs(try #require(result.fourteenDay).poundsPerWeek - 1.4) < 0.001)
        #expect(abs(try #require(result.twentyEightDay).poundsPerWeek - 1.4) < 0.001)
        #expect(result.confidence == .high)
        #expect(!result.isStale)
    }

    @Test func acceleratingLossForecastsFromTheSlowerTrend() throws {
        let early = (0..<14).map { day($0 - 27, 240 - Double($0) * 0.1) }
        let late = (0..<14).map { day($0 - 13, 238.6 - Double($0) * 0.3) }
        let result = trend(early + late)
        let short = try #require(result.fourteenDay)
        let long = try #require(result.twentyEightDay)
        #expect(short.poundsPerWeek > long.poundsPerWeek)
        #expect(result.actualPoundsPerWeek == short.poundsPerWeek)
        #expect(result.forecastWindow == long)
    }

    @Test func slowingLossShowsTheRecentSlowdown() throws {
        let early = (0..<14).map { day($0 - 27, 240 - Double($0) * 0.3) }
        let late = (0..<14).map { day($0 - 13, 235.8 - Double($0) * 0.05) }
        let result = trend(early + late)
        let short = try #require(result.fourteenDay)
        #expect(short.poundsPerWeek < (result.twentyEightDay?.poundsPerWeek ?? 0))
        #expect(result.forecastWindow == short)
    }

    @Test func plateau() {
        let result = trend(Fixture.history(endingAt: morning, days: 14, from: 230, perDay: 0))
        #expect(abs(result.actualPoundsPerWeek ?? 99) < 0.001)
    }

    @Test func weightGainIsNegative() {
        let result = trend(Fixture.history(endingAt: morning, days: 14, from: 228, perDay: -0.1))
        #expect(abs((result.actualPoundsPerWeek ?? 0) + 0.7) < 0.001)
    }

    @Test func irregularWeighIns() {
        // Four weigh-in days spread over 12 days: enough for the 14-day trend, not the 28-day one.
        let result = trend([day(-12, 232), day(-9, 231.4), day(-5, 230.6), day(-1, 229.8)])
        #expect(result.fourteenDay != nil)
        #expect(result.twentyEightDay == nil)
        #expect(result.confidence == .medium)
    }

    @Test func duplicateReadingsCollapseToOneDay() {
        let base = Fixture.history(endingAt: morning, days: 10, from: 226, perDay: 0.2)
        // The same weigh-in synced twice, plus an evening reading that day.
        let duplicated = base + [base[3], WeightPoint(date: base[3].date.addingTimeInterval(12 * 3600), pounds: base[3].pounds + 0.1)]
        let single = trend(base)
        let doubled = trend(duplicated)
        #expect(doubled.dailyWeights.count == single.dailyWeights.count)
        #expect(abs((doubled.actualPoundsPerWeek ?? 0) - (single.actualPoundsPerWeek ?? 0)) < 0.05)
    }

    @Test func missingHistory() {
        let result = trend([])
        #expect(result.actualPoundsPerWeek == nil)
        #expect(result.smoothedCurrent == nil)
        #expect(result.confidence == .low)
    }

    @Test func oneWaterWeightSpikeDoesntMoveTheTrend() {
        var history = Fixture.history(endingAt: morning, days: 14, from: 230, perDay: 0.2)
        history[9] = WeightPoint(date: history[9].date, pounds: history[9].pounds + 4)
        #expect(abs((trend(history).actualPoundsPerWeek ?? 0) - 1.4) < 0.15)
    }

    @Test func staleHistoryHasNoPace() {
        let ended = Fixture.calendar.date(byAdding: .day, value: -10, to: morning)!
        let result = trend(Fixture.history(endingAt: ended, days: 14, from: 230, perDay: 0.2))
        #expect(result.isStale)
        #expect(result.actualPoundsPerWeek == nil)
    }

    @Test func smoothingDoesntBridgeGaps() {
        let result = trend([day(-20, 232), day(-5, 229)])
        #expect(result.smoothed.isEmpty)
        let dense = trend(Fixture.history(endingAt: morning, days: 7, from: 230, perDay: 0.2))
        #expect(dense.smoothed.count == 6)
    }

    @Test func futureReadingsAreIgnored() {
        let result = trend(Fixture.history(endingAt: morning, days: 10, from: 226, perDay: 0.2) + [day(3, 150)])
        #expect(result.dailyWeights.allSatisfy { $0.date <= now })
    }
}
