import SwiftUI

extension TrackStatus {
    var color: Color {
        switch self {
        case .onTrack, .goalReached: Theme.gold
        case .buildingMomentum: Theme.goldLight
        case .loggingIncomplete, .needsAttention, .goalNeedsAdjustment: .orange
        case .deadlinePassed: Theme.red
        case .needsData: .gray
        }
    }

    var symbol: String {
        switch self {
        case .onTrack: "checkmark.shield.fill"
        case .goalReached: "crown.fill"
        case .buildingMomentum: "arrow.up.right.circle.fill"
        case .needsAttention: "exclamationmark.triangle.fill"
        case .loggingIncomplete: "square.and.pencil"
        case .goalNeedsAdjustment: "calendar.badge.clock"
        case .deadlinePassed: "calendar.badge.exclamationmark"
        case .needsData: "antenna.radiowaves.left.and.right"
        }
    }
}

private let oneDecimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
private let wholeNumber = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
private let shortDate = Date.FormatStyle.dateTime.month(.abbreviated).day()
private let longDate = Date.FormatStyle.dateTime.month(.abbreviated).day().year()

struct StatusCard: View {
    let snapshot: TargetSnapshot

    private var plan: GoalPlan { snapshot.plan }

    var body: some View {
        GlassCard(accent: snapshot.status.color) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: snapshot.status.symbol)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(snapshot.status.color)
                        .symbolEffect(.pulse, isActive: snapshot.status != .onTrack && snapshot.status != .goalReached)
                        .accessibilityHidden(true)
                    Text(snapshot.status.title)
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(snapshot.status.color)
                }
                Text(snapshot.status.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if snapshot.currentWeight != nil, plan.feasibility != .achieved {
                    trendLine
                }
                if snapshot.paceAboveSustainable {
                    note(
                        "You're losing faster than about \(plan.sustainablePace.upperBound.formatted(oneDecimal)) lb/week. Early weeks often include water weight, but if this keeps up, make sure you're eating enough to fuel yourself.",
                        systemImage: "heart.text.square"
                    )
                }
                if snapshot.currentWeight != nil, plan.needsAdjustment || plan.feasibility == .exceedsSustainable {
                    adjustment
                }
                if snapshot.currentWeight != nil, plan.weightIsStale {
                    note("Your last weigh-in is over a week old. Step on the scale so the plan uses a current weight.", systemImage: "scalemass")
                }
            }
        }
    }

    @ViewBuilder
    private var trendLine: some View {
        let planText = "plan \(plan.recommendedPoundsPerWeek.formatted(oneDecimal)) lb/week"
        if let actual = snapshot.actualPoundsPerWeek {
            Text("Measured trend: \(actual, format: oneDecimal) lb/week · \(planText)")
                .font(.caption.weight(.semibold).monospacedDigit())
        } else {
            Text("Trend: needs 4+ weigh-in days over a week · \(planText)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var adjustment: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !plan.needsAdjustment {
                Text("SAFER ALTERNATIVE (OPTIONAL)")
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(.orange)
            }
            if plan.feasibility == .exceedsSustainable, plan.intensity == .standard {
                Text("Reaching \(plan.targetWeight.formatted(oneDecimal)) lb by \(plan.targetDate.formatted(shortDate)) would take \(plan.requiredPoundsPerWeek.formatted(oneDecimal)) lb/week (roughly \(plan.requiredDailyDeficitEstimate.formatted(wholeNumber)) kcal/day). That's above the ~\(plan.sustainablePace.upperBound.formatted(oneDecimal)) lb/week that's sustainable for you, so the plan doesn't chase it.")
            }
            if let atDeadline = plan.projectedWeightAtDeadline {
                Text("At a sustainable pace: about \(atDeadline.lowerBound.formatted(wholeNumber))–\(atDeadline.upperBound.formatted(wholeNumber)) lb by \(plan.targetDate.formatted(shortDate)).")
            }
            if let dates = plan.projectedTargetDate {
                Text("\(plan.targetWeight.formatted(oneDecimal)) lb projected \(dates.lowerBound.formatted(longDate)) – \(dates.upperBound.formatted(longDate)).")
            }
            if let suggested = plan.suggestedTargetDate {
                Text(plan.needsAdjustment
                     ? "Consider moving the date to \(suggested.formatted(longDate)) in Goal Settings."
                     : "A date that fits a steady pace would be \(suggested.formatted(longDate)). Your goal stays as you set it.")
                    .foregroundStyle(Theme.goldLight)
            }
            Text("Projections are estimates, not promises.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func note(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

struct EmergencyResetButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "hand.raised.fill")
                Text("EMERGENCY RESET")
                    .tracking(2)
            }
            .font(.headline.weight(.black))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.redGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(.white)
            .shadow(color: Theme.red.opacity(0.5), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
    }
}

