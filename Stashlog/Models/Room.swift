import Foundation
import SwiftData

@Model
final class Room {
    var name: String
    var symbol: String
    var sortIndex: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Item.room)
    var items: [Item] = []

    init(name: String, symbol: String = Room.defaultSymbol(for: ""), sortIndex: Int = 0) {
        self.name = name
        self.symbol = symbol
        self.sortIndex = sortIndex
        self.createdAt = .now
    }

    /// Sum of each item's best-known value (replacement value, falling back to purchase price).
    var totalValue: Decimal {
        items.reduce(Decimal.zero) { $0 + $1.insuredValue }
    }

    var sortedItems: [Item] {
        items.sorted { $0.createdAt < $1.createdAt }
    }

    static let suggestions = [
        "Living Room", "Kitchen", "Primary Bedroom", "Bedroom", "Bathroom",
        "Dining Room", "Office", "Garage", "Basement", "Attic", "Closet", "Laundry Room",
    ]

    static func defaultSymbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("kitchen") { return "refrigerator" }
        if n.contains("bed") { return "bed.double" }
        if n.contains("bath") { return "bathtub" }
        if n.contains("living") || n.contains("family") { return "sofa" }
        if n.contains("dining") { return "fork.knife" }
        if n.contains("office") || n.contains("study") { return "desktopcomputer" }
        if n.contains("garage") { return "car" }
        if n.contains("laundry") { return "washer" }
        if n.contains("closet") { return "hanger" }
        return "square.split.bottomrightquarter"
    }
}
