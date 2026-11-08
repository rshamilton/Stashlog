import CoreGraphics
import Foundation
import Vision

nonisolated struct Suggestion: Hashable, Sendable {
    let name: String
    let category: ItemCategory
    let confidence: Float
}

/// Suggests names for a photo the user framed around one object.
///
/// Runs the on-device household detector and picks the object in the reticle, then adds
/// Apple's classifier results (centre crop and full frame) as a fallback, ranking specific
/// names ("Camera") above catch-all ones ("Furniture", "Artwork").
nonisolated struct ItemSuggester: Sendable {
    /// Minimum confidence to fill the name in automatically. Below it we only offer chips.
    var autoNameConfidence: Float = 0.35
    var minimumConfidence: Float = 0.05
    /// Detector hits below this aren't worth showing as chips.
    var detectorMinimumConfidence: Float = 0.12

    /// Labels that describe a kind of thing rather than the thing itself.
    static let genericLabels: Set<String> = [
        "furniture", "consumer_electronics", "appliance", "art", "tool", "toy", "clothing",
        "musical_instrument", "string_instrument", "brass_music", "woodwind", "sports_equipment",
        "computer", "cookware", "tableware", "utensil", "textile", "chair_other", "illustrations",
    ]
    static let genericPenalty: Float = 0.4

    @concurrent
    func suggestions(for image: CGImage, limit: Int = 4) async -> [Suggestion] {
        // 1. The household detector: finds specific objects, and which one is in the reticle.
        let detected = await ObjectDetector.shared.detect(in: image)

        // 2. Apple's built-in classifier as a backup for things outside the detector's vocabulary.
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let center = CGRect(x: w * 0.15, y: h * 0.15, width: w * 0.7, height: h * 0.7).integral
        var observations: [(String, Float)] = []
        for region in [image.cropping(to: center), image].compactMap({ $0 }) {
            if let results = try? await ClassifyImageRequest().perform(on: region) {
                observations += results.map { ($0.identifier, $0.confidence) }
            }
        }
        return combine(detected: detected, classified: rank(observations, limit: limit), limit: limit)
    }

    /// Detector results first (ordered by how centred and confident they are), then classifier
    /// results, without duplicate names.
    func combine(detected: [DetectedObject], classified: [Suggestion], limit: Int = 4) -> [Suggestion] {
        var seen = Set<String>()
        var result: [Suggestion] = []
        let fromDetector = detected
            .filter { $0.confidence >= detectorMinimumConfidence }
            .sorted { $0.focusScore > $1.focusScore }
            .map { Suggestion(name: $0.name, category: $0.category, confidence: $0.confidence) }
        for s in fromDetector + classified where seen.insert(s.name.lowercased()).inserted {
            result.append(s)
            if result.count == limit { break }
        }
        return result
    }

    /// Pure ranking step, separated for testing.
    func rank(_ observations: [(identifier: String, confidence: Float)], limit: Int = 3) -> [Suggestion] {
        var best: [String: Suggestion] = [:]
        for (identifier, confidence) in observations where confidence >= minimumConfidence {
            guard let entry = LabelCatalog.entry(for: identifier) else { continue }
            let score = Self.genericLabels.contains(identifier) ? confidence * Self.genericPenalty : confidence
            if (best[entry.name]?.confidence ?? -1) < score {
                best[entry.name] = Suggestion(name: entry.name, category: entry.category, confidence: score)
            }
        }
        return Array(best.values.sorted { $0.confidence > $1.confidence }.prefix(limit))
    }

    func autoName(from suggestions: [Suggestion]) -> Suggestion? {
        suggestions.first.flatMap { $0.confidence >= autoNameConfidence ? $0 : nil }
    }
}
