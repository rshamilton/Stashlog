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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                if room.items.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12)], spacing: 12) {
                        ForEach(room.sortedItems.reversed()) { item in
                            NavigationLink(value: item) {
                                ItemCard(item: item, currencyCode: currencyCode)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item) }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 90)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { captureButton }
        .navigationTitle(room.name)
        .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Import Photos", systemImage: "photo.on.rectangle") { showingPhotoPicker = true }
                    Button("Add Item Manually", systemImage: "square.and.pencil") { addManualItem() }
                } label: {
                    if importing { ProgressView() } else { Label("More", systemImage: "ellipsis.circle") }
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

    private var summaryCard: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(room.totalValue, format: .currency(code: currencyCode))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                Text("\(itemCount) items").foregroundStyle(.secondary)
            }
            Spacer()
            if unreviewedCount > 0 {
                Label("\(unreviewedCount) to review", systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
        }
    }

    private var itemCount: Int { room.items.reduce(0) { $0 + max($1.quantity, 1) } }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Nothing here yet").font(.title3.weight(.semibold))
            Text("Tap Capture, point at one thing, and tap the shutter. Each photo becomes an item and Stashlog suggests a name. Photos stay on this iPhone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }

    private var captureButton: some View {
        Button {
            capturing = true
        } label: {
            Label("Capture", systemImage: "camera.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .disabled(!CameraController.isAvailable)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
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

struct ItemCard: View {
    let item: Item
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { ItemThumbnail(data: item.photo, category: item.category, cornerRadius: 0) }
                .clipped()
                .overlay(alignment: .topLeading) {
                    if item.needsReview {
                        Text("Review")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.orange, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if item.quantity > 1 {
                        Text("×\(item.quantity)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.isUnnamed ? "Unnamed item" : item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.isUnnamed ? .secondary : .primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var subtitle: String {
        if let unit = item.unitValue {
            return (unit * Decimal(max(item.quantity, 1))).formatted(.currency(code: currencyCode))
        }
        return item.makeAndModel.isEmpty ? item.category.title : item.makeAndModel
    }
}

struct ItemThumbnail: View {
    let data: Data?
    let category: ItemCategory
    var cornerRadius: CGFloat = 8

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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
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
