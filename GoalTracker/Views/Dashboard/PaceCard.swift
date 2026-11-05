import SwiftUI

private let oneDecimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
private let wholeNumber = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))

extension PaceStatus {
    var color: Color {
        switch self {
        case .aheadOfPace, .onPace, .goalReached: Theme.gold
        case .behindPace, .deadlinePassed: Theme.red
        case .insufficientData: .gray
        }
    }

    var symbol: String {
        switch self {
        case .aheadOfPace: "hare.fill"
        case .onPace: "checkmark.seal.fill"
        case .behindPace: "tortoise.fill"
        case .insufficientData: "questionmark.circle"
        case .goalReached: "crown.fill"
        case .deadlinePassed: "calendar.badge.exclamationmark"
        }
    }
}

extension Confidence {
    var label: String {
        switch self {
        case .low: "Low confidence"
        case .medium: "Medium confidence"
        case .high: "High confidence"
        }
    }
}

/// Actual pace vs. the pace the user's own deadline requires. The goal shown here is always the user's exact goal.
struct PaceCard: View {
    let snapshot: TargetSnapshot
    /// Required pace when Aggressive mode was acknowledged; a large rise since then surfaces a new warning.
    var acknowledgedRequiredPace: Double?

    private var pace: PaceAssessment { snapshot.pace }
    private var forecast: GoalForecast { snapshot.forecast }
    private var plan: GoalPlan { snapshot.plan }

    var body: some View {
        GlassCard(accent: pace.status.color) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    CardHeader(title: "Your Pace", systemImage: "speedometer")
                    Spacer()
                    if plan.intensity != .standard {
                        modeBadge
                    }
                }

                if pace.status != .goalReached && pace.status != .deadlinePassed {
                    HStack(alignment: .top) {
                        metric("REQUIRED", pace.requiredPoundsPerWeek, caption: "to hit \(plan.targetDate.formatted(.dateTime.month(.abbreviated).day()))")
                        Spacer()
                        metric("ACTUAL", pace.actualPoundsPerWeek, caption: actualCaption, color: pace.isGaining ? Theme.red : nil)
                    }
                }

                statusRow

                if pace.status != .goalReached {
                    Divider().overlay(Theme.gold.opacity(0.3))
                    forecastRows
                }

                if plan.intensity != .standard, plan.risk > .none {
                    riskNote
                }
            }
        }
    }

    // MARK: - Pieces

    private var modeBadge: some View {
        Text(plan.intensity == .aggressive ? "AGGRESSIVE GOAL" : "CLINICIAN-GUIDED")
            .font(.caption2.weight(.heavy))
            .tracking(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.red.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.red.opacity(0.7), lineWidth: 1))
            .foregroundStyle(Theme.red)
    }

    private var actualCaption: String {
        guard let window = snapshot.trend.primaryWindow else { return "no reliable trend" }
        let direction = pace.isGaining ? "gaining" : "\(window.windowDays)-day trend"
        return "\(direction) · \(window.daysWithReadings) weigh-ins"
    }

    private func metric(_ label: String, _ value: Double?, caption: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // A gain is shown as a gain (e.g. +0.6), not as a negative loss rate.
                Text(value.map { pace.isGaining && label == "ACTUAL" ? "+\(abs($0).formatted(oneDecimal))" : $0.formatted(oneDecimal) } ?? "—")
                    .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Theme.goldGradient))
                Text("lb/wk").font(.caption).foregroundStyle(.secondary)
            }
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(pace.status.title, systemImage: pace.status.symbol)
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(pace.status.color)
            if pace.status == .insufficientData {
                Text(PaceAssessment.insufficientDataMessage)
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if let summary = pace.differenceSummary {
                Text(summary).font(.subheadline.weight(.semibold).monospacedDigit())
            } else if pace.status == .deadlinePassed {
                Text("Your deadline has passed. Set a new date in Goal Settings when you're ready.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var forecastRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Your deadline", plan.targetDate.formatted(.dateTime.month(.wide).day().year()))
            switch forecast.state {
            case .projected:
                if let date = forecast.projectedGoalDate {
                    row("Projected goal date", "\(date.formatted(.dateTime.month(.wide).year())) (estimate)")
                }
            case let .notProjected(reason):
                row("Projected goal date", "Not currently projected")
                Text(reason).font(.caption).foregroundStyle(.secondary)
            case .goalReached:
                EmptyView()
            }
            if let weight = forecast.projectedWeightAtDeadline {
                let text = abs(weight.upperBound - weight.lowerBound) < 1.5
                    ? "~\(((weight.lowerBound + weight.upperBound) / 2).formatted(wholeNumber)) lb (estimate)"
                    : "~\(weight.lowerBound.formatted(wholeNumber))–\(weight.upperBound.formatted(wholeNumber)) lb (estimate)"
                row("Weight by \(plan.targetDate.formatted(.dateTime.month(.abbreviated).day()))", text)
            }
            if forecast.state != .goalReached, forecast.paceUsed != nil {
                Text("\(forecast.confidence.label) · based on your measured weigh-ins, not calorie estimates")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if plan.intensity != .standard {
                Text("Your target remains unchanged: \(plan.targetWeight.formatted(oneDecimal)) lb by \(plan.targetDate.formatted(.dateTime.month(.abbreviated).day().year())).")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.goldLight)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased()).font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.bold).monospacedDigit()).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var riskNote: some View {
        let limit = plan.usesClinicianPace ? "your clinician's limit of" : "the ~"
        VStack(alignment: .leading, spacing: 4) {
            Label(plan.risk == .severe ? "Very high required pace" : "Elevated required pace", systemImage: "exclamationmark.shield.fill")
                .font(.caption.weight(.heavy))
            Text("Your deadline needs \(plan.requiredPoundsPerWeek.formatted(oneDecimal)) lb/week, above \(limit) \(plan.sustainablePace.upperBound.formatted(oneDecimal)) lb/week\(plan.usesClinicianPace ? "" : " commonly recommended"). Vanity won't prescribe a bigger deficit or extra exercise to close the gap.")
                .font(.caption)
            if let acknowledged = acknowledgedRequiredPace,
               plan.requiredPoundsPerWeek - acknowledged >= AggressiveMode.newWarningPaceIncrease {
                Text("Required pace has risen from \(acknowledged.formatted(oneDecimal)) lb/week since you chose this mode. Consider reviewing the plan with your healthcare professional.")
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
