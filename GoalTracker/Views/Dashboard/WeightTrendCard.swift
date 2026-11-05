import Charts
import SwiftUI

private let oneDecimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))

/// Weigh-ins, the 7-day average, the path to the goal and the forecast, over 7, 30 or 90 days.
/// Built from the same snapshot as the Pace card, so the two always agree.
struct WeightTrendCard: View {
    let snapshot: TargetSnapshot
    let goalStartDate: Date
    let goalStartWeight: Double

    @AppStorage("weightChartRange") private var rangeRaw = ChartRange.month.rawValue

    private var range: ChartRange { ChartRange(rawValue: rangeRaw) ?? .month }

    private var model: WeightChartModel {
        WeightChartModel.build(.init(
            trend: snapshot.trend,
            plan: snapshot.plan,
            forecast: snapshot.forecast,
            goalStartDate: goalStartDate,
            goalStartWeight: goalStartWeight,
            range: range
        ))
    }

    var body: some View {
        let model = model
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardHeader(title: "Weight Trend", systemImage: "chart.line.downtrend.xyaxis")
                    Spacer()
                    if let average = snapshot.trend.smoothedCurrent {
                        Text("7-day avg \(average, format: oneDecimal)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Range", selection: $rangeRaw) {
                    ForEach(ChartRange.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)

                if model.hasEnoughData {
                    chart(model)
                        .frame(height: 220)
                        .accessibilityElement()
                        .accessibilityLabel("Weight trend chart")
                        .accessibilityValue(model.accessibilitySummary)
                    legend(model)
                } else {
                    Text("Log a few weigh-ins to see your trend over the last \(range.days) days.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .multilineTextAlignment(.center)
                }

                footnote(model)
            }
        }
    }

    // MARK: - Chart

    private func chart(_ model: WeightChartModel) -> some View {
        Chart {
            if model.targetVisible {
                RuleMark(y: .value("Target", model.target))
                    .foregroundStyle(Theme.red.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .bottom, alignment: .leading) {
                        Text("TARGET \(model.target, format: oneDecimal)")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Theme.red)
                    }
            }

            if model.xDomain.upperBound > model.today {
                RuleMark(x: .value("Today", model.today))
                    .foregroundStyle(.white.opacity(0.18))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            ForEach(model.goalPath) { point in
                LineMark(x: .value("Date", point.date), y: .value("Weight", point.pounds), series: .value("Series", "goal"))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }

            ForEach(model.forecast) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("Low", point.low), yEnd: .value("High", point.high), series: .value("Series", "band"))
                    .foregroundStyle(Theme.gold.opacity(0.14))
                LineMark(x: .value("Date", point.date), y: .value("Weight", point.pounds), series: .value("Series", "forecast"))
                    .foregroundStyle(Theme.gold.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [3, 3]))
            }

            ForEach(model.smoothedSegments) { segment in
                ForEach(segment.points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Weight", point.pounds), series: .value("Series", "avg-\(segment.id)"))
                        .foregroundStyle(Theme.gold)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }

            ForEach(model.readings) { point in
                PointMark(x: .value("Date", point.date), y: .value("Weight", point.pounds))
                    .foregroundStyle(Theme.goldLight.opacity(0.75))
                    .symbolSize(model.range == .quarter ? 14 : 28)
            }
        }
        .chartXScale(domain: model.xDomain)
        .chartYScale(domain: model.yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel()
            }
        }
    }

    private func legend(_ model: WeightChartModel) -> some View {
        HStack(spacing: 14) {
            legendItem("Weigh-ins") { Circle().fill(Theme.goldLight.opacity(0.75)).frame(width: 7, height: 7) }
            legendItem("7-day avg") { Capsule().fill(Theme.gold).frame(width: 16, height: 3) }
            if !model.goalPath.isEmpty {
                legendItem("Goal path") { dash(.white.opacity(0.45), pattern: [4, 3]) }
            }
            if !model.forecast.isEmpty {
                legendItem("Forecast") { dash(Theme.gold, pattern: [2, 2]) }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func legendItem(_ title: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: 4) {
            swatch()
            Text(title)
        }
    }

    private func dash(_ color: Color, pattern: [CGFloat]) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 1.5))
            path.addLine(to: CGPoint(x: 16, y: 1.5))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, dash: pattern))
        .frame(width: 16, height: 3)
    }

    @ViewBuilder
    private func footnote(_ model: WeightChartModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !model.targetVisible {
                Text("Target \(model.target, format: oneDecimal) lb is below this view.")
            }
            switch snapshot.forecast.state {
            case .projected:
                if let pace = snapshot.forecast.paceUsed {
                    Text("Forecast follows your slower recent trend (\(pace, format: oneDecimal) lb/week). The shaded band is its likely range.")
                }
            case .notProjected(let reason):
                Text(reason)
            case .goalReached:
                EmptyView()
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
