import AVFoundation
import CoreGraphics
import CoreImage
import ImageIO
import os

nonisolated struct SampledFrame: Sendable {
    let time: Double
    let image: CGImage
}

nonisolated enum FrameSamplerError: LocalizedError {
    case noVideoTrack
    case emptyVideo
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "That file doesn't contain a video track."
        case .emptyVideo: "That video is empty."
        case let .unreadable(reason): "Couldn't read frames from that video. (\(reason))"
        }
    }
}

/// Pulls evenly spaced still frames out of a walkthrough video, entirely on-device.
///
/// Tries `AVAssetImageGenerator` first; if that can't produce enough frames (some HDR/HEVC
/// captures and edited videos), it falls back to decoding the track with `AVAssetReader`.
nonisolated struct FrameSampler: Sendable {
    /// Seconds between samples for short videos.
    var interval: Double = 1.0
    /// Upper bound so long videos stay fast; spacing widens instead.
    var maxFrames: Int = 45
    var maxDimension: CGFloat = 1280

    static let log = Logger(subsystem: "com.rshamilton.stashlog", category: "FrameSampler")

    func sampleTimes(duration: Double) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        let step = max(interval, duration / Double(maxFrames))
        return Array(stride(from: min(0.2, duration / 2), to: duration, by: step))
    }

    @concurrent
    func frames(from url: URL) async throws -> [SampledFrame] {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw FrameSamplerError.noVideoTrack
        }
        let duration = try await asset.load(.duration).seconds
        let times = sampleTimes(duration: duration)
        guard !times.isEmpty else { throw FrameSamplerError.emptyVideo }
        Self.log.info("Sampling \(times.count) frames from \(duration, format: .fixed(precision: 1))s video")

        var lastError: Error?
        var frames = await generatorFrames(asset: asset, times: times, lastError: &lastError)
        try Task.checkCancellation()

        if frames.count < max(1, times.count / 2) {
            Self.log.error("Generator produced \(frames.count)/\(times.count) frames (\(String(describing: lastError))); falling back to AVAssetReader")
            do {
                let decoded = try await readerFrames(asset: asset, track: track, times: times)
                if decoded.count > frames.count { frames = decoded }
            } catch {
                lastError = error
                Self.log.error("AVAssetReader failed: \(String(describing: error))")
            }
        }

        guard !frames.isEmpty else {
            throw FrameSamplerError.unreadable(lastError?.localizedDescription ?? "unknown error")
        }
        return frames.sorted { $0.time < $1.time }
    }

    // MARK: - AVAssetImageGenerator

    func generatorFrames(asset: AVAsset, times: [Double], lastError: inout Error?) async -> [SampledFrame] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        var frames: [SampledFrame] = []
        let cmTimes = times.map { CMTime(seconds: $0, preferredTimescale: 600) }
        for await result in generator.images(for: cmTimes) {
            if Task.isCancelled { break }
            do {
                frames.append(SampledFrame(time: result.requestedTime.seconds, image: try result.image))
            } catch {
                lastError = error
            }
        }
        return frames
    }

    // MARK: - AVAssetReader fallback

    func readerFrames(asset: AVAsset, track: AVAssetTrack, times: [Double]) async throws -> [SampledFrame] {
        let transform = try await track.load(.preferredTransform)
        let orientation = Self.orientation(for: transform)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw FrameSamplerError.unreadable("reader output rejected") }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? FrameSamplerError.unreadable("reader failed to start")
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        var frames: [SampledFrame] = []
        var next = 0
        while next < times.count, let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); break }
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard t + 0.02 >= times[next], let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            while next < times.count, times[next] <= t + 0.02 { next += 1 }

            var image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
            let scale = min(1, maxDimension / max(image.extent.width, image.extent.height))
            if scale < 1 { image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
            if let cg = context.createCGImage(image, from: image.extent.integral) {
                frames.append(SampledFrame(time: t, image: cg))
            }
        }
        if reader.status == .failed { throw reader.error ?? FrameSamplerError.unreadable("decode failed") }
        return frames
    }

    /// Maps a video track's preferred transform to the image orientation that displays it upright.
    static func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a.rounded(), t.b.rounded(), t.c.rounded(), t.d.rounded()) {
        case (0, 1, -1, 0): .right       // portrait (home button / bottom down)
        case (0, -1, 1, 0): .left        // portrait upside down
        case (-1, 0, 0, -1): .down       // landscape, rotated 180°
        default: .up
        }
    }
}
