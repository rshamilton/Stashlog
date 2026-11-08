import PhotosUI
import SwiftData
import SwiftUI

struct RoomDetailView: View {
    @Bindable var room: Room
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.currencyCode) private var currencyCode = Locale.defaultCurrencyCode

    @State private var capturing = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showingPhotoPicker = false
    @State private var importing = false
    @State private var importError: String?

    private var unreviewedCount: Int { room.items.filter(\.needsReview).count }

    var body: some View {
        List {
            Section {
                Button {
                    capturing = true
                } label: {
                    Label("Capture Items", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!CameraController.isAvailable)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } footer: {
                if room.items.isEmpty {
                    Text("Point at one thing and tap. Each photo becomes an item, and Stashlog suggests a name. Photos stay on this iPhone.")
                }
            }

            if !room.items.isEmpty {
                Section {
                    LabeledContent("Room total") {
                        Text(room.totalValue, format: .currency(code: currencyCode)).bold()
                    }
                    if unreviewedCount > 0 {
                        Label("\(unreviewedCount) to review", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
                Section("Items") {
                    ForEach(room.sortedItems) { item in
                        NavigationLink(value: item) { ItemRow(item: item, currencyCode: currencyCode) }
                    }
                    .onDelete { offsets in
                        let items = room.sortedItems
                        for index in offsets { context.delete(items[index]) }
                    }
                }
            }
        }
        .navigationTitle(room.name)
        .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Import Photos", systemImage: "photo.on.rectangle") { showingPhotoPicker = true }
                    Button("Add Item Manually", systemImage: "square.and.pencil") { addManualItem() }
                } label: {
                    if importing { ProgressView() } else { Label("More", systemImage: "plus") }
                }
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoSelection, maxSelectionCount: 50,
                      matching: .images)
        .onChange(of: photoSelection) { _, items in Task { await importPhotos(items) } }
        .fullScreenCover(isPresented: $capturing) { CaptureView(room: room) }
        .alert("Couldn't import", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func addManualItem() {
        let item = Item(name: "New item")
        item.room = room
        context.insert(item)
    }

    /// Each imported photo becomes one item, named automatically when the suggestion is confident.
    private func importPhotos(_ selections: [PhotosPickerItem]) async {
        guard !selections.isEmpty else { return }
        importing = true
        defer { importing = false; photoSelection = [] }
        let suggester = ItemSuggester()
        var imported = 0
        for selection in selections {
            guard let data = try? await selection.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)?.normalizedCGImage() else { continue }
            let item = Item(name: Item.placeholderName,
                            photo: ItemDetector.jpeg(image, maxDimension: 1600, quality: 0.8), needsReview: true)
            if let top = suggester.autoName(from: await suggester.suggestions(for: image)) {
                item.name = top.name
                item.category = top.category
            }
            item.room = room
            context.insert(item)
            imported += 1
        }
        if imported == 0 { importError = "Those photos couldn't be loaded." }
    }
}

struct ItemRow: View {
    let item: Item
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            ItemThumbnail(data: item.photo, category: item.category)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.name).font(.headline).lineLimit(1)
                    if item.quantity > 1 { Text("×\(item.quantity)").foregroundStyle(.secondary) }
                }
                if item.needsReview {
                    Label("Needs review", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                } else if !item.makeAndModel.isEmpty {
                    Text(item.makeAndModel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let value = item.unitValue {
                Text(value * Decimal(item.quantity), format: .currency(code: currencyCode))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ItemThumbnail: View {
    let data: Data?
    let category: ItemCategory

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: category.symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.fill.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension UIImage {
    /// A CGImage with orientation baked in, so Vision sees the photo upright.
    func normalizedCGImage(maxDimension: CGFloat = 2048) -> CGImage? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }.cgImage
    }
}
