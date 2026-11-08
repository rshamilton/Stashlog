import CoreGraphics
import Foundation
import Vision

nonisolated struct Suggestion: Hashable, Sendable {
    let name: String
    let category: ItemCategory
    let confidence: Float
}

/// What the suggester concluded about one photo.
nonisolated struct SuggestionResult: Sendable, Equatable {
    /// Filled into the name field only when there's a clear answer. Nil means "ask the user".
    var autoName: Suggestion?
    /// Chips to offer, best first.
    var chips: [Suggestion]
    /// For books: the author read from the cover.
    var author: String?

    static let empty = SuggestionResult(autoName: nil, chips: [])
}

/// Suggests a name for a photo the user framed around one object.
///
/// Tuned on real captures: the household detector usually finds the right object, so the work is
/// in choosing it. Rules: the object under the reticle wins; surfaces things sit on (desk, table,
/// shelf…) only win when they fill the frame and nothing else is there; near-ties aren't
/// auto-filled; and for books the cover's title beats the word "Book".
nonisolated struct ItemSuggester: Sendable {
    /// Where the reticle points, in normalized top-left coordinates.
    static let aim = CGPoint(x: 0.5, y: 0.45)

    var autoNameConfidence: Float = 0.35
    var candidateConfidence: Float = 0.15
    /// A second, different label on the same object within this margin makes it a tie.
    var tieMargin: Float = 0.12
    var maxChips = 5

    /// Things other things sit on or in front of. They're background unless they fill the frame.
    static let surfaces: Set<String> = [
        "Desk", "Dining table", "Coffee table", "Side table", "Nightstand", "Bed", "Shelf", "Bookshelf",
        "Rug", "Cabinet", "TV stand", "Dresser", "Chest of drawers", "Sofa", "Armchair", "Bench",
        "Wardrobe", "Filing cabinet", "Curtains", "Blanket", "Comforter", "Crib", "Mouse pad",
    ]
    static let bookLike: Set<String> = ["Book", "Books", "Magazine", "Poster"]

    @concurrent
    func analyze(_ image: CGImage) async -> SuggestionResult {
        let detected = await ObjectDetector.shared.detect(in: image)
        let classified = await classify(image)
        var result = choose(detected: detected, classified: classified)

        // Books: read the cover. A title is far more useful than "Book".
        let looksLikeBook = result.chips.prefix(3).contains { Self.bookLike.contains($0.name) }
        if looksLikeBook, let cover = await TitleReader().read(in: image) {
            let title = Suggestion(name: cover.title, category: .books, confidence: 1)
            result.chips.removeAll { $0.name == cover.title }
            result.chips.insert(title, at: 0)
            result.autoName = title
            result.author = cover.author
        }
        return result
    }

    // MARK: - Choosing (pure, tested)

    func choose(detected: [DetectedObject], classified: [Suggestion]) -> SuggestionResult {
        func distanceToAim(_ box: CGRect) -> CGFloat {
            hypot(box.midX - Self.aim.x, box.midY - Self.aim.y)
        }
        func score(_ d: DetectedObject) -> Float {
            d.confidence * Float(1 - 0.5 * min(1, distanceToAim(d.box) / 0.3))
        }
        func coversAim(_ d: DetectedObject) -> Bool {
            d.box.insetBy(dx: -0.04, dy: -0.04).contains(Self.aim)
        }

        let candidates = detected
            .filter { !Self.surfaces.contains($0.name) && $0.confidence >= candidateConfidence && coversAim($0) }
            .sorted { score($0) > score($1) }

        var autoName: Suggestion?
        if let best = candidates.first {
            let tied = candidates.dropFirst().contains {
                $0.name != best.name && $0.box.iou(best.box) > 0.5 && $0.confidence >= best.confidence - tieMargin
            }
            if best.confidence >= autoNameConfidence, !tied {
                autoName = Suggestion(name: best.name, category: best.category, confidence: best.confidence)
            }
        } else if let surface = detected
            .filter({ Self.surfaces.contains($0.name) && $0.box.insetBy(dx: 0.1, dy: 0.1).contains(Self.aim)
                        && $0.box.area >= 0.6 && $0.confidence >= 0.5 })
            .max(by: { $0.confidence < $1.confidence }) {
            // Nothing on it: the user photographed the desk itself.
            autoName = Suggestion(name: surface.name, category: surface.category, confidence: surface.confidence)
        } else if detected.isEmpty, let top = classified.first, top.confidence >= autoNameConfidence {
            // The detector saw nothing it knows; fall back to Apple's classifier.
            autoName = top
        }

        // Chips: what's under the reticle, then other objects, then surfaces, then the classifier.
        let others = detected
            .filter { d in !candidates.contains(where: { $0 == d }) }
            .sorted { (Self.surfaces.contains($0.name) ? 1 : 0, -$0.confidence) < (Self.surfaces.contains($1.name) ? 1 : 0, -$1.confidence) }
        var seen = Set<String>()
        var chips: [Suggestion] = []
        if let autoName { seen.insert(autoName.name.lowercased()); chips.append(autoName) }
        for d in candidates + others where d.confidence >= 0.1 {
            if seen.insert(d.name.lowercased()).inserted {
                chips.append(Suggestion(name: d.name, category: d.category, confidence: d.confidence))
            }
        }
        for s in classified where seen.insert(s.name.lowercased()).inserted { chips.append(s) }
        return SuggestionResult(autoName: autoName, chips: Array(chips.prefix(maxChips)))
    }

    // MARK: - Apple's classifier (fallback)

    /// Labels that describe a kind of thing rather than the thing itself.
    static let genericLabels: Set<String> = [
        "furniture", "consumer_electronics", "appliance", "art", "tool", "toy", "clothing",
        "musical_instrument", "string_instrument", "brass_music", "woodwind", "sports_equipment",
        "computer", "cookware", "tableware", "utensil", "textile", "chair_other", "illustrations",
    ]
    static let genericPenalty: Float = 0.4

    private func classify(_ image: CGImage) async -> [Suggestion] {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let center = CGRect(x: w * 0.15, y: h * 0.15, width: w * 0.7, height: h * 0.7).integral
        var observations: [(String, Float)] = []
        for region in [image.cropping(to: center), image].compactMap({ $0 }) {
            if let results = try? await ClassifyImageRequest().perform(on: region) {
                observations += results.map { ($0.identifier, $0.confidence) }
            }
        }
        return rank(observations)
    }

    /// Keeps insurable labels, ranks specific above generic, best score per name.
    func rank(_ observations: [(identifier: String, confidence: Float)], limit: Int = 3) -> [Suggestion] {
        var best: [String: Suggestion] = [:]
        for (identifier, confidence) in observations where confidence >= 0.05 {
            guard let entry = LabelCatalog.entry(for: identifier) else { continue }
            let score = Self.genericLabels.contains(identifier) ? confidence * Self.genericPenalty : confidence
            if (best[entry.name]?.confidence ?? -1) < score {
                best[entry.name] = Suggestion(name: entry.name, category: entry.category, confidence: score)
            }
        }
        return Array(best.values.sorted { $0.confidence > $1.confidence }.prefix(limit))
    }
}

extension CGRect {
    nonisolated var area: CGFloat { width * height }

    nonisolated func iou(_ other: CGRect) -> CGFloat {
        let inter = intersection(other)
        guard !inter.isNull, inter.area > 0 else { return 0 }
        return inter.area / (area + other.area - inter.area)
    }
}
