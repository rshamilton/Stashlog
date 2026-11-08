import SwiftData
import SwiftUI

@main
struct StashlogApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Room.self, Item.self])
    }
}

/// Keys for the few user preferences Stashlog stores (all on-device, in UserDefaults).
enum SettingsKey {
    static let ownerName = "ownerName"
    static let propertyAddress = "propertyAddress"
    static let insurer = "insurer"
    static let policyNumber = "policyNumber"
    static let currencyCode = "currencyCode"
}

extension Locale {
    static var defaultCurrencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }
}
