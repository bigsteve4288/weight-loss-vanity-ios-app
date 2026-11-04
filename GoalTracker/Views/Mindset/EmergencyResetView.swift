import SwiftData
import SwiftUI

/// Full-screen grounding experience for when cravings or food focus hit.
struct EmergencyResetView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var quotes: [SpiritualQuote]
    @Query(filter: #Predicate<ProgressPhoto> { $0.isBaseline == true }) private var baselines: [ProgressPhoto]

    @State private var startedAt = Date.now
    @State private var quote: SpiritualQuote?
    @State private var completedSteps: Set<Int> = []

    private let steps = [
        "Drink a full glass of water",
        "Name 5 things you can see right now",
        "Say your target weight out loud",
        "Pray or reflect in silence for 60 seconds",
        "Wait 10 minutes before deciding to eat",
    ]

    var body: some View {
        ZStack {
            Theme.black.ignoresSafeArea()
            if let data = baselines.first?.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .opacity(0.16)
                    .blur(radius: 6)
            }
            ScrollView {
                VStack(spacing: 28) {
                    Text("PAUSE. BREATHE. RESET.")
                        .font(.title2.weight(.black))
                        .tracking(2)
                        .foregroundStyle(Theme.goldGradient)
                        .padding(.top, 40)

                    BreathingGuide(startedAt: startedAt)

                    if let quote {
                        VStack(spacing: 8) {
                            Text("\u{201C}\(quote.text)\u{201D}")
                                .font(.title3.weight(.semibold))
                                .italic()
                                .multilineTextAlignment(.center)
                            Text(quote.source.uppercased())
                                .font(.caption.weight(.heavy))
                                .tracking(1.5)
                                .foregroundStyle(Theme.gold)
                        }
                        .padding(.horizontal)
                    }

                    GlassCard(accent: Theme.red) {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeader(title: "Ground Yourself", systemImage: "figure.mind.and.body")
                            ForEach(steps.indices, id: \.self) { index in
                                Button {
                                    if completedSteps.contains(index) { completedSteps.remove(index) } else { completedSteps.insert(index) }
                                } label: {
                                    Label(steps[index], systemImage: completedSteps.contains(index) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(completedSteps.contains(index) ? Theme.gold : .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .sensoryFeedback(.success, trigger: completedSteps.count)

                    Button { dismiss() } label: {
                        Text("I'M BACK IN CONTROL")
                            .font(.headline.weight(.black))
                            .tracking(1.5)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.goldGradient, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .padding(.bottom, 30)
                }
                .padding()
            }
        }
        .statusBarHidden()
        .onAppear {
            quote = quotes.filter(\.isFavorite).randomElement() ?? quotes.randomElement()
        }
    }
}

/// Box breathing: 4s in, 4s hold, 4s out, 4s hold.
struct BreathingGuide: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startedAt).truncatingRemainder(dividingBy: 16)
            let phase = Self.phase(at: elapsed)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.gold.opacity(0.55), Theme.red.opacity(0.12)], center: .center, startRadius: 10, endRadius: 140))
                    .scaleEffect(phase.scale)
                Circle()
                    .strokeBorder(Theme.goldGradient, lineWidth: 2)
                    .scaleEffect(phase.scale)
                Text(phase.label)
                    .font(.title3.weight(.heavy))
                    .tracking(2)
            }
            .frame(width: 240, height: 240)
        }
    }

    static func phase(at t: Double) -> (label: String, scale: Double) {
        let small = 0.55
        switch t {
        case ..<4: return ("BREATHE IN", small + (1 - small) * ease(t / 4))
        case ..<8: return ("HOLD", 1)
        case ..<12: return ("BREATHE OUT", 1 - (1 - small) * ease((t - 8) / 4))
        default: return ("HOLD", small)
        }
    }

    private static func ease(_ x: Double) -> Double { 0.5 - cos(x * .pi) / 2 }
}
