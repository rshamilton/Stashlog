import Foundation

/// Insurance-friendly categories. Raw values are stored, so never rename them.
nonisolated enum ItemCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case electronics
    case appliances
    case furniture
    case kitchen
    case decor
    case art
    case jewelry
    case clothing
    case musical
    case sports
    case tools
    case books
    case toys
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .electronics: "Electronics"
        case .appliances: "Appliances"
        case .furniture: "Furniture"
        case .kitchen: "Kitchenware"
        case .decor: "Decor & Lighting"
        case .art: "Art & Collectibles"
        case .jewelry: "Jewelry & Watches"
        case .clothing: "Clothing & Accessories"
        case .musical: "Musical Instruments"
        case .sports: "Sports & Fitness"
        case .tools: "Tools & Garden"
        case .books: "Books & Media"
        case .toys: "Toys & Games"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .electronics: "tv"
        case .appliances: "washer"
        case .furniture: "sofa"
        case .kitchen: "fork.knife"
        case .decor: "lamp.floor"
        case .art: "photo.artframe"
        case .jewelry: "sparkles"
        case .clothing: "tshirt"
        case .musical: "guitars"
        case .sports: "dumbbell"
        case .tools: "wrench.and.screwdriver"
        case .books: "books.vertical"
        case .toys: "teddybear"
        case .other: "shippingbox"
        }
    }
}
