import Foundation

/// A measured trend over one trailing window.
struct TrendWindow: Equatable, Sendable {
    let windowDays: Int
    /// Weekly loss rate (positive = losing, negative = gaining), from the median of all pairwise slopes.
    let poundsPerWeek: Double
    /// Middle half of the pairwise slopes, as weekly loss rates: a plain-language uncertainty band.
    let range: ClosedRange<Double>
    /// Days with at least one weigh-in.
    let daysWithReadings: Int
    /// Days between the first and last weigh-in in the window.
    let spanDays: Int
}

struct WeightTrend: Equatable, Sendable {
    /// One value per local calendar day (median of that day's readings), oldest first.
    let dailyWeights: [WeightPoint]
    /// Trailing 7-day mean, only on days with at least two weigh-ins in their window, so gaps aren't bridged.
    let smoothed: [WeightPoint]
    /// Mean of the last seven days' daily weights, if there are any.
    let smoothedCurrent: Double?
    let latestReading: Date?
    let fourteenDay: TrendWindow?
    let twentyEightDay: TrendWindow?
    /// No weigh-in in the last `WeightTrendService.staleAfterDays` days.
    let isStale: Bool
    let confidence: Confidence

    /// The observed pace shown to the user: the recent 14-day trend when available, else the 28-day one.
    var actualPoundsPerWeek: Double? { (fourteenDay ?? twentyEightDay)?.poundsPerWeek }
    var primaryWindow: TrendWindow? { fourteenDay ?? twentyEightDay }

    /// The pace used for forecasts: the slower of the 14- and 28-day trends, so a good week isn't extrapolated.
    var forecastWindow: TrendWindow? {
        switch (fourteenDay, twentyEightDay) {
        case let (short?, long?): short.poundsPerWeek <= long.poundsPerWeek ? short : long
        case let (short?, nil): short
        case let (nil, long?): long
        case (nil, nil): nil
        }
    }

    static let empty = WeightTrend(
        dailyWeights: [], smoothed: [], smoothedCurrent: nil, latestReading: nil,
        fourteenDay: nil, twentyEightDay: nil, isStale: true, confidence: .low
    )
}

/// Turns raw HealthKit weigh-ins into an observed trend. Pure and cheap (a 28-day window is at most
/// ~380 pairwise slopes), so it's recomputed with every dashboard snapshot rather than cached.
enum WeightTrendService {
    static let staleAfterDays = 7
    /// Minimum weigh-in days and span for each window to count as a reliable trend.
    static let fourteenDayRequirement = (days: 4, span: 7)
    static let twentyEightDayRequirement = (days: 6, span: 14)
    /// 14- and 28-day trends within this many lb/week of each other agree.
    static let agreementTolerance = 1.0

    static func trend(_ history: [WeightPoint], now: Date = .now, calendar: Calendar = .current) -> WeightTrend {
        let daily = dailyWeights(history.filter { $0.date <= now }, calendar: calendar)
        guard let latest = daily.last else { return .empty }

        let today = calendar.startOfDay(for: now)
        let daysSinceLatest = -dayIndex(latest.date, from: today, calendar: calendar)
        let isStale = daysSinceLatest > staleAfterDays

        let fourteen = isStale ? nil : window(daily, days: 14, requirement: fourteenDayRequirement, today: today, calendar: calendar)
        let twentyEight = isStale ? nil : window(daily, days: 28, requirement: twentyEightDayRequirement, today: today, calendar: calendar)

        let confidence: Confidence
        if let fourteen, let twentyEight, twentyEight.daysWithReadings >= 10,
           abs(fourteen.poundsPerWeek - twentyEight.poundsPerWeek) <= agreementTolerance {
            confidence = .high
        } else if fourteen != nil || twentyEight != nil {
            confidence = .medium
        } else {
            confidence = .low
        }

        let lastWeek = daily.filter { dayIndex($0.date, from: today, calendar: calendar) > -7 }
        return WeightTrend(
            dailyWeights: daily,
            smoothed: smoothed(daily, calendar: calendar),
            smoothedCurrent: lastWeek.isEmpty ? nil : lastWeek.map(\.pounds).reduce(0, +) / Double(lastWeek.count),
            latestReading: history.map(\.date).filter { $0 <= now }.max(),
            fourteenDay: fourteen,
            twentyEightDay: twentyEight,
            isStale: isStale,
            confidence: confidence
        )
    }

    /// Sorts readings and collapses each local calendar day to its median, so duplicate readings
    /// (two apps syncing the same weigh-in) and second weigh-ins don't add weight to that day.
    static func dailyWeights(_ history: [WeightPoint], calendar: Calendar = .current) -> [WeightPoint] {
        Dictionary(grouping: history) { calendar.startOfDay(for: $0.date) }
            .map { day, readings in WeightPoint(date: day, pounds: median(readings.map(\.pounds))) }
            .sorted { $0.date < $1.date }
    }

    /// Theil–Sen estimate over the trailing window: the median of slopes between every pair of days.
    static func window(
        _ daily: [WeightPoint],
        days: Int,
        requirement: (days: Int, span: Int),
        today: Date,
        calendar: Calendar = .current
    ) -> TrendWindow? {
        let points = daily
            .map { (x: dayIndex($0.date, from: today, calendar: calendar), y: $0.pounds) }
            .filter { $0.x > -days && $0.x <= 0 }
        guard points.count >= requirement.days,
              let first = points.first?.x, let last = points.last?.x,
              last - first >= requirement.span
        else { return nil }

        var slopes: [Double] = []
        for i in points.indices {
            for j in points.indices where j > i {
                slopes.append((points[j].y - points[i].y) / Double(points[j].x - points[i].x))
            }
        }
        slopes.sort()
        // Slopes are lb/day of change; flip sign so a positive rate means losing.
        let rate = -median(slopes) * 7
        let fastest = -quantile(slopes, 0.25) * 7
        let slowest = -quantile(slopes, 0.75) * 7
        return TrendWindow(
            windowDays: days, poundsPerWeek: rate, range: min(slowest, fastest)...max(slowest, fastest),
            daysWithReadings: points.count, spanDays: last - first
        )
    }

    static func smoothed(_ daily: [WeightPoint], calendar: Calendar = .current) -> [WeightPoint] {
        daily.compactMap { point in
            let window = daily.filter {
                let offset = dayIndex($0.date, from: point.date, calendar: calendar)
                return offset > -7 && offset <= 0
            }
            guard window.count >= 2 else { return nil }
            return WeightPoint(date: point.date, pounds: window.map(\.pounds).reduce(0, +) / Double(window.count))
        }
    }

    /// Whole local calendar days from `reference` to `date` (negative = before). Ignores DST hour shifts.
    static func dayIndex(_ date: Date, from reference: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: reference), to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func median(_ values: [Double]) -> Double { quantile(values.sorted(), 0.5) }

    /// Linear-interpolated quantile of already sorted values.
    static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let position = q * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}
