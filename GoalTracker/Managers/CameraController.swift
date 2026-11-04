import AVFoundation
import UIKit

enum CameraError: LocalizedError {
    case unavailable
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: "The camera isn't available on this device."
        case .captureFailed: "The photo couldn't be captured. Try again."
        }
    }
}

/// Owns the AVCaptureSession. All session work runs on a private serial queue, as AVFoundation requires.
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.bigsteve4288.goaltracker.camera")
    private let lock = NSLock()
    private var currentInput: AVCaptureDeviceInput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var pendingCapture: CheckedContinuation<UIImage, Error>?

    static var isAvailable: Bool { AVCaptureDevice.default(for: .video) != nil }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    func start(position: AVCaptureDevice.Position) async throws {
        try await onSessionQueue {
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            self.session.sessionPreset = .photo
            if !self.session.outputs.contains(self.photoOutput), self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            try self.useCamera(at: position)
        }
        queue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func switchCamera(to position: AVCaptureDevice.Position) async throws {
        try await onSessionQueue {
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            try self.useCamera(at: position)
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func capture() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.lock.withLock { self.pendingCapture = continuation }
                // Set rotation per shot: the connection doesn't exist yet while the session is first being configured.
                if let connection = self.photoOutput.connection(with: .video) {
                    let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
                    if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                }
                self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let continuation = lock.withLock {
            defer { pendingCapture = nil }
            return pendingCapture
        }
        if let error {
            continuation?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            continuation?.resume(returning: image)
        } else {
            continuation?.resume(throwing: CameraError.captureFailed)
        }
    }

    // MARK: - Session-queue helpers

    private func useCamera(at position: AVCaptureDevice.Position) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.unavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        if let currentInput { session.removeInput(currentInput) }
        guard session.canAddInput(input) else { throw CameraError.unavailable }
        session.addInput(input)
        currentInput = input
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)

        if let connection = photoOutput.connection(with: .video) {
            // Mirror front-camera shots so the saved photo matches what you saw on screen.
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
        }
    }

    private func onSessionQueue(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
