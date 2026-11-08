import CoreGraphics
import Foundation
import SwiftData
import Testing
import Vision
@testable import Stashlog

struct LabelCatalogTests {
    @Test func mapsCommonHouseholdLabels() {
        #expect(LabelCatalog.entry(for: "television")?.category == .electronics)
        #expect(LabelCatalog.entry(for: "sofa")?.category == .furniture)
        #expect(LabelCatalog.entry(for: "guitar")?.category == .musical)
        #expect(LabelCatalog.entry(for: "refrigerator")?.category == .appliances)
    }

    @Test func ignoresScenesFoodAndAnimals() {
        #expect(LabelCatalog.entry(for: "living_room") == nil)
        #expect(LabelCatalog.entry(for: "pizza") == nil)
        #expect(LabelCatalog.entry(for: "dog") == nil)
    }

    /// Guards against typos: every catalog key must be a label Vision can actually emit.
    @Test func everyKeyIsARealVisionLabel() throws {
        let supported = Set(try VNClassifyImageRequest().supportedIdentifiers())
        let unknown = LabelCatalog.identifiers.subtracting(supported)
        #expect(unknown.isEmpty, "Not Vision labels: \(unknown.sorted())")
    }
}

struct ScanAggregatorTests {
    private func detection(_ id: String, _ confidence: Float, frame: Double) -> Detection {
        Detection(identifier: id, entry: LabelCatalog.entry(for: id)!, confidence: confidence,
                  frameTime: frame, thumbnail: nil)
    }

    @Test func mergesSameItemAcrossFrames() {
        let result = ScanAggregator().aggregate([
            detection("sofa", 0.6, frame: 0), detection("sofa", 0.8, frame: 1), detection("sofa", 0.7, frame: 2),
        ])
        #expect(result.count == 1)
        #expect(result[0].quantity == 1)
        #expect(result[0].framesSeen == 3)
        #expect(result[0].confidence == 0.8)
    }

    @Test func quantityIsMaxCopiesInOneFrame() {
        let result = ScanAggregator().aggregate([
            detection("chair", 0.6, frame: 0), detection("chair", 0.6, frame: 0),
            detection("chair", 0.6, frame: 1), detection("chair", 0.6, frame: 1), detection("chair", 0.6, frame: 1),
        ])
        #expect(result.first?.quantity == 3)
    }

    @Test func weakSingleSightingsStartUnselected() {
        let result = ScanAggregator().aggregate([detection("vase", 0.32, frame: 4)])
        #expect(result.first?.isSelected == false)
    }
}

struct PatternParserTests {
    @Test func readsSerialAndModelFromNameplate() {
        let details = PatternParser.parse([
            "SAMSUNG", "MODEL: QN65Q80CAFXZA", "S/N: 0A1B3CXR500123W", "MADE IN MEXICO",
        ])
        #expect(details.model == "QN65Q80CAFXZA")
        #expect(details.serialNumber == "0A1B3CXR500123W")
    }

    @Test func prefersTotalLineOnReceipt() {
        let details = PatternParser.parse([
            "BEST STORE", "TV 65IN        899.99", "MOUNT           49.99",
            "SUBTOTAL       949.98", "TAX             78.37", "TOTAL        $1,028.35",
        ])
        #expect(details.price == Decimal(string: "1028.35"))
    }

    @Test func emptyWhenNothingFound() {
        #expect(PatternParser.parse(["hello world"]).isEmpty)
    }
}

@MainActor
struct ReportTests {
    /// Held for the test's lifetime: SwiftData models crash if their container is deallocated.
    let container: ModelContainer
    let rooms: [Room]

    init() throws {
        (container, rooms) = try Self.sampleRooms()
    }

    private static func sampleRooms() throws -> (ModelContainer, [Room]) {
        let container = try ModelContainer(
            for: Room.self, Item.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let room = Room(name: "Living Room")
        container.mainContext.insert(room)
        let tv = Item(name: "Television", category: .electronics)
        tv.replacementValue = 1200
        tv.serialNumber = "ABC123"
        tv.room = room
        let chairs = Item(name: "Chair, \"dining\"", category: .furniture, quantity: 4)
        chairs.purchasePrice = 150
        chairs.room = room
        container.mainContext.insert(tv)
        container.mainContext.insert(chairs)
        return (container, [room])
    }

    @Test func totalsUseReplacementThenPurchasePriceTimesQuantity() throws {

        let report = InventoryReport(rooms: rooms, defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        #expect(report.grandTotal == 1800)  // 1200 + 4 × 150
        #expect(report.itemCount == 5)
    }

    @Test func pdfIsAValidDocument() throws {

        let data = InventoryReport(rooms: rooms).pdfData()
        #expect(data.count > 1000)
        #expect(data.prefix(4) == Data("%PDF".utf8))
    }

    @Test func csvEscapesQuotesAndCommas() throws {

        let csv = InventoryReport(rooms: rooms).csv()
        #expect(csv.contains("\"Chair, \"\"dining\"\"\""))
        #expect(csv.split(separator: "\n").count == 3)
    }
}
