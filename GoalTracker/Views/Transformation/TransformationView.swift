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
    @State private var nowPhotoID: PersistentIdentifier?
    @State private var photoPendingDelete: ProgressPhoto?
    @State private var editingPhoto: ProgressPhoto?
    /// Which slot a new photo goes into.
    enum PhotoSlot: String, Identifiable {
        case baseline, progress
        var id: Self { self }
    }

    @State private var pickedItem: PhotosPickerItem?
    @State private var isShowingLibrary = false
    @State private var librarySlot = PhotoSlot.progress
    @State private var cameraSlot: PhotoSlot?
    @State private var isShowingCoach = false

    private var baseline: ProgressPhoto? { photos.first(where: \.isBaseline) }
    private var latest: ProgressPhoto? { photos.nowPhoto(selected: nowPhotoID) }
    private var thenPhoto: ProgressPhoto? { photos.thenPhoto(selected: thenPhotoID) }

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

                        Button { isShowingCoach = true } label: {
                            Label("GET THE COACH'S VERDICT", systemImage: "flame.fill")
                                .font(.headline.weight(.black))
                                .tracking(1.2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.redGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        photoStrip
                    }
                    pickerButtons
                }
                .padding()
            }
            .background(ThemedBackground())
            .navigationTitle("Transformation")
            .toolbar {
                Button("AI Coach", systemImage: "flame.fill") { isShowingCoach = true }
            }
            .sheet(isPresented: $isShowingCoach) {
                CoachView(thenPhotoID: $thenPhotoID, nowPhotoID: $nowPhotoID)
            }
            .overlay {
                if viewModel.isImporting {
                    ProgressView().controlSize(.large)
                }
            }
            .photosPicker(isPresented: $isShowingLibrary, selection: $pickedItem, matching: .images)
            .onChange(of: pickedItem) { _, item in importItem(item, into: librarySlot) }
            .fullScreenCover(item: $cameraSlot) { slot in
                TimedCameraView(ghostImageData: slot == .progress ? thenPhoto?.imageData : latest?.imageData) { image in
                    saveCaptured(image, into: slot)
                }
            }
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
            CardHeader(title: "Your Photos", systemImage: "photo.stack")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos.reversed()) { photo in
                        Menu {
                            Button("Use as THEN", systemImage: "clock.arrow.circlepath") { thenPhotoID = photo.persistentModelID }
                            Button("Use as NOW", systemImage: "camera") { nowPhotoID = photo.persistentModelID }
                            Button("Edit Date & Weight…", systemImage: "calendar") { editingPhoto = photo }
                            if !photo.isBaseline {
                                Button("Make Baseline", systemImage: "star") { viewModel.makeBaseline(photo, among: photos) }
                            }
                            Divider()
                            Button("Delete Photo", systemImage: "trash", role: .destructive) { photoPendingDelete = photo }
                        } label: {
                            thumbnail(for: photo)
                        }
                    }
                }
            }
            Text("Tap a photo to use it as THEN or NOW, make it your baseline, or delete it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .sheet(item: $editingPhoto) { PhotoDetailsEditor(photo: $0) }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: Binding(get: { photoPendingDelete != nil }, set: { if !$0 { photoPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Photo", role: .destructive) {
                if let photo = photoPendingDelete { context.delete(photo) }
                photoPendingDelete = nil
            }
        } message: {
            Text(photoPendingDelete?.isBaseline == true ? "This is your baseline. Notifications and Emergency Reset will stop showing it until you set a new one." : "This can't be undone.")
        }
    }

    private func thumbnail(for photo: ProgressPhoto) -> some View {
        let role = photo == thenPhoto ? "THEN" : photo == latest ? "NOW" : nil
        return PhotoImage(photo: photo)
            .frame(width: 64, height: 86)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(role == nil ? .clear : (role == "THEN" ? Theme.gold : Theme.red), lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if photo.isBaseline {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.gold).padding(4)
                }
            }
            .overlay(alignment: .bottom) {
                if let role {
                    Text(role)
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.7), in: Capsule())
                        .foregroundStyle(role == "THEN" ? Theme.gold : Theme.red)
                        .padding(.bottom, 4)
                }
            }
    }

    private var pickerButtons: some View {
        let baselineTitle = baseline == nil ? "Add Baseline" : "New Baseline"
        return HStack(spacing: 12) {
            photoMenu(baselineTitle, systemImage: "star.square.fill", slot: .baseline)
                .buttonStyle(.bordered)
            photoMenu("Add Progress", systemImage: "camera.fill", slot: .progress)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
    }

    private func photoMenu(_ title: String, systemImage: String, slot: PhotoSlot) -> some View {
        Menu {
            if CameraController.isAvailable {
                Button("Take Photo", systemImage: "camera.fill") { cameraSlot = slot }
            }
            Button("Choose from Library", systemImage: "photo.on.rectangle") {
                librarySlot = slot
                isShowingLibrary = true
            }
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
    }

    private func saveCaptured(_ image: UIImage, into slot: PhotoSlot) {
        viewModel.saveCapturedPhoto(image, asBaseline: slot == .baseline, weight: health.latestWeightLbs, existing: photos, context: context)
        if slot == .progress { nowPhotoID = nil }
    }

    private func importItem(_ item: PhotosPickerItem?, into slot: PhotoSlot) {
        guard let item else { return }
        Task {
            await viewModel.importPhoto(from: item, asBaseline: slot == .baseline, weight: health.latestWeightLbs, existing: photos, context: context)
            if slot == .progress { nowPhotoID = nil }
            pickedItem = nil
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
