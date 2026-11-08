import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// One thing spotted in one frame.
nonisolated struct Detection: Sendable {
    let identifier: String
    let entry: CatalogEntry
    let confidence: Float
    let frameTime: Double
    /// JPEG of the cropped region, for the review screen and the item photo.
    let thumbnail: Data?
}

/// Finds insurable objects in a still image using only on-device Vision requests:
/// objectness saliency proposes regions, then each region (plus the whole frame) is classified.
nonisolated struct ItemDetector: Sendable {
    var regionConfidence: Float = 0.30
    var frameConfidence: Float = 0.55
    var maxRegions = 6

    @concurrent
    func detect(in image: CGImage, frameTime: Double = 0) async -> [Detection] {
        let size = CGSize(width: image.width, height: image.height)
        var detections: [Detection] = []

        // 1. Salient object regions → classify each crop, keep its best catalog hit.
        let saliency = try? await GenerateObjectnessBasedSaliencyImageRequest().perform(on: image)
        let regions = (saliency?.salientObjects ?? [])
            .map { $0.boundingBox.toImageCoordinates(size, origin: .upperLeft) }
            .map { Self.expand($0, by: 0.12, within: size) }
            .filter { $0.width * $0.height >= size.width * size.height * 0.02 }
            .prefix(maxRegions)

        for rect in regions {
            guard let crop = image.cropping(to: rect.integral) else { continue }
            if let best = await classify(crop, minimum: regionConfidence).first {
                detections.append(Detection(
                    identifier: best.identifier, entry: best.entry, confidence: best.confidence,
                    frameTime: frameTime, thumbnail: Self.jpeg(crop)
                ))
            }
        }

        // 2. Whole frame → catch large items (sofa, bed, piano) that saliency may skip.
        let seen = Set(detections.map(\.identifier))
        for hit in await classify(image, minimum: frameConfidence) where !seen.contains(hit.identifier) {
            detections.append(Detection(
                identifier: hit.identifier, entry: hit.entry, confidence: hit.confidence,
                frameTime: frameTime, thumbnail: Self.jpeg(image)
            ))
        }
        return detections
    }

    private struct Hit { let identifier: String; let entry: CatalogEntry; let confidence: Float }

    private func classify(_ image: CGImage, minimum: Float) async -> [Hit] {
        guard let observations = try? await ClassifyImageRequest().perform(on: image) else { return [] }
        return observations
            .filter { $0.confidence >= minimum }
            .compactMap { obs in
                LabelCatalog.entry(for: obs.identifier).map {
                    Hit(identifier: obs.identifier, entry: $0, confidence: obs.confidence)
                }
            }
            .sorted { $0.confidence > $1.confidence }
    }

    static func expand(_ rect: CGRect, by fraction: CGFloat, within size: CGSize) -> CGRect {
        let dx = rect.width * fraction, dy = rect.height * fraction
        return rect.insetBy(dx: -dx, dy: -dy)
            .intersection(CGRect(origin: .zero, size: size))
    }

    static func jpeg(_ image: CGImage, maxDimension: CGFloat = 600, quality: CGFloat = 0.75) -> Data? {
        let scaled = downscale(image, maxDimension: maxDimension) ?? image
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    static func downscale(_ image: CGImage, maxDimension: CGFloat) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let scale = min(1, maxDimension / max(w, h))
        guard scale < 1 else { return image }
        let size = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        guard let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }
}
