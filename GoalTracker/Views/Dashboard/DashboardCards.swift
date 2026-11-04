import Charts
import SwiftUI

extension TrackStatus {
    var color: Color {
        switch self {
        case .onTrack, .goalReached: Theme.gold
        case .pushHarder: .orange
        case .deficitNeeded, .deadlinePassed: Theme.red
        case .needsData: .gray
        }
    }

    var symbol: String {
        switch self {
        case .onTrack: "checkmark.shield.fill"
        case .goalReached: "crown.fill"
        case .pushHarder: "bolt.heart.fill"
        case .deficitNeeded: "exclamationmark.triangle.fill"
        case .deadlinePassed: "calendar.badge.exclamationmark"
        case .needsData: "antenna.radiowaves.left.and.right"
        }
    }
}

private let oneDecimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
private let wholeNumber = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))

struct StatusCard: View {
    let snapshot: TargetSnapshot

    var body: some View {
        GlassCard(accent: snapshot.status.color) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: snapshot.status.symbol)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(snapshot.status.color)
                        .symbolEffect(.pulse, isActive: snapshot.status != .onTrack)
                    Text(snapshot.status.title)
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(snapshot.status.color)
                }
                Text(snapshot.status.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let actual = snapshot.actualPoundsPerWeek {
                    Text("14-day pace: \(actual, format: oneDecimal) lb/week · need \(snapshot.requiredPoundsPerWeek, format: oneDecimal)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
                if snapshot.exceedsSafePace {
                    Label(
                        "Required pace is \(snapshot.requiredPoundsPerWeek.formatted(oneDecimal)) lb/week, above the ~2 lb/week generally considered safe. Consider extending the date or checking with your doctor.",
                        systemImage: "heart.text.square"
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.red)
                }
            }
        }
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
    let consumed: Double
    let active: Double

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Today's Deficit", systemImage: "flame.fill")
                HStack {
                    column("CONSUMED", consumed, "Carb Manager")
                    Spacer()
                    column("BURNED", snapshot.todayBurn, "\(active.formatted(wholeNumber)) active")
                    Spacer()
                    column("DEFICIT", snapshot.todayDeficit, "kcal", highlight: snapshot.todayDeficit >= snapshot.requiredDailyDeficit ? Theme.gold : Theme.red)
                }
                ProgressView(value: min(max(snapshot.todayDeficit / max(snapshot.requiredDailyDeficit, 1), 0), 1))
                    .tint(snapshot.todayDeficit >= snapshot.requiredDailyDeficit ? Theme.gold : Theme.red)
                Text("Required daily deficit: \(snapshot.requiredDailyDeficit, format: wholeNumber) kcal")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func column(_ label: String, _ value: Double, _ caption: String, highlight: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(.secondary)
            Text(value, format: wholeNumber)
                .font(.system(.title2, design: .rounded, weight: .black).monospacedDigit())
                .foregroundStyle(highlight)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
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

struct WeightTrendCard: View {
    let points: [WeightPoint]
    let target: Double

    private var domain: ClosedRange<Double> {
        let values = points.map(\.pounds) + [target]
        return ((values.min() ?? target) - 2)...((values.max() ?? target) + 2)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "90-Day Trend", systemImage: "chart.line.downtrend.xyaxis")
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Weight", point.pounds))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Theme.gold)
                        AreaMark(x: .value("Date", point.date), yStart: .value("Base", domain.lowerBound), yEnd: .value("Weight", point.pounds))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(colors: [Theme.gold.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    }
                    RuleMark(y: .value("Target", target))
                        .foregroundStyle(Theme.red)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("TARGET \(target, format: oneDecimal)")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(Theme.red)
                        }
                }
                .chartYScale(domain: domain)
                .frame(height: 200)
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
