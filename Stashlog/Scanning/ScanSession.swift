import CoreGraphics
import Foundation
import Observation

/// Drives one scan (a walkthrough video or a set of photos) through detection and aggregation.
@Observable
final class ScanSession {
    enum Phase: Equatable {
        case idle
        case extractingFrames
        case detecting(done: Int, total: Int)
        case finished
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    var candidates: [ScanCandidate] = []

    private let sampler = FrameSampler()
    private let detector = ItemDetector()
    private let aggregator = ScanAggregator()

    var progress: Double {
        switch phase {
        case .idle: 0
        case .extractingFrames: 0.05
        case let .detecting(done, total): 0.1 + 0.9 * Double(done) / Double(max(total, 1))
        case .finished, .failed: 1
        }
    }

    func scanVideo(at url: URL) async {
        phase = .extractingFrames
        do {
            let frames = try await sampler.frames(from: url)
            await detect(frames)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func scanImages(_ images: [CGImage]) async {
        await detect(images.enumerated().map { SampledFrame(time: Double($0.offset), image: $0.element) })
    }

    private func detect(_ frames: [SampledFrame]) async {
        var detections: [Detection] = []
        for (index, frame) in frames.enumerated() {
            if Task.isCancelled { phase = .idle; return }
            phase = .detecting(done: index, total: frames.count)
            detections += await detector.detect(in: frame.image, frameTime: frame.time)
        }
        candidates = aggregator.aggregate(detections)
        phase = .finished
    }
}
