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
