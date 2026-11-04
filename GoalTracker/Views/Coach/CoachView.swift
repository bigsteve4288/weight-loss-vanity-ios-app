import SwiftData
import SwiftUI

struct CoachView: View {
    let thenPhoto: ProgressPhoto?
    let nowPhoto: ProgressPhoto?
    /// Saves a freshly taken progress photo, which then becomes `nowPhoto`.
    let onNewNowPhoto: (UIImage) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitManager.self) private var health
    @Query private var profiles: [GoalProfile]
    @Query(sort: \CoachCritique.date, order: .reverse) private var critiques: [CoachCritique]

    @State private var viewModel = CoachViewModel()
    @State private var keyDraft = ""
    @State private var isShowingCamera = false
    @AppStorage("coachTone") private var toneRaw = CoachTone.drillSergeant.rawValue

    private var tone: Binding<CoachTone> {
        Binding { CoachTone(rawValue: toneRaw) ?? .drillSergeant } set: { toneRaw = $0.rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if viewModel.hasAPIKey {
                        requestCard
                    } else {
                        apiKeyCard
                    }
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let latest = critiques.first {
                        CritiqueCard(critique: latest)
                    }
                    if critiques.count > 1 {
                        historyCard
                    }
                    footer
                }
                .padding()
            }
            .background(ThemedBackground())
            .navigationTitle("AI Coach")
            .fullScreenCover(isPresented: $isShowingCamera) {
                TimedCameraView(ghostImageData: thenPhoto?.imageData, onCapture: onNewNowPhoto)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var requestCard: some View {
        GlassCard(accent: Theme.red) {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Get the Verdict", systemImage: "flame.fill")
                Picker("Tone", selection: tone) {
                    ForEach(CoachTone.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    PhotoPanel(photo: thenPhoto, label: "THEN")
                    PhotoPanel(photo: nowPhoto, label: "NOW")
                }
                .frame(maxHeight: 200)

                if CameraController.isAvailable {
                    Button {
                        isShowingCamera = true
                    } label: {
                        Label("Take New NOW Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoading)
                }

                Button {
                    guard let thenPhoto, let nowPhoto else { return }
                    Task {
                        await viewModel.requestVerdict(
                            then: thenPhoto, now: nowPhoto, tone: tone.wrappedValue,
                            profile: profiles.first, health: health, previous: critiques.first, context: context
                        )
                    }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView().tint(.black)
                            Text("COACH IS LOOKING…")
                        } else {
                            Image(systemName: "eye.trianglebadge.exclamationmark")
                            Text("HIT ME WITH IT")
                        }
                    }
                    .font(.headline.weight(.black))
                    .tracking(1.2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.goldGradient, in: Capsule())
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(thenPhoto == nil || nowPhoto == nil || viewModel.isLoading)
                .opacity(thenPhoto == nil || nowPhoto == nil ? 0.4 : 1)

                if thenPhoto == nil || nowPhoto == nil {
                    Text("Add a baseline and at least one progress photo first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var apiKeyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Connect the Coach", systemImage: "key.fill")
                Text("The AI Coach uses Claude. Create an API key at console.anthropic.com → API Keys, then paste it here. It's stored in this iPhone's Keychain only.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("sk-ant-…", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                Button("Save Key") {
                    viewModel.saveAPIKey(keyDraft)
                    keyDraft = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var historyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Past Verdicts", systemImage: "clock.arrow.circlepath")
                ForEach(critiques.dropFirst()) { critique in
                    NavigationLink {
                        ScrollView { CritiqueCard(critique: critique).padding() }
                            .background(ThemedBackground())
                    } label: {
                        HStack(spacing: 12) {
                            GradeBadge(grade: critique.grade, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(critique.headline).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text(critique.date, format: .dateTime.month().day().year())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { context.delete(critique) }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text("Both photos and your stats are sent to Anthropic's API for each verdict. Nothing is sent until you tap the button.")
            if viewModel.hasAPIKey {
                Button("Remove API Key", role: .destructive) { viewModel.removeAPIKey() }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
}

struct CritiqueCard: View {
    let critique: CoachCritique

    var body: some View {
        GlassCard(accent: gradeColor(critique.grade)) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    GradeBadge(grade: critique.grade, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(critique.headline)
                            .font(.system(.title3, design: .rounded, weight: .black))
                        Text("\(critique.tone.label) · \(critique.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                section("What I See", "eye.fill", critique.observations)
                VStack(alignment: .leading, spacing: 6) {
                    CardHeader(title: "Since Then", systemImage: "arrow.left.arrow.right")
                    Text(critique.progressSinceThen).font(.subheadline)
                }
                section("Fix This", "wrench.and.screwdriver.fill", critique.focusAreas)
                section("Orders for Today", "checklist", critique.ordersForToday, numbered: true)
            }
        }
    }

    private func section(_ title: String, _ symbol: String, _ items: [String], numbered: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: title, systemImage: symbol)
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(numbered ? "\(index + 1)." : "•")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(numbered ? Theme.gold : Theme.red)
                    Text(items[index]).font(.subheadline)
                }
            }
        }
    }
}

struct GradeBadge: View {
    let grade: String
    let size: CGFloat

    var body: some View {
        Text(grade)
            .font(.system(size: size * 0.55, weight: .black, design: .rounded))
            .frame(width: size, height: size)
            .background(gradeColor(grade).opacity(0.18), in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).strokeBorder(gradeColor(grade), lineWidth: 1.5)
            }
            .foregroundStyle(gradeColor(grade))
    }
}

private func gradeColor(_ grade: String) -> Color {
    switch grade {
    case "A", "B": Theme.gold
    case "C": .orange
    default: Theme.red
    }
}
