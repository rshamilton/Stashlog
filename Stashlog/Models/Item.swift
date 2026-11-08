import Foundation
import SwiftData

@Model
final class Item {
    var name: String
    var categoryRaw: String
    var quantity: Int
    var brand: String
    var model: String
    var serialNumber: String
    var notes: String
    var purchaseDate: Date?
    /// Price paid, per unit.
    var purchasePrice: Decimal?
    /// Estimated cost to replace new today, per unit.
    var replacementValue: Decimal?
    /// True when the item was created by a scan and the user hasn't confirmed it yet.
    var needsReview: Bool
    var createdAt: Date

    @Attribute(.externalStorage) var photo: Data?
    @Attribute(.externalStorage) var receiptPhoto: Data?

    var room: Room?

    init(
        name: String,
        category: ItemCategory = .other,
        quantity: Int = 1,
        photo: Data? = nil,
        needsReview: Bool = false
    ) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.quantity = quantity
        self.brand = ""
        self.model = ""
        self.serialNumber = ""
        self.notes = ""
        self.needsReview = needsReview
        self.createdAt = .now
        self.photo = photo
    }

    /// Name given to a captured item until it's named; such items show as needing review.
    static let placeholderName = "Unnamed item"
    var isUnnamed: Bool { name == Self.placeholderName || name.isEmpty }

    var category: ItemCategory {
        get { ItemCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// Per-unit value used for totals: replacement value if known, else purchase price.
    var unitValue: Decimal? { replacementValue ?? purchasePrice }

    /// Total value for this line (unit value × quantity).
    var insuredValue: Decimal {
        (unitValue ?? 0) * Decimal(max(quantity, 1))
    }

    /// Short "Brand Model" description, empty if neither is known.
    var makeAndModel: String {
        [brand, model].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
