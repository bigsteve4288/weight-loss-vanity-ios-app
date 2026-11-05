import SwiftUI

private let oneDecimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))

/// The dashboard at a glance: today's verdict and the goal trajectory side by side (kept separate,
/// as everywhere else), the three numbers that matter, and the one next action.
struct TodaySummaryCard: View {
    let snapshot: TargetSnapshot
    var onLogWeight: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        let action = NextActionAdvisor.advise(snapshot)
        GlassCard(accent: snapshot.status.color) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    pill("TODAY", snapshot.status.title, color: snapshot.status.color)
                    pill("PACE", snapshot.pace.status.title, color: snapshot.pace.status.color)
                }

                HStack(alignment: .firstTextBaseline) {
                    stat(snapshot.currentWeight.map { $0.formatted(oneDecimal) } ?? "—", unit: "lb", caption: "current")
                    Spacer()
                    stat(snapshot.poundsRemaining.formatted(oneDecimal), unit: "lb", caption: "to go", color: Theme.red)
                    Spacer()
                    stat(snapshot.daysRemaining >= 0 ? "\(snapshot.daysRemaining)" : "—", unit: snapshot.daysRemaining == 1 ? "day" : "days", caption: "left")
                }

                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: snapshot.progress)
                        .tint(Theme.gold)
                        .accessibilityLabel("Progress toward goal")
                    HStack {
                        Text("\(snapshot.progress.formatted(.percent.precision(.fractionLength(0)))) complete")
                        Spacer()
                        if let projection = snapshot.projectionSummary {
                            Text(projection)
                        }
                    }
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }

                let gaps = snapshot.dataGaps
                if !gaps.isEmpty {
                    Label(gaps.joined(separator: " · "), systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Data limits: \(gaps.joined(separator: ", "))")
                }

                Divider().overlay(Theme.gold.opacity(0.3))

                nextAction(action)
            }
        }
    }

    private func pill(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value).foregroundStyle(color)
        }
        .font(.caption2.weight(.heavy))
        .tracking(0.8)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, unit: String, caption: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .black).monospacedDigit())
                    .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Theme.goldGradient))
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            Text(caption.uppercased())
                .font(.caption2.weight(.heavy))
                .tracking(1)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func nextAction(_ action: NextAction) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: action.symbol)
                .font(.title3)
                .foregroundStyle(Theme.gold)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(action.title)
                    .font(.subheadline.weight(.bold))
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            switch action.kind {
            case .logWeight:
                actionButton("Log", systemImage: "plus", action: onLogWeight)
            case .openGoalSettings:
                actionButton("Open", systemImage: "gearshape.fill", action: onOpenSettings)
            case .logFood, .reflect, .none:
                EmptyView()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.heavy))
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.red)
        .controlSize(.small)
    }
}
