import PhotosUI
import SwiftData
import SwiftUI

struct ItemDetailView: View {
    @Bindable var item: Item
    @AppStorage(SettingsKey.currencyCode) private var currencyCode = Locale.defaultCurrencyCode

    @State private var photoPick: PhotosPickerItem?
    @State private var receiptPick: PhotosPickerItem?
    @State private var labelPick: PhotosPickerItem?
    @State private var cameraTarget: CameraTarget?
    @State private var isReadingLabel = false
    @State private var labelMessage: String?

    enum CameraTarget: Identifiable {
        case photo, receipt, label
        var id: Self { self }
    }

    var body: some View {
        Form {
            Section {
                Color.clear
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay { ItemThumbnail(data: item.photo, category: item.category, cornerRadius: 0) }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .bottomTrailing) {
                        Menu {
                            Button("Take Photo", systemImage: "camera") { cameraTarget = .photo }
                                .disabled(!CameraPicker.isAvailable)
                            PhotosPicker("Choose Photo", selection: $photoPick, matching: .images)
                        } label: {
                            Label(item.photo == nil ? "Add Photo" : "Change", systemImage: "camera")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(10)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Item") {
                TextField("Name", text: Binding(
                    get: { item.isUnnamed ? "" : item.name },
                    set: { item.name = $0.trimmingCharacters(in: .whitespaces).isEmpty ? Item.placeholderName : $0 }
                ), prompt: Text("What is it?"))
                .font(.headline)
                Picker("Category", selection: $item.category) {
                    ForEach(ItemCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                Stepper(value: $item.quantity, in: 1...999) {
                    LabeledContent("Quantity", value: "\(item.quantity)")
                }
            }

            Section {
                TextField("Brand", text: $item.brand)
                TextField("Model", text: $item.model)
                TextField("Serial number", text: $item.serialNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                HStack {
                    Menu {
                        Button("Take Photo of Label", systemImage: "camera") { cameraTarget = .label }
                            .disabled(!CameraPicker.isAvailable)
                        PhotosPicker("Choose Photo of Label", selection: $labelPick, matching: .images)
                    } label: {
                        Label("Read from label", systemImage: "text.viewfinder")
                    }
                    if isReadingLabel { Spacer(); ProgressView() }
                }
            } header: {
                Text("Identification")
            } footer: {
                Text(labelMessage ?? "Photograph the sticker or nameplate (often on the back or underneath) to fill these in automatically. The text is read on your iPhone.")
            }

            Section {
                PriceField(title: "Price paid", unitPrice: $item.purchasePrice,
                           quantity: item.quantity, currencyCode: currencyCode)
                PriceField(title: "Cost to replace today", unitPrice: $item.replacementValue,
                           quantity: item.quantity, currencyCode: currencyCode)
                Toggle("Known purchase date", isOn: Binding(
                    get: { item.purchaseDate != nil },
                    set: { item.purchaseDate = $0 ? (item.purchaseDate ?? .now) : nil }
                ))
                if item.purchaseDate != nil {
                    DatePicker("Purchased", selection: Binding(
                        get: { item.purchaseDate ?? .now }, set: { item.purchaseDate = $0 }
                    ), in: ...Date.now, displayedComponents: .date)
                }
            } header: {
                Text("Value")
            } footer: {
                Text("Insurers usually pay replacement cost — what it would cost to buy new today.")
            }

            Section("Receipt") {
                if let data = item.receiptPhoto, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                    Button("Remove Receipt", role: .destructive) { item.receiptPhoto = nil }
                }
                imageButtons(pick: $receiptPick, target: .receipt, title: "Receipt")
            }

            Section("Notes") {
                TextField("Condition, where it was bought, warranty…", text: $item.notes, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        .navigationTitle(item.isUnnamed ? "Unnamed item" : item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if item.needsReview {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark Reviewed", systemImage: "checkmark.seal") { item.needsReview = false }
                }
            }
        }
        .onChange(of: photoPick) { _, pick in Task { await load(pick, into: .photo); photoPick = nil } }
        .onChange(of: receiptPick) { _, pick in Task { await load(pick, into: .receipt); receiptPick = nil } }
        .onChange(of: labelPick) { _, pick in Task { await load(pick, into: .label); labelPick = nil } }
        .fullScreenCover(item: $cameraTarget) { target in
            CameraPicker(mode: .photo) { result in
                cameraTarget = nil
                if case let .photo(image) = result { Task { await apply(image, to: target) } }
            }
            .ignoresSafeArea()
        }
    }

    private func imageButtons(pick: Binding<PhotosPickerItem?>, target: CameraTarget, title: String) -> some View {
        HStack {
            Button("Take \(title)", systemImage: "camera") { cameraTarget = target }
                .disabled(!CameraPicker.isAvailable)
            Spacer()
            PhotosPicker("Choose", selection: pick, matching: .images)
        }
        .buttonStyle(.borderless)
    }

    private func load(_ pick: PhotosPickerItem?, into target: CameraTarget) async {
        guard let pick, let data = try? await pick.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await apply(image, to: target)
    }

    private func apply(_ image: UIImage, to target: CameraTarget) async {
        guard let cg = image.normalizedCGImage() else { return }
        switch target {
        case .photo:
            item.photo = ItemDetector.jpeg(cg, maxDimension: 1600, quality: 0.8)
        case .receipt:
            item.receiptPhoto = ItemDetector.jpeg(cg, maxDimension: 2000, quality: 0.8)
            await readDetails(from: cg, isReceipt: true)
        case .label:
            await readDetails(from: cg, isReceipt: false)
        }
    }

    private func readDetails(from image: CGImage, isReceipt: Bool) async {
        isReadingLabel = true
        defer { isReadingLabel = false }
        let details = await DetailsExtractor().extract(from: image)
        var filled: [String] = []
        if item.brand.isEmpty, let v = details.brand { item.brand = v; filled.append("brand") }
        if item.model.isEmpty, let v = details.model { item.model = v; filled.append("model") }
        if item.serialNumber.isEmpty, let v = details.serialNumber { item.serialNumber = v; filled.append("serial number") }
        if isReceipt {
            if item.purchasePrice == nil, let v = details.price { item.purchasePrice = v; filled.append("price") }
            if item.purchaseDate == nil, let v = details.purchaseDate { item.purchaseDate = v; filled.append("date") }
        }
        labelMessage = filled.isEmpty
            ? "Couldn't find new details in that photo. Try a closer, sharper shot."
            : "Filled in \(ListFormatter.localizedString(byJoining: filled)). Please double-check."
    }
}
