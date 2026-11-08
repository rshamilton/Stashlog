import SwiftUI

/// Half-height details sheet shown over the camera during capture.
struct ItemQuickEditor: View {
    @Bindable var item: Item
    var onPhotographLabel: () -> Void
    var onPhotographReceipt: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.currencyCode) private var currencyCode = Locale.defaultCurrencyCode
    @FocusState private var focused: Field?

    enum Field { case name, brand, model, serial, notes }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ItemThumbnail(data: item.photo, category: item.category)
                            .frame(width: 56, height: 56)
                        TextField("What is it?", text: nameBinding)
                            .font(.headline)
                            .focused($focused, equals: .name)
                    }
                    Picker("Category", selection: $item.category) {
                        ForEach(ItemCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Stepper(value: $item.quantity, in: 1...999) {
                        LabeledContent("Quantity", value: "\(item.quantity)")
                    }
                }

                Section("Price") {
                    PriceField(title: "Price", unitPrice: $item.purchasePrice,
                               quantity: item.quantity, currencyCode: currencyCode)
                }

                Section {
                    TextField("Brand", text: $item.brand).focused($focused, equals: .brand)
                    TextField("Model", text: $item.model).focused($focused, equals: .model)
                    TextField("Serial number", text: $item.serialNumber)
                        .focused($focused, equals: .serial)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button {
                        dismiss()
                        onPhotographLabel()
                    } label: {
                        Label("Photograph the label", systemImage: "text.viewfinder")
                    }
                } header: {
                    Text("Make & model")
                } footer: {
                    Text("The sticker or nameplate is usually on the back or underneath. Stashlog reads it on your iPhone.")
                }

                Section {
                    if item.receiptPhoto != nil {
                        Label("Receipt attached", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button {
                        dismiss()
                        onPhotographReceipt()
                    } label: {
                        Label(item.receiptPhoto == nil ? "Photograph the receipt" : "Replace receipt",
                              systemImage: "doc.text.viewfinder")
                    }
                }

                Section("Notes") {
                    TextField("Condition, where you bought it, warranty…", text: $item.notes, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focused, equals: .notes)
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.disabled)
    }

    /// Editing the name here counts as reviewing it.
    private var nameBinding: Binding<String> {
        Binding {
            item.isUnnamed ? "" : item.name
        } set: { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            item.name = trimmed.isEmpty ? Item.placeholderName : newValue
            item.needsReview = trimmed.isEmpty
        }
    }
}
