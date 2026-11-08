import CoreGraphics
import Foundation
import Observation

/// What a scan reads from.
enum ScanInput {
    case video(URL)
    case photos([CGImage])
}

/// Drives one scan (a walkthrough video or a set of photos) through detection and aggregation.
///
/// The session owns its own task, so the scan keeps running even if SwiftUI rebuilds the
/// review sheet (which happens when it's presented while the camera is still dismissing).
/// Only `cancel()` stops it.
@Observable
final class ScanSession: Identifiable {
    enum Phase: Equatable {
        case starting
        case extractingFrames
        case detecting(done: Int, total: Int)
        case finished
        case failed(String)
        case cancelled
    }

    let id = UUID()
    private(set) var phase: Phase = .starting
    var candidates: [ScanCandidate] = []

    @ObservationIgnored private var task: Task<Void, Never>?
    private let sampler = FrameSampler()
    private let detector = ItemDetector()
    private let aggregator = ScanAggregator()

    var isRunning: Bool {
        switch phase {
        case .starting, .extractingFrames, .detecting: true
        default: false
        }
    }

    var progress: Double {
        switch phase {
        case .starting: 0
        case .extractingFrames: 0.05
        case let .detecting(done, total): 0.1 + 0.9 * Double(done) / Double(max(total, 1))
        case .finished, .failed, .cancelled: 1
        }
    }

    /// Starts the scan once. Calling again is a no-op.
    func start(_ input: ScanInput) {
        guard task == nil else { return }
        task = Task {
            switch input {
            case let .video(url):
                await scanVideo(at: url)
                try? FileManager.default.removeItem(at: url)
            case let .photos(images):
                await detect(images.enumerated().map { SampledFrame(time: Double($0.offset), image: $0.element) })
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func scanVideo(at url: URL) async {
        phase = .extractingFrames
        do {
            let frames = try await sampler.frames(from: url)
            try Task.checkCancellation()
            await detect(frames)
        } catch is CancellationError {
            phase = .cancelled
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func detect(_ frames: [SampledFrame]) async {
        var detections: [Detection] = []
        for (index, frame) in frames.enumerated() {
            if Task.isCancelled { phase = .cancelled; return }
            phase = .detecting(done: index, total: frames.count)
            detections += await detector.detect(in: frame.image, frameTime: frame.time)
        }
        candidates = aggregator.aggregate(detections)
        phase = .finished
    }
}
