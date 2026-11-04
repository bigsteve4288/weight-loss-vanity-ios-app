import PhotosUI
import SwiftData
import SwiftUI

struct TransformationView: View {
    enum CompareMode: String, CaseIterable, Identifiable {
        case sideBySide = "Side by Side"
        case overlay = "Overlay"
        var id: Self { self }
    }

    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Query(sort: \ProgressPhoto.date) private var photos: [ProgressPhoto]

    @State private var viewModel = TransformationViewModel()
    @State private var mode = CompareMode.sideBySide
    @State private var overlayAmount = 0.5
    @State private var thenPhotoID: PersistentIdentifier?
    @State private var baselineItem: PhotosPickerItem?
    @State private var progressItem: PhotosPickerItem?

    private var baseline: ProgressPhoto? { photos.first(where: \.isBaseline) }
    private var latest: ProgressPhoto? { photos.last(where: { !$0.isBaseline }) }
    private var thenPhoto: ProgressPhoto? {
        photos.first(where: { $0.persistentModelID == thenPhotoID }) ?? baseline
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if photos.isEmpty {
                        ContentUnavailableView(
                            "Anchor Your Transformation",
                            systemImage: "person.crop.rectangle.badge.plus",
                            description: Text("Add a baseline \u{201C}Then\u{201D} photo. It becomes your lock-screen reminder.")
                        )
                        .padding(.top, 40)
                    } else {
                        Picker("Mode", selection: $mode) {
                            ForEach(CompareMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        switch mode {
                        case .sideBySide:
                            HStack(spacing: 10) {
                                PhotoPanel(photo: thenPhoto, label: "THEN")
                                PhotoPanel(photo: latest, label: "NOW")
                            }
                        case .overlay:
                            overlayComparison
                        }

                        photoStrip
                    }
                    pickerButtons
                }
                .padding()
            }
            .background(ThemedBackground())
            .navigationTitle("Transformation")
            .overlay {
                if viewModel.isImporting {
                    ProgressView().controlSize(.large)
                }
            }
            .onChange(of: baselineItem) { _, item in importItem(item, asBaseline: true) }
            .onChange(of: progressItem) { _, item in importItem(item, asBaseline: false) }
            .alert("Photo Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var overlayComparison: some View {
        VStack(spacing: 12) {
            Color.clear
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    ZStack {
                        PhotoImage(photo: latest)
                        PhotoImage(photo: thenPhoto).opacity(overlayAmount)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.goldGradient, lineWidth: 1)
                }
            GlassCard {
                VStack(spacing: 6) {
                    HStack {
                        Text("NOW").font(.caption.weight(.heavy))
                        Slider(value: $overlayAmount, in: 0...1)
                        Text("THEN").font(.caption.weight(.heavy))
                    }
                    Text("Then opacity \(overlayAmount.formatted(.percent.precision(.fractionLength(0))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var photoStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "Choose the Then photo", systemImage: "clock.arrow.circlepath")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos) { photo in
                        Button {
                            thenPhotoID = photo.persistentModelID
                        } label: {
                            PhotoImage(photo: photo)
                                .frame(width: 64, height: 86)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(photo == thenPhoto ? Theme.gold : .clear, lineWidth: 2)
                                }
                                .overlay(alignment: .topTrailing) {
                                    if photo.isBaseline {
                                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.gold).padding(4)
                                    }
                                }
                        }
                        .contextMenu {
                            Button("Set as Baseline", systemImage: "star") { viewModel.makeBaseline(photo, among: photos) }
                            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(photo) }
                        }
                    }
                }
            }
            Text("Long-press a photo to set it as the baseline or delete it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var pickerButtons: some View {
        let baselineTitle = baseline == nil ? "Add Baseline" : "New Baseline"
        return HStack(spacing: 12) {
            PhotosPicker(selection: $baselineItem, matching: .images) {
                Label(baselineTitle, systemImage: "star.square.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            PhotosPicker(selection: $progressItem, matching: .images) {
                Label("Add Progress", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
    }

    private func importItem(_ item: PhotosPickerItem?, asBaseline: Bool) {
        guard let item else { return }
        Task {
            await viewModel.importPhoto(from: item, asBaseline: asBaseline, weight: health.latestWeightLbs, existing: photos, context: context)
            baselineItem = nil
            progressItem = nil
        }
    }
}

struct PhotoImage: View {
    let photo: ProgressPhoto?

    var body: some View {
        if let photo, let image = UIImage(data: photo.imageData) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Color.white.opacity(0.05)
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
    }
}

struct PhotoPanel: View {
    let photo: ProgressPhoto?
    let label: String

    var body: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay { PhotoImage(photo: photo) }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.goldGradient, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.caption.weight(.black))
                    .tracking(1.5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(Theme.gold)
                    .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                if let photo {
                    VStack(alignment: .leading) {
                        Text(photo.date, format: .dateTime.month().day().year())
                        if let weight = photo.weightLbs {
                            Text("\(weight, format: .number.precision(.fractionLength(1))) lb")
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(6)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                }
            }
    }
}
