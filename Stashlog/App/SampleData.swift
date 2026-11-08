#if DEBUG
import SwiftData
import UIKit

/// Demo inventory for simulator previews and screenshots. Launch with `-seedSampleData`.
/// Debug builds only; never shipped.
enum SampleData {
    static func seedIfRequested(into context: ModelContext) {
        guard CommandLine.arguments.contains("-seedSampleData") else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<Room>())) ?? 0
        guard existing == 0 else { return }

        let rooms: [(String, [(String, ItemCategory, Int, Decimal?, String, Bool, UIColor)])] = [
            ("Living Room", [
                ("Television", .electronics, 1, 1199.99, "Samsung QN65Q80C", false, .systemIndigo),
                ("Sofa", .furniture, 1, 1850, "", false, .systemBrown),
                ("Lamp", .decor, 2, 89.99, "", false, .systemOrange),
                ("Acoustic guitar", .musical, 1, 1299, "Taylor 214ce", false, .systemRed),
                ("Speakers", .electronics, 1, 190, "Sonos Era 100", true, .systemGray),
                (Item.placeholderName, .other, 1, nil, "", true, .systemTeal),
            ]),
            ("Office", [
                ("Camera", .electronics, 1, 479, "Canon EOS Rebel T7", false, .darkGray),
                ("Laptop", .electronics, 1, 1299, "MacBook Air 13\"", false, .systemBlue),
                ("Office chair", .furniture, 1, 329, "", false, .systemGreen),
            ]),
            ("Kitchen", []),
        ]
        for (index, (roomName, items)) in rooms.enumerated() {
            let room = Room(name: roomName, symbol: Room.defaultSymbol(for: roomName), sortIndex: index)
            context.insert(room)
            for (offset, spec) in items.enumerated() {
                let (name, category, quantity, price, makeModel, review, color) = spec
                let item = Item(name: name, category: category, quantity: quantity,
                                photo: photo(symbol: category.symbol, color: color), needsReview: review)
                item.purchasePrice = price
                let parts = makeModel.split(separator: " ", maxSplits: 1).map(String.init)
                item.brand = parts.first ?? ""
                item.model = parts.count > 1 ? parts[1] : ""
                item.createdAt = Date.now.addingTimeInterval(Double(offset) * 60)
                item.room = room
                context.insert(item)
            }
        }
    }

    private static func photo(symbol: String, color: UIColor) -> Data? {
        let size = CGSize(width: 600, height: 600)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            color.withAlphaComponent(0.85).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let config = UIImage.SymbolConfiguration(pointSize: 220, weight: .regular)
            if let glyph = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(.white.withAlphaComponent(0.9), renderingMode: .alwaysOriginal) {
                glyph.draw(at: CGPoint(x: (size.width - glyph.size.width) / 2, y: (size.height - glyph.size.height) / 2))
            }
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}
#endif
