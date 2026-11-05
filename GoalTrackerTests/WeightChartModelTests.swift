import Foundation
import Testing
@testable import GoalTracker

struct WeightChartModelTests {
    private let now = Fixture.date(2026, 11, 4, hour: 9)
    private var today: Date { Fixture.calendar.startOfDay(for: now) }

    private func day(_ offset: Int, hour: Int = 7) -> Date {
        Fixture.calendar.date(byAdding: .hour, value: hour, to: Fixture.calendar.date(byAdding: .day, value: offset, to: today)!)!
    }

    private func model(
        _ history: [WeightPoint],
        range: ChartRange = .month,
        target: Double = 200,
        deadline: Date = Fixture.date(2027, 3, 4),
        goalStart: Date? = nil,
        goalStartWeight: Double = 230
    ) -> WeightChartModel {
        let current = history.last?.pounds ?? goalStartWeight
        let plan = WeightGoalEngine.plan(.init(
            targetWeight: target, targetDate: deadline, currentWeight: current, latestWeightDate: history.last?.date,
            now: now, calendar: Fixture.calendar
        ))
        let trend = WeightTrendService.trend(history, now: now, calendar: Fixture.calendar)
        let forecast = GoalForecastService.forecast(plan: plan, trend: trend, currentWeight: current, now: now, calendar: Fixture.calendar)
        return WeightChartModel.build(.init(
            trend: trend, plan: plan, forecast: forecast,
            goalStartDate: goalStart ?? day(-60), goalStartWeight: goalStartWeight,
            range: range, now: now, calendar: Fixture.calendar
        ))
    }

    @Test func windowCoversRangeAndLooksAhead() {
        let chart = model(Fixture.history(endingAt: day(0), days: 60, from: 230, perDay: 0.15))
        #expect(chart.xDomain.lowerBound == day(-29, hour: 0))
        #expect(chart.xDomain.upperBound == day(10, hour: 0))
        #expect(chart.readings.count == 30)
        #expect(chart.readings.allSatisfy { chart.xDomain.contains($0.date) })
    }

    @Test func eachRangeShowsItsOwnHistory() {
        let history = Fixture.history(endingAt: day(0), days: 97, from: 235, perDay: 0.1)
        #expect(model(history, range: .week).readings.count == 7)
        #expect(model(history, range: .quarter).readings.count == 90)
        // The extra week before the 90 days still gives the first visible day a 7-day average.
        #expect(model(history, range: .quarter).smoothedSegments.first?.points.first?.date == day(-89, hour: 0))
    }

    @Test func sameDayReadingsAreOneDot() {
        var history = Fixture.history(endingAt: day(0), days: 10, from: 225, perDay: 0.2)
        history.append(WeightPoint(date: day(0, hour: 20), pounds: 230))
        let chart = model(history, range: .week)
        #expect(chart.readings.count == 7)
        #expect(chart.readings.filter { Fixture.calendar.isDate($0.date, inSameDayAs: today) }.count == 1)
    }

    @Test func averageLineIsNotDrawnAcrossGaps() {
        let before = Fixture.history(endingAt: day(-15), days: 10, from: 228, perDay: 0.2)
        let after = Fixture.history(endingAt: day(0), days: 6, from: 225, perDay: 0.2)
        let chart = model(before + after)
        #expect(chart.smoothedSegments.count == 2)
        for segment in chart.smoothedSegments {
            for (a, b) in zip(segment.points, segment.points.dropFirst()) {
                #expect(WeightTrendService.dayIndex(b.date, from: a.date, calendar: Fixture.calendar) <= WeightChartModel.maxConnectedGapDays)
            }
        }
    }

    @Test func splitDropsLonePoints() {
        let points = [day(-20), day(-10), day(-9), day(-2)].map { WeightPoint(date: $0, pounds: 220) }
        let segments = WeightChartModel.split(points, maxGapDays: 4, calendar: Fixture.calendar)
        #expect(segments.count == 1)
        #expect(segments[0].points.count == 2)
    }

