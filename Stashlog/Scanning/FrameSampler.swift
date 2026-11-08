import AVFoundation
import CoreGraphics

nonisolated struct SampledFrame: Sendable {
    let time: Double
    let image: CGImage
}

/// Pulls evenly spaced still frames out of a walkthrough video, entirely on-device.
nonisolated struct FrameSampler: Sendable {
    /// Seconds between samples for short videos.
    var interval: Double = 0.75
    /// Upper bound so long videos stay fast; spacing widens instead.
    var maxFrames: Int = 90
    var maxDimension: CGFloat = 1280

    func sampleTimes(duration: Double) -> [Double] {
        guard duration > 0 else { return [] }
        let step = max(interval, duration / Double(maxFrames))
        return Array(stride(from: min(0.2, duration / 2), to: duration, by: step))
    }

    @concurrent
    func frames(from url: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> [SampledFrame] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let times = sampleTimes(duration: duration)
        guard !times.isEmpty else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        let tolerance = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        var frames: [SampledFrame] = []
        frames.reserveCapacity(times.count)
        let cmTimes = times.map { CMTime(seconds: $0, preferredTimescale: 600) }
        for await result in generator.images(for: cmTimes) {
            try Task.checkCancellation()
            if let image = try? result.image {
                frames.append(SampledFrame(time: result.requestedTime.seconds, image: image))
            }
            progress?(Double(frames.count) / Double(cmTimes.count))
        }
        return frames.sorted { $0.time < $1.time }
    }
}
