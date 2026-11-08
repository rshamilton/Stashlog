import PhotosUI
import SwiftData
import SwiftUI

struct RoomDetailView: View {
    @Bindable var room: Room
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.currencyCode) private var currencyCode = Locale.defaultCurrencyCode

    @State private var activeScan: ScanSession?
    @State private var recordedVideo: URL?
    @State private var showingCamera = false
    @State private var videoSelection: PhotosPickerItem?
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showingVideoPicker = false
    @State private var showingPhotoPicker = false
    @State private var importError: String?

    var body: some View {
        List {
            if room.items.isEmpty {
                ContentUnavailableView {
                    Label("No items yet", systemImage: "video.badge.waveform")
                } description: {
                    Text("Film a slow pan around \(room.name). Stashlog will suggest items for you to confirm.")
                } actions: {
                    scanMenu.buttonStyle(.borderedProminent)
                }
            } else {
                Section {
                    LabeledContent("Room total") {
                        Text(room.totalValue, format: .currency(code: currencyCode)).bold()
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
            ToolbarItem(placement: .topBarTrailing) { scanMenu }
        }
        .photosPicker(isPresented: $showingVideoPicker, selection: $videoSelection, matching: .videos)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoSelection, maxSelectionCount: 20,
                      matching: .images)
        .onChange(of: videoSelection) { _, item in Task { await loadVideo(item) } }
        .onChange(of: photoSelection) { _, items in Task { await loadPhotos(items) } }
        // Start the scan only after the camera has fully closed; presenting the review sheet
        // mid-dismissal makes SwiftUI rebuild it.
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            if let url = recordedVideo {
                recordedVideo = nil
                startScan(.video(url))
            }
        }) {
            CameraPicker(mode: .video) { result in
                if case let .video(url) = result { recordedVideo = url }
                showingCamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(item: $activeScan) { session in ScanReviewView(room: room, session: session) }
        .alert("Couldn't import", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var scanMenu: some View {
        Menu {
            Button("Film Walkthrough", systemImage: "video") { showingCamera = true }
                .disabled(!CameraPicker.isAvailable)
            Button("Choose Video", systemImage: "film.stack") { showingVideoPicker = true }
            Button("Choose Photos", systemImage: "photo.on.rectangle") { showingPhotoPicker = true }
            Divider()
            Button("Add Item Manually", systemImage: "square.and.pencil") { addManualItem() }
        } label: {
            Label("Add Items", systemImage: "plus")
        }
    }

    private func startScan(_ input: ScanInput) {
        let session = ScanSession()
        session.start(input)
        activeScan = session
    }

    private func addManualItem() {
        let item = Item(name: "New item")
        item.room = room
        context.insert(item)
    }

    private func loadVideo(_ selection: PhotosPickerItem?) async {
        guard let selection else { return }
        defer { videoSelection = nil }
        do {
            guard let movie = try await selection.loadTransferable(type: VideoFile.self) else {
                importError = "That video couldn't be loaded."
                return
            }
            startScan(.video(movie.url))
        } catch {
            importError = error.localizedDescription
        }
    }

    private func loadPhotos(_ selections: [PhotosPickerItem]) async {
        guard !selections.isEmpty else { return }
        defer { photoSelection = [] }
        var images: [CGImage] = []
        for selection in selections {
            if let data = try? await selection.loadTransferable(type: Data.self),
               let image = UIImage(data: data)?.normalizedCGImage() {
                images.append(image)
            }
        }
        if images.isEmpty { importError = "Those photos couldn't be loaded." } else { startScan(.photos(images)) }
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

/// A picked video copied into the app's temporary directory so AVFoundation can read it.
struct VideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return VideoFile(url: destination)
        }
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
