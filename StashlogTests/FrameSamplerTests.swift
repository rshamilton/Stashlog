import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import Stashlog

/// Writes a short portrait-tagged H.264 video, like an iPhone capture (landscape pixels +
/// a 90° preferred transform), so both sampling paths are exercised on real files.
private func makeTestVideo(seconds: Int = 3, fps: Int32 = 30) async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
    let width = 320, height = 240
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    input.transform = CGAffineTransform(rotationAngle: .pi / 2)  // portrait, as the camera records
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    #expect(writer.startWriting())
    writer.startSession(atSourceTime: .zero)

    for frame in 0..<(seconds * Int(fps)) {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        let pb = try #require(buffer)
        CVPixelBufferLockBaseAddress(pb, [])
        let shade = UInt8(frame * 255 / (seconds * Int(fps)))
        memset(CVPixelBufferGetBaseAddress(pb), Int32(shade), CVPixelBufferGetDataSize(pb))
        CVPixelBufferUnlockBaseAddress(pb, [])
        adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
    }
    input.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
    return url
}

struct FrameSamplerTests {
    @Test func samplesFramesFromRealVideo() async throws {
        let url = try await makeTestVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = try await FrameSampler().frames(from: url)
        #expect(frames.count >= 3)
        // Portrait transform must be applied: frames come out taller than wide.
        let first = try #require(frames.first)
        #expect(first.image.height > first.image.width)
    }

    @Test func readerFallbackDecodesUpright() async throws {
        let url = try await makeTestVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let sampler = FrameSampler()
        let frames = try await sampler.readerFrames(asset: asset, track: track, times: sampler.sampleTimes(duration: 3))
        #expect(frames.count >= 3)
        let first = try #require(frames.first)
        #expect(first.image.height > first.image.width)
    }

    @Test func nonVideoFileGivesClearError() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try Data("not a video".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: (any Error).self) { try await FrameSampler().frames(from: url) }
    }

    @Test func orientationFromTransform() {
        #expect(FrameSampler.orientation(for: CGAffineTransform(rotationAngle: .pi / 2)) == .right)
        #expect(FrameSampler.orientation(for: .identity) == .up)
        #expect(FrameSampler.orientation(for: CGAffineTransform(rotationAngle: .pi)) == .down)
    }
}

@MainActor
struct ScanSessionTests {
    /// A scan started by the session must run to a terminal state on its own,
    /// without any view keeping a task alive.
    @Test func videoScanRunsToCompletion() async throws {
        let url = try await makeTestVideo()
        let session = ScanSession()
        session.start(.video(url))
        session.start(.video(url))  // second call must be a no-op
        let deadline = Date.now.addingTimeInterval(60)
        while session.isRunning, Date.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(session.phase == .finished)
        #expect(!FileManager.default.fileExists(atPath: url.path))  // temp video cleaned up
    }

    @Test func cancelStopsTheScan() async throws {
        let url = try await makeTestVideo()
        let session = ScanSession()
        session.start(.video(url))
        session.cancel()
        let deadline = Date.now.addingTimeInterval(30)
        while session.isRunning, Date.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(session.phase == .cancelled)
    }
}
