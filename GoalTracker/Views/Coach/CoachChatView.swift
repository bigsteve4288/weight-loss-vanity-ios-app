import SwiftData
import SwiftUI

/// Ask the Coach: a conversation about the user's own progress, answered from their Health data.
struct CoachChatView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitManager.self) private var health
    @Query private var profiles: [GoalProfile]
    @Query(sort: \CoachMessage.date) private var messages: [CoachMessage]
    @AppStorage("coachTone") private var toneRaw = CoachTone.supportive.rawValue

    @State private var viewModel = CoachChatViewModel()
    @State private var access = CoachViewModel()
    @State private var codeDraft = ""
    @State private var isConfirmingClear = false
    @FocusState private var isComposing: Bool

    /// Shown as a sheet from the dashboard; pushed inside AI Coach, which has its own Done button.
    var showsDoneButton = true

    private var tone: Binding<CoachTone> {
        Binding { CoachTone(rawValue: toneRaw) ?? .supportive } set: { toneRaw = $0.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Picker("Tone", selection: tone) {
                            ForEach(CoachTone.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 4)

                        if !access.hasAPIKey {
                            accessCard
                        } else if messages.isEmpty {
                            intro
                        }

                        ForEach(messages) { message in
                            ChatBubble(message: message)
                                .id(message.persistentModelID)
                        }

                        if viewModel.isSending {
                            HStack(spacing: 8) {
                                ProgressView().tint(Theme.gold)
                                Text("Coach is checking your numbers…").font(.caption).foregroundStyle(.secondary)
                            }
                            .id("sending")
                        }
                        if let error = viewModel.errorMessage {
                            Text(error).font(.caption).foregroundStyle(Theme.red)
                        }
                        if access.hasAPIKey, !messages.isEmpty, !viewModel.isSending {
                            suggestionChips
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) {
                    withAnimation { proxy.scrollTo(messages.last?.persistentModelID, anchor: .bottom) }
                }
                .onChange(of: viewModel.isSending) { _, sending in
                    if sending { withAnimation { proxy.scrollTo("sending", anchor: .bottom) } }
                }
            }

            if access.hasAPIKey {
                composer
            }
        }
        .background(ThemedBackground())
        .navigationTitle("Ask the Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            if !messages.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", systemImage: "trash") { isConfirmingClear = true }
                        .disabled(viewModel.isSending)
                }
            }
        }
        .confirmationDialog("Clear this conversation?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear Conversation", role: .destructive) { viewModel.clear(messages, context: context) }
        } message: {
            Text("It's deleted from this iPhone. Your Health data isn't affected.")
        }
    }

    // MARK: - Pieces

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    CardHeader(title: "Ask About Your Progress", systemImage: "bubble.left.and.text.bubble.right.fill")
                    Text("The coach answers from your Apple Health data: weigh-ins, logged food, workouts and your goal. If something isn't recorded, it'll tell you rather than guess.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Each question sends a summary of your stats (never photos) to Anthropic's API. Health history is included only if you turned that on in Goal Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            suggestionChips
        }
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CoachChatViewModel.suggestions, id: \.self) { suggestion in
                    Button(suggestion) { ask(suggestion) }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.gold.opacity(0.12), in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.4), lineWidth: 1))
                        .foregroundStyle(Theme.goldLight)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about your progress…", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($isComposing)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .submitLabel(.send)
                .onSubmit { ask(viewModel.draft) }
            Button {
                ask(viewModel.draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.goldGradient)
            }
            .disabled(viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var accessCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Connect the Coach", systemImage: "key.fill")
                Text("Enter the coach access code you were given. It's stored in this iPhone's Keychain only.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("Access code", text: $codeDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                Button("Save") {
                    access.saveAPIKey(codeDraft)
                    codeDraft = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(codeDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func ask(_ question: String) {
        isComposing = false
        Task {
            await viewModel.send(question, tone: tone.wrappedValue, profile: profiles.first, health: health, conversation: messages, context: context)
        }
    }
}

private struct ChatBubble: View {
    let message: CoachMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? AnyShapeStyle(Theme.red.opacity(0.35)) : AnyShapeStyle(Color.white.opacity(0.07)),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isUser ? Theme.red.opacity(0.5) : Theme.gold.opacity(0.25), lineWidth: 1)
                }
            if !isUser { Spacer(minLength: 40) }
        }
        .accessibilityLabel("\(isUser ? "You" : "Coach"): \(message.text)")
    }
}
