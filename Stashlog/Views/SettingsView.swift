import FoundationModels
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.ownerName) private var ownerName = ""
    @AppStorage(SettingsKey.propertyAddress) private var address = ""
    @AppStorage(SettingsKey.insurer) private var insurer = ""
    @AppStorage(SettingsKey.policyNumber) private var policyNumber = ""
    @AppStorage(SettingsKey.currencyCode) private var currencyCode = Locale.defaultCurrencyCode

    private static let currencies = Locale.commonISOCurrencyCodes

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $ownerName).textContentType(.name)
                    TextField("Property address", text: $address, axis: .vertical).textContentType(.fullStreetAddress)
                    TextField("Insurance company", text: $insurer)
                    TextField("Policy number", text: $policyNumber)
                } header: {
                    Text("Report details")
                } footer: {
                    Text("Shown on the first page of your PDF report.")
                }

                Picker("Currency", selection: $currencyCode) {
                    ForEach(Self.currencies, id: \.self) { code in
                        Text("\(code) — \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code)
                    }
                }

                Section("Privacy") {
                    Label("No account, no ads, no tracking", systemImage: "hand.raised")
                    Label("Videos and photos are processed on this iPhone", systemImage: "lock.iphone")
                    Label("Stashlog has no servers; nothing is uploaded", systemImage: "icloud.slash")
                    LabeledContent("On-device AI") {
                        Text(SystemLanguageModel.default.isAvailable ? "Available" : "Not available")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Link(destination: URL(string: "https://github.com/argtime/Stashlog")!) {
                        Label("Source code (GPLv3)", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } footer: {
                    Text("Stashlog is free and open source.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
