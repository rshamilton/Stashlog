import AVFoundation
import UIKit

nonisolated enum CameraError: LocalizedError {
    case unavailable
    case configurationFailed
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: "No camera is available on this device."
        case .configurationFailed: "The camera couldn't be set up."
        case .captureFailed: "The photo couldn't be taken. Try again."
        }
    }
}

/// A minimal back-camera photo pipeline tuned for rapid, one-item-per-tap capture.
/// All AVFoundation work happens on a private serial queue.
nonisolated final class CameraController: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.rshamilton.stashlog.camera")
    /// Guarded by `queue`.
    private var pending: [Int64: CheckedContinuation<Data, Error>] = [:]
    private var isConfigured = false

    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    /// Configures (once) and starts the session.
    func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    if !self.isConfigured { try self.configure() }
                    if !self.session.isRunning { self.session.startRunning() }
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.unavailable
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw CameraError.configurationFailed }
        session.addInput(input)
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .balanced
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90  // portrait; recorded in the photo's EXIF orientation
        }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            try? device.lockForConfiguration()
            device.focusMode = .continuousAutoFocus
            device.unlockForConfiguration()
        }
        isConfigured = true
    }

    /// Takes one photo and returns its encoded data (HEIC/JPEG with orientation metadata).
    func capture() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard self.session.isRunning else { cont.resume(throwing: CameraError.captureFailed); return }
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .speed
                self.pending[settings.uniqueID] = cont
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let id = photo.resolvedSettings.uniqueID
        let data = photo.fileDataRepresentation()
        queue.async {
            guard let cont = self.pending.removeValue(forKey: id) else { return }
            if let data { cont.resume(returning: data) } else { cont.resume(throwing: error ?? CameraError.captureFailed) }
        }
    }
}
