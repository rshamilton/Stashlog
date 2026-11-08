import CoreGraphics
import Foundation
import Testing
@testable import Stashlog

struct ItemSuggesterTests {
    let suggester = ItemSuggester()

    /// The desk photo failure: Vision said "art" most strongly, but a camera was in frame.
    @Test func specificItemBeatsGenericLabel() {
        let ranked = suggester.rank([("art", 0.62), ("camera", 0.41), ("furniture", 0.5)])
        #expect(ranked.first?.name == "Camera")
        #expect(ranked.first?.category == .electronics)
    }

    @Test func ignoresScenesAndLowConfidence() {
        let ranked = suggester.rank([("interior_room", 0.9), ("bedroom", 0.8), ("lamp", 0.02)])
        #expect(ranked.isEmpty)
    }

    @Test func mergesCropAndFullFrameKeepingBestScore() {
        let ranked = suggester.rank([("television", 0.3), ("television", 0.7), ("laptop", 0.2)])
        #expect(ranked.count == 2)
        #expect(ranked.first?.name == "Television")
        #expect(ranked.first?.confidence == 0.7)
    }

    @Test func autoNamesOnlyWhenConfident() {
        #expect(suggester.autoName(from: suggester.rank([("guitar", 0.8)]))?.name == "Guitar")
        #expect(suggester.autoName(from: suggester.rank([("guitar", 0.2)])) == nil)
        // A generic label alone shouldn't auto-name (0.6 × 0.4 penalty is below threshold).
        #expect(suggester.autoName(from: suggester.rank([("furniture", 0.6)])) == nil)
    }

    @Test func respectsLimit() {
        let ranked = suggester.rank([("sofa", 0.5), ("lamp", 0.4), ("television", 0.3), ("vase", 0.2)], limit: 3)
        #expect(ranked.map(\.name) == ["Sofa", "Lamp", "Television"])
    }
}

struct PriceFieldTests {
    @Test func totalIsSplitPerUnit() {
        #expect(PriceField.unit(from: 400, mode: .total, quantity: 4) == 100)
        #expect(PriceField.unit(from: 100, mode: .total, quantity: 3) == Decimal(string: "33.33"))
    }

    @Test func eachIsStoredAsIs() {
        #expect(PriceField.unit(from: 89.99, mode: .each, quantity: 2) == Decimal(string: "89.99"))
        #expect(PriceField.unit(from: 50, mode: .total, quantity: 1) == 50)
    }
}

struct DetectorTests {
    @Test func bundledDetectorLoads() {
        let detector = ObjectDetector(bundle: .main)  // hosted tests run inside the app
        #expect(detector.isAvailable)
        #expect(detector.vocabularySize >= 250)
    }

    @Test func centredObjectBeatsMoreConfidentEdgeObject() {
        let centred = DetectedObject(name: "Camera", category: .electronics, confidence: 0.5,
                                     box: CGRect(x: 0.3, y: 0.25, width: 0.4, height: 0.4))
        let edge = DetectedObject(name: "Lamp", category: .decor, confidence: 0.7,
                                  box: CGRect(x: 0.0, y: 0.0, width: 0.15, height: 0.15))
        #expect(centred.focusScore > edge.focusScore)
    }

    @Test func detectorSuggestionsComeBeforeClassifierAndDedupe() {
        let suggester = ItemSuggester()
        let detected = [
            DetectedObject(name: "Camera", category: .electronics, confidence: 0.6,
                           box: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)),
            DetectedObject(name: "Tissue box", category: .decor, confidence: 0.05,  // below threshold
                           box: CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3)),
        ]
        let classified = [Suggestion(name: "Artwork", category: .art, confidence: 0.3),
                          Suggestion(name: "Camera", category: .electronics, confidence: 0.2)]
        let combined = suggester.combine(detected: detected, classified: classified)
        #expect(combined.map(\.name) == ["Camera", "Artwork"])
        #expect(suggester.autoName(from: combined)?.name == "Camera")
    }
}
