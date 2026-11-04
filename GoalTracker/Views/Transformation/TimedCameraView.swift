import AudioToolbox
import AVFoundation
import SwiftUI

/// Full-screen camera with a self-timer so the phone can be propped up for a full-body shot.
struct TimedCameraView: View {
    /// Shown faintly over the live preview to line up pose and distance.
    let ghostImageData: Data?
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("cameraTimer") private var timerSeconds = 0
    @AppStorage("cameraUsesFront") private var usesFront = true
    @AppStorage("cameraShowsGhost") private var showsGhost = true

    @State private var camera = CameraController()
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var captured: UIImage?
    @State private var isFlashing = false
    @State private var errorMessage: String?
    @State private var isAccessDenied = false

    private static let timerOptions = [0, 3, 5, 10]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let captured {
                review(captured)
            } else {
                liveCamera
            }
            Color.white
                .ignoresSafeArea()
                .opacity(isFlashing ? 0.85 : 0)
                .allowsHitTesting(false)
        }
        .statusBarHidden()
        .task { await startCamera() }
        .onDisappear {
            countdownTask?.cancel()
            camera.stop()
        }
    }

    // MARK: - Live camera

    private var liveCamera: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            if showsGhost, let data = ghostImageData, let ghost = UIImage(data: data) {
                Image(uiImage: ghost)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .opacity(0.28)
                    .allowsHitTesting(false)
            }

            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 180, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.goldGradient)
                    .shadow(color: .black.opacity(0.8), radius: 20)
                    .contentTransition(.numericText(countsDown: true))
            }

            VStack {
                topBar
                Spacer()
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                if countdown == nil {
                    Text(timerSeconds == 0 ? "Turn on the timer to prop the phone up for a full-body shot." : "Prop the phone up, step back, and fit head to feet in the frame.")
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.horizontal)
                    timerPicker
                }
                shutterButton
                    .padding(.bottom, 24)
            }
        }
    }

    private var topBar: some View {
        HStack {
            circleButton("xmark") { dismiss() }
            Spacer()
            if ghostImageData != nil {
                circleButton(showsGhost ? "person.crop.rectangle.fill" : "person.crop.rectangle", highlighted: showsGhost) {
                    showsGhost.toggle()
                }
                .accessibilityLabel(showsGhost ? "Hide ghost overlay" : "Show ghost overlay")
            }
            circleButton("arrow.triangle.2.circlepath.camera") { flipCamera() }
                .accessibilityLabel("Switch camera")
                .disabled(countdown != nil)
        }
        .padding()
    }

    private var timerPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer").foregroundStyle(Theme.gold)
            ForEach(Self.timerOptions, id: \.self) { seconds in
                Button {
                    timerSeconds = seconds
                } label: {
                    Text(seconds == 0 ? "Off" : "\(seconds)s")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(timerSeconds == seconds ? Theme.gold : Color.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(timerSeconds == seconds ? .black : .white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }

    private var shutterButton: some View {
        Button(action: shutterTapped) {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 5).frame(width: 84, height: 84)
                if countdown != nil {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.red).frame(width: 32, height: 32)
                } else {
                    Circle().fill(Theme.goldGradient).frame(width: 68, height: 68)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(countdown != nil ? "Cancel timer" : "Take photo")
        .disabled(errorMessage != nil && isAccessDenied)
    }

    private func circleButton(_ symbol: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.55), in: Circle())
                .foregroundStyle(highlighted ? Theme.gold : .white)
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text(message).font(.subheadline).multilineTextAlignment(.center)
            if isAccessDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    // MARK: - Review

    private func review(_ image: UIImage) -> some View {
        VStack(spacing: 20) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal)
            HStack(spacing: 14) {
                Button {
                    captured = nil
                } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    onCapture(image)
                    dismiss()
                } label: {
                    Label("Use Photo", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    private func startCamera() async {
        guard await CameraController.requestAccess() else {
            isAccessDenied = true
            errorMessage = "Camera access is off. Turn it on in Settings → Vanity → Camera."
            return
        }
        do {
            try await camera.start(position: usesFront ? .front : .back)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func flipCamera() {
        usesFront.toggle()
        Task {
            do {
                try await camera.switchCamera(to: usesFront ? .front : .back)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func shutterTapped() {
        if countdown != nil {
            countdownTask?.cancel()
            countdown = nil
            return
        }
        countdownTask = Task {
            for remaining in stride(from: timerSeconds, through: 1, by: -1) {
                withAnimation(.snappy) { countdown = remaining }
                AudioServicesPlaySystemSound(1104)
                UIImpactFeedbackGenerator(style: remaining <= 3 ? .heavy : .light).impactOccurred()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            countdown = nil
            await takePhoto()
        }
    }

    private func takePhoto() async {
        do {
            let image = try await camera.capture()
            withAnimation(.easeOut(duration: 0.08)) { isFlashing = true }
            withAnimation(.easeIn(duration: 0.35).delay(0.08)) { isFlashing = false }
            captured = image
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
