import SwiftData
import SwiftUI

@main
struct StashlogApp: App {
    let container: ModelContainer = {
        do {
            let container = try ModelContainer(for: Room.self, Item.self)
            #if DEBUG
            SampleData.seedIfRequested(into: container.mainContext)
            #endif
            return container
        } catch {
            fatalError("Couldn't open the inventory database: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
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