    @Test func forecastStartsFromTheAverageAndNeverPassesTarget() throws {
        let chart = model(Fixture.history(endingAt: day(0), days: 28, from: 206, perDay: 0.2), range: .quarter, target: 200)
        let first = try #require(chart.forecast.first)
        #expect(first.date == today)
        #expect(chart.forecast.count == ChartRange.quarter.futureDays + 1)
        for point in chart.forecast {
            #expect(point.low <= point.pounds + 1e-9 && point.pounds <= point.high + 1e-9)
            #expect(point.low >= 200)
        }
        // At 1.4 lb/week the target is reached inside the 30-day look-ahead, and the line stops there.
        #expect(chart.forecast.last?.pounds == 200)
    }

    @Test func noForecastWithoutAReliableTrend() {
        #expect(model(Fixture.history(endingAt: day(0), days: 3, from: 225, perDay: 0.2)).forecast.isEmpty)
        #expect(model(Fixture.history(endingAt: day(0), days: 20, from: 225, perDay: 0)).forecast.isEmpty)
        #expect(model(Fixture.history(endingAt: day(-12), days: 20, from: 225, perDay: 0.2)).forecast.isEmpty)
    }

    @Test func goalPathIsClippedToTheWindow() throws {
        let start = WeightPoint(date: day(-60, hour: 0), pounds: 230)
        let end = WeightPoint(date: day(60, hour: 0), pounds: 200)
        let clipped = WeightChartModel.clippedLine(from: start, to: end, within: day(-29, hour: 0)...day(10, hour: 0))
        #expect(clipped.count == 2)
        // Halfway through the line is 215; 31 days in is a little above it.
        #expect(abs(clipped[0].pounds - (230 - 30 * 31.0 / 120)) < 0.05)
        #expect(clipped[1].date == day(10, hour: 0))

        #expect(WeightChartModel.clippedLine(from: start, to: WeightPoint(date: day(-40), pounds: 200), within: day(-29)...day(10)).isEmpty)
        #expect(WeightChartModel.clippedLine(from: WeightPoint(date: day(20), pounds: 230), to: end, within: day(-29)...day(10)).isEmpty)
    }

    @Test func farTargetDoesNotFlattenAShortView() {
        let history = Fixture.history(endingAt: day(0), days: 10, from: 226, perDay: 0.1)
        let week = model(history, range: .week, target: 190, goalStart: day(-5), goalStartWeight: 226)
        #expect(!week.targetVisible)
        #expect(week.yDomain.lowerBound > 200)

        let near = model(history, range: .week, target: 223, goalStart: day(-5), goalStartWeight: 226)
        #expect(near.targetVisible)
        #expect(near.yDomain.contains(223))
    }

    @Test func everythingDrawnFitsTheAxis() {
        let chart = model(Fixture.history(endingAt: day(0), days: 40, from: 232, perDay: 0.2), range: .quarter)
        let values = chart.readings.map(\.pounds) + chart.smoothedSegments.flatMap { $0.points.map(\.pounds) }
            + chart.goalPath.map(\.pounds) + chart.forecast.flatMap { [$0.low, $0.high] }
        #expect(values.allSatisfy { chart.yDomain.contains($0) })
    }

    @Test func oneWeighInIsNotATrend() {
        let chart = model([WeightPoint(date: day(0), pounds: 224)], range: .week)
        #expect(!chart.hasEnoughData)
        #expect(chart.forecast.isEmpty)
        #expect(chart.accessibilitySummary == "Not enough weigh-ins in the last 7 days to show a trend.")
    }

    @Test func accessibilitySummaryDescribesTheChart() {
        let summary = model(Fixture.history(endingAt: day(0), days: 28, from: 230, perDay: 0.15)).accessibilitySummary
        #expect(summary.hasPrefix("Weight over the last 30 days"))
        #expect(summary.contains("Seven-day average"))
        #expect(summary.contains("Target 200.0 pounds."))
    }
}
