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
/// Classifies the centre of the frame (where the user aimed) and the whole frame, keeps only
/// insurable item labels, and ranks specific names ("Camera") above catch-all ones
/// ("Furniture", "Artwork") that Vision tends to give cluttered scenes.
nonisolated struct ItemSuggester: Sendable {
    /// Minimum confidence to fill the name in automatically. Below it we only offer chips.
    var autoNameConfidence: Float = 0.35
    var minimumConfidence: Float = 0.05

    /// Labels that describe a kind of thing rather than the thing itself.
    static let genericLabels: Set<String> = [
        "furniture", "consumer_electronics", "appliance", "art", "tool", "toy", "clothing",
        "musical_instrument", "string_instrument", "brass_music", "woodwind", "sports_equipment",
        "computer", "cookware", "tableware", "utensil", "textile", "chair_other", "illustrations",
    ]
    static let genericPenalty: Float = 0.4

    @concurrent
    func suggestions(for image: CGImage, limit: Int = 3) async -> [Suggestion] {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let center = CGRect(x: w * 0.15, y: h * 0.15, width: w * 0.7, height: h * 0.7).integral
        var observations: [(String, Float)] = []
        for region in [image.cropping(to: center), image].compactMap({ $0 }) {
            if let results = try? await ClassifyImageRequest().perform(on: region) {
                observations += results.map { ($0.identifier, $0.confidence) }
            }
        }
        return rank(observations, limit: limit)
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
