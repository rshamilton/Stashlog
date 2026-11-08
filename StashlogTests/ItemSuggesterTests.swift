import CoreGraphics
import Foundation
import Testing
@testable import Stashlog

/// Builds a detection from a centre point and size (normalized, top-left origin), the way the
/// detector reported them on real captures.
private func det(_ name: String, _ conf: Float, cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat,
                 category: ItemCategory = .other) -> DetectedObject {
    DetectedObject(name: name, category: category, confidence: conf,
                   box: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
}

/// Fixtures are the detector's actual output on photos from a real capture session.
struct SelectionTests {
    let suggester = ItemSuggester()

    @Test func mouseOnDeskIsMouseNotDesk() {  // capture #20
        let r = suggester.choose(detected: [
            det("Mouse", 0.92, cx: 0.54, cy: 0.40, w: 0.32, h: 0.25),
            det("Laptop", 0.68, cx: 0.45, cy: 0.12, w: 0.84, h: 0.25),
            det("Pen", 0.67, cx: 0.17, cy: 0.36, w: 0.13, h: 0.28),
            det("Desk", 0.65, cx: 0.50, cy: 0.50, w: 1.0, h: 1.0),
        ], classified: [])
        #expect(r.autoName?.name == "Mouse")
        #expect(r.chips.first?.name == "Mouse")
        #expect(r.chips.last?.name != "Mouse")
    }

    @Test func cameraBeatsMoreConfidentDeskAndOffCentreItems() {  // capture #23
        let r = suggester.choose(detected: [
            det("Desk", 0.82, cx: 0.50, cy: 0.68, w: 1.0, h: 0.64),
            det("Keyboard (music)", 0.70, cx: 0.47, cy: 0.78, w: 0.41, h: 0.30),
            det("Camera", 0.65, cx: 0.46, cy: 0.41, w: 0.30, h: 0.16),
        ], classified: [])
        #expect(r.autoName?.name == "Camera")
    }

    @Test func bookOnDeskIsBook() {  // capture #21
        let r = suggester.choose(detected: [
            det("Book", 0.71, cx: 0.52, cy: 0.42, w: 0.47, h: 0.45),
            det("Desk", 0.53, cx: 0.50, cy: 0.48, w: 1.0, h: 0.96),
        ], classified: [])
        #expect(r.autoName?.name == "Book")
    }

    @Test func tieBetweenLabelsOnSameObjectIsNotAutoFilled() {  // capture #25 (pen)
        let r = suggester.choose(detected: [
            det("Scissors", 0.38, cx: 0.52, cy: 0.39, w: 0.10, h: 0.48),
            det("Pen", 0.37, cx: 0.52, cy: 0.40, w: 0.10, h: 0.49),
            det("Mouse pad", 0.60, cx: 0.75, cy: 0.55, w: 0.6, h: 0.8),
        ], classified: [])
        #expect(r.autoName == nil)
        #expect(Set(r.chips.prefix(2).map(\.name)) == ["Scissors", "Pen"])
    }

    @Test func unknownObjectOnDeskStaysBlankInsteadOfDesk() {  // capture #22 (USB hub)
        let r = suggester.choose(detected: [
            det("Desk", 0.69, cx: 0.54, cy: 0.51, w: 0.93, h: 0.98),
            det("Remote control", 0.17, cx: 0.47, cy: 0.41, w: 0.34, h: 0.21),
        ], classified: [])
        #expect(r.autoName == nil)
    }

    @Test func deskFillingFrameWithNothingOnItIsDesk() {
        let r = suggester.choose(detected: [det("Desk", 0.8, cx: 0.5, cy: 0.5, w: 0.95, h: 0.9)], classified: [])
        #expect(r.autoName?.name == "Desk")
    }

    @Test func classifierOnlyUsedWhenDetectorSawNothing() {
        let artwork = Suggestion(name: "Artwork", category: .art, confidence: 0.6)
        #expect(suggester.choose(detected: [], classified: [artwork]).autoName?.name == "Artwork")
        let withDesk = suggester.choose(detected: [det("Desk", 0.6, cx: 0.5, cy: 0.7, w: 1, h: 0.5)],
                                        classified: [artwork])
        #expect(withDesk.autoName == nil)
        #expect(withDesk.chips.contains { $0.name == "Artwork" })
    }
}

struct ClassifierRankTests {
    let suggester = ItemSuggester()

    @Test func specificItemBeatsGenericLabel() {
        let ranked = suggester.rank([("art", 0.62), ("camera", 0.41), ("furniture", 0.5)])
        #expect(ranked.first?.name == "Camera")
    }

    @Test func ignoresScenesAndLowConfidence() {
        #expect(suggester.rank([("interior_room", 0.9), ("bedroom", 0.8), ("lamp", 0.02)]).isEmpty)
    }
}

struct TitleReaderTests {
    let reader = TitleReader()

    /// The text Vision read off the Catcher in the Rye cover (capture #26).
    @Test func readsTitleAndAuthorFromCover() {
        let cover = reader.assemble([
            .init(text: "the CATCHER", height: 0.053, midY: 0.20, midX: 0.48),
            .init(text: "in the RYE", height: 0.051, midY: 0.26, midX: 0.48),
            .init(text: "novel by J. D. SALINGER", height: 0.033, midY: 0.62, midX: 0.50),
        ])
        #expect(cover?.title == "The Catcher in the Rye")
        #expect(cover?.author == "J. D. Salinger")
    }

    @Test func ignoresSmallScreenText() {  // capture #24: text on a laptop screen
        #expect(reader.assemble([
            .init(text: "Attach a simulator", height: 0.007, midY: 0.3, midX: 0.5),
            .init(text: "100", height: 0.015, midY: 0.5, midX: 0.5),
        ]) == nil)
    }

    @Test func titleCasing() {
        #expect(TitleReader.titleCase("THE LORD OF THE RINGS") == "The Lord of the Rings")
        #expect(TitleReader.titleCase("of mice and men") == "Of Mice and Men")
    }
}

struct DetectorTests {
    @Test func bundledDetectorLoads() {
        let detector = ObjectDetector(bundle: .main)  // hosted tests run inside the app
        #expect(detector.isAvailable)
        #expect(detector.vocabularySize >= 260)
    }

    @Test func iou() {
        let a = CGRect(x: 0, y: 0, width: 1, height: 1)
        #expect(a.iou(a) == 1)
        #expect(a.iou(CGRect(x: 2, y: 2, width: 1, height: 1)) == 0)
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