struct TargetCard: View {
    let snapshot: TargetSnapshot
    let startWeight: Double

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Target Engine", systemImage: "target")
                HStack(alignment: .firstTextBaseline) {
                    metric("CURRENT", snapshot.currentWeight)
                    Spacer()
                    Image(systemName: "arrow.right").foregroundStyle(Theme.gold)
                    Spacer()
                    metric("TARGET", snapshot.targetWeight)
                }
                ProgressView(value: snapshot.progress)
                    .tint(Theme.gold)
                    .scaleEffect(y: 2.2)
                HStack {
                    Text("\(snapshot.poundsLost, format: oneDecimal) lbs lost")
                    Spacer()
                    Text("\(snapshot.poundsRemaining, format: oneDecimal) lbs to go")
                        .foregroundStyle(Theme.red)
                }
                .font(.subheadline.weight(.bold).monospacedDigit())
                Text("Start \(startWeight, format: oneDecimal) lb · \(snapshot.progress.formatted(.percent.precision(.fractionLength(0)))) complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(.secondary)
            Text(value.map { $0.formatted(oneDecimal) } ?? "—")
                .font(.system(size: 38, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.goldGradient)
            Text("lb").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CountdownCard: View {
    let targetDate: Date

    var body: some View {
        GlassCard(accent: Theme.red) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Birthday Countdown", systemImage: "gift.fill")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(Calendar.current.startOfDay(for: targetDate).timeIntervalSince(context.date), 0)
                    let total = Int(remaining)
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(total / 86_400)")
                            .font(.system(size: 56, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.goldGradient)
                        Text("days").font(.headline).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%02d:%02d:%02d", total % 86_400 / 3_600, total % 3_600 / 60, total % 60))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.red)
                    }
                }
                Text(targetDate, format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DeficitCard: View {
    let snapshot: TargetSnapshot

    private var intake: IntakeAssessment { snapshot.intake }
    private var energy: EnergySummary { snapshot.energy }
    private var plan: GoalPlan { snapshot.plan }
    /// Gold only for a finished, logged day that met the plan. A day in progress is never colored as a miss.
    private var deficitColor: Color {
        intake.canJudgeDeficit && snapshot.todayDeficit >= plan.recommendedDailyDeficitEstimate * 0.8 ? Theme.gold : .primary
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: intake.canJudgeDeficit ? "Today's Deficit" : "Today So Far", systemImage: "flame.fill")
                HStack {
                    column("CONSUMED", snapshot.intake.state == .notTracking ? nil : snapshot.caloriesConsumed, intake.state.label)
                    Spacer()
                    column("BURNED", snapshot.todayBurn, energy.includesEstimates ? "includes estimate" : "\(energy.active.formatted(wholeNumber)) active")
                    Spacer()
                    column(
                        "DEFICIT",
                        snapshot.intake.state == .notTracking ? nil : snapshot.todayDeficit,
                        intake.canJudgeDeficit ? "kcal" : "so far",
                        highlight: deficitColor
                    )
                }
                if intake.canJudgeDeficit, plan.recommendedDailyDeficitEstimate > 0 {
                    ProgressView(value: min(max(snapshot.todayDeficit / plan.recommendedDailyDeficitEstimate, 0), 1))
                        .tint(deficitColor)
                }
                Text(intake.summary)
                    .font(.caption)
                    .foregroundStyle(intake.state == .missingLogs || intake.lowIntakeConcern ? .orange : .secondary)
                if intake.proteinDataMissing {
                    Text("No protein data reached Apple Health. Check macro syncing in your food app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if plan.recommendedDailyDeficitEstimate > 0 {
                    Text("Plan: about \(plan.recommendedDailyDeficitEstimate, format: wholeNumber) kcal/day deficit (rough estimate)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if !energy.issues.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(energy.issues.indices, id: \.self) { index in
                            let issue = energy.issues[index]
                            Label(issue.message, systemImage: issue.reducesConfidence ? "exclamationmark.circle" : "info.circle")
                                .foregroundStyle(issue.reducesConfidence ? Color.orange : Color.secondary)
                        }
                    }
                    .font(.caption2)
                }
            }
        }
    }

    private func column(_ label: String, _ value: Double?, _ caption: String, highlight: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(.secondary)
            Text(value.map { $0.formatted(wholeNumber) } ?? "—")
                .font(.system(.title2, design: .rounded, weight: .black).monospacedDigit())
                .foregroundStyle(highlight)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MacrosCard: View {
    let carbs: Double
    let protein: Double
    let fat: Double

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Macros Today", systemImage: "chart.pie.fill")
                HStack {
                    macro("CARBS", carbs, Theme.red)
                    Spacer()
                    macro("PROTEIN", protein, Theme.gold)
                    Spacer()
                    macro("FAT", fat, Theme.goldLight)
                }
            }
        }
    }

    private func macro(_ label: String, _ grams: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(grams, format: wholeNumber)
                    .font(.system(.title2, design: .rounded, weight: .black).monospacedDigit())
                    .foregroundStyle(color)
                Text("g").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct HealthSyncFooter: View {
    @Environment(HealthKitManager.self) private var health

    var body: some View {
        VStack(spacing: 8) {
            if !health.isAvailable {
                Text("Apple Health isn't available on this device.")
            } else if !health.hasRequestedAuthorization {
                Button("Connect Apple Health") { Task { await health.start() } }
                    .buttonStyle(.borderedProminent)
            } else if let updated = health.lastUpdated {
                Text("Synced from Apple Health at \(updated, format: .dateTime.hour().minute()) · pull to refresh")
            }
            if let error = health.errorMessage {
                Text(error).foregroundStyle(Theme.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }
}
