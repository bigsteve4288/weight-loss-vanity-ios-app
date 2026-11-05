import Foundation

/// The trend chart's visible window: days of history, plus a short look ahead for the forecast.
enum ChartRange: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var days: Int { rawValue }
    var label: String { "\(rawValue)D" }
    /// How far past today the chart extends, so the forecast and goal path have room to show.
    var futureDays: Int {
        switch self {
        case .week: 3
        case .month: 10
        case .quarter: 30
        }
    }
}

/// Everything the trend chart draws, computed from the same trend, plan and forecast the Pace card uses,
/// so the chart can never disagree with the numbers. Pure, so it's unit tested.
struct WeightChartModel: Equatable, Sendable {
    struct Segment: Equatable, Sendable, Identifiable {
        let id: Int
        let points: [WeightPoint]
    }

    struct ForecastPoint: Equatable, Sendable, Identifiable {
        var id: Date { date }
        let date: Date
        let pounds: Double
        /// Uncertainty band from the trend's middle half of slopes. Never below the target.
        let low: Double
        let high: Double
    }

    let range: ChartRange
    let today: Date
    let xDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    /// One reading per day (that day's median), shown as dots. Never joined into a line.
    let readings: [WeightPoint]
    /// The 7-day average, broken wherever weigh-ins have a gap, so a line never implies data that isn't there.
    let smoothedSegments: [Segment]
    /// The straight path from the goal's start to the target on the deadline, clipped to the window.
    let goalPath: [WeightPoint]
    /// The projection forward from today. Empty unless the Pace card's forecast is projected.
    let forecast: [ForecastPoint]
    let target: Double
    /// False when the target is far below the visible data; the card names it instead of flattening the chart.
    let targetVisible: Bool

    var hasEnoughData: Bool { readings.count >= 2 }

    /// A smoothed line isn't drawn across more than this many days without a weigh-in.
    static let maxConnectedGapDays = 4

    struct Input {
        var trend: WeightTrend
        var plan: GoalPlan
        var forecast: GoalForecast
        var goalStartDate: Date
        var goalStartWeight: Double
        var range: ChartRange
        var now: Date = .now
        var calendar: Calendar = .current
    }

    static func build(_ input: Input) -> WeightChartModel {
        let calendar = input.calendar
        let today = calendar.startOfDay(for: input.now)
        let start = calendar.date(byAdding: .day, value: -(input.range.days - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: input.range.futureDays, to: today) ?? today
        let target = input.plan.targetWeight

        let readings = input.trend.dailyWeights.filter { $0.date >= start && $0.date <= input.now }
        let smoothed = input.trend.smoothed.filter { $0.date >= start && $0.date <= input.now }
        let segments = split(smoothed, maxGapDays: maxConnectedGapDays, calendar: calendar)

        let goalPath = clippedLine(
            from: WeightPoint(date: calendar.startOfDay(for: input.goalStartDate), pounds: input.goalStartWeight),
            to: WeightPoint(date: calendar.startOfDay(for: input.plan.targetDate), pounds: target),
            within: start...end
        )

        var forecast: [ForecastPoint] = []
        if input.forecast.state == .projected,
           let pace = input.forecast.paceUsed,
           let band = input.trend.forecastWindow?.range,
           let base = input.trend.smoothedCurrent {
            forecast = (0...input.range.futureDays).compactMap { day in
                guard let date = calendar.date(byAdding: .day, value: day, to: today) else { return nil }
                let weeks = Double(day) / 7
                let a = max(base - band.upperBound * weeks, target)
                let b = max(base - band.lowerBound * weeks, target)
                return ForecastPoint(date: date, pounds: max(base - pace * weeks, target), low: min(a, b), high: max(a, b))
            }
        }

        // Fit the y-axis to what's actually drawn. The target joins it only when it's reasonably close,
        // so a 7-day view of a long goal doesn't flatten into a line.
        var values = readings.map(\.pounds) + smoothed.map(\.pounds) + goalPath.map(\.pounds)
        values += forecast.flatMap { [$0.low, $0.high] }
        let dataLow = values.min() ?? target
        let dataHigh = values.max() ?? target
        let span = max(dataHigh - dataLow, 1)
        let targetVisible = target >= dataLow - max(3, span * 0.5)
        let low = targetVisible ? min(dataLow, target) : dataLow
        let high = targetVisible ? max(dataHigh, target) : dataHigh
        let padding = max((high - low) * 0.1, 0.5)

        return WeightChartModel(
            range: input.range,
            today: today,
            xDomain: start...end,
            yDomain: (low - padding)...(high + padding),
            readings: readings,
            smoothedSegments: segments,
            goalPath: goalPath,
            forecast: forecast,
            target: target,
            targetVisible: targetVisible
        )
    }

    /// Splits points into runs with no gap longer than `maxGapDays`. A run needs two points to draw a line.
    static func split(_ points: [WeightPoint], maxGapDays: Int, calendar: Calendar = .current) -> [Segment] {
        var segments: [[WeightPoint]] = []
        for point in points {
            if let previous = segments.last?.last,
               WeightTrendService.dayIndex(point.date, from: previous.date, calendar: calendar) <= maxGapDays {
                segments[segments.count - 1].append(point)
            } else {
                segments.append([point])
            }
        }
        return segments.filter { $0.count >= 2 }.enumerated().map { Segment(id: $0.offset, points: $0.element) }
    }

    /// The part of the straight line `a`→`b` that falls inside `window`, as its two end points.
    static func clippedLine(from a: WeightPoint, to b: WeightPoint, within window: ClosedRange<Date>) -> [WeightPoint] {
        let lower = max(a.date, window.lowerBound)
        let upper = min(b.date, window.upperBound)
        guard b.date > a.date, lower < upper else { return [] }
        let total = b.date.timeIntervalSince(a.date)
        func value(at date: Date) -> Double {
            a.pounds + (b.pounds - a.pounds) * date.timeIntervalSince(a.date) / total
        }
        return [WeightPoint(date: lower, pounds: value(at: lower)), WeightPoint(date: upper, pounds: value(at: upper))]
    }

    /// Spoken summary for VoiceOver, which can't read the chart itself.
    var accessibilitySummary: String {
        let lb = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        guard hasEnoughData, let first = readings.first, let last = readings.last else {
            return "Not enough weigh-ins in the last \(range.days) days to show a trend."
        }
        var parts = ["Weight over the last \(range.days) days, from \(first.pounds.formatted(lb)) to \(last.pounds.formatted(lb)) pounds."]
        if let average = smoothedSegments.last?.points.last {
            parts.append("Seven-day average \(average.pounds.formatted(lb)).")
        }
        if let projected = forecast.last {
            parts.append("Forecast about \(projected.pounds.formatted(lb)) pounds by \(projected.date.formatted(.dateTime.month(.wide).day())).")
        }
        parts.append("Target \(target.formatted(lb)) pounds.")
        return parts.joined(separator: " ")
    }
}
