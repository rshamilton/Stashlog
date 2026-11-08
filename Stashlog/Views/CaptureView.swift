import SwiftData
import SwiftUI

/// Rapid capture: point at one thing, tap, it's saved. Name it with a tap on a chip, by typing,
/// or later. Never makes the user wait before the next shot.
struct CaptureView: View {
    let room: Room

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.currencyCode) private var currencyCode = Locale.defaultCurrencyCode

    @State private var camera = CameraController()
    @State private var cameraState: CameraState = .starting
    /// Items captured in this session, oldest first.
    @State private var session: [Item] = []
    @State private var current: Item?
    @State private var suggestions: [Suggestion] = []
    @State private var nameDraft = ""
    @State private var shotMode: ShotMode = .item
    @State private var showingDetails = false
    @State private var busy = false
    @State private var flash = false
    @State private var toast: String?
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    private let suggester = ItemSuggester()

    enum CameraState: Equatable { case starting, ready, denied, failed(String) }
    enum ShotMode: Equatable { case item, label, receipt }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraLayer

            VStack(spacing: 10) {
                topBar
                if shotMode != .item { modeBanner }
                if let toast { ToastView(text: toast).transition(.move(edge: .top).combined(with: .opacity)) }
                Spacer()
                if session.count > 1 { filmstrip }
                if let current, shotMode == .item { itemCard(current) }
                shutterBar
            }
            .animation(.snappy, value: toast)
            .animation(.snappy, value: shotMode)
            .animation(.snappy, value: current?.persistentModelID)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .medium), trigger: session.count)
        .sensoryFeedback(.success, trigger: toast) { _, new in new != nil }
        .task { await startCamera() }
        .onDisappear {
            commitDraft()
            camera.stop()
        }
        .sheet(isPresented: $showingDetails, onDismiss: syncDraftFromItem) {
            if let current {
                ItemQuickEditor(
                    item: current,
                    onPhotographLabel: { shotMode = .label },
                    onPhotographReceipt: { shotMode = .receipt }
                )
            }
        }
        .alert("Couldn't take photo", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Camera

    @ViewBuilder
    private var cameraLayer: some View {
        switch cameraState {
        case .ready, .starting:
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .overlay { Reticle(color: shotMode == .item ? .white : .yellow) }
                .overlay { if flash { Color.white.opacity(0.5).ignoresSafeArea() } }
                .onTapGesture { nameFocused = false }
        case .denied:
            ContentUnavailableView {
                Label("Camera access needed", systemImage: "camera")
            } description: {
                Text("Stashlog uses the camera to photograph your belongings. Photos stay on this iPhone.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
            }
        case let .failed(message):
            ContentUnavailableView("Camera unavailable", systemImage: "camera.badge.ellipsis",
                                   description: Text(message))
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: room.symbol)
                VStack(alignment: .leading, spacing: 0) {
                    Text(room.name).font(.subheadline.weight(.semibold))
                    Text("\(room.items.count) items").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            Button("Done") { commitDraft(); dismiss() }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private var modeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: shotMode == .label ? "text.viewfinder" : "doc.text.viewfinder")
                .font(.title3)
            VStack(alignment: .leading, spacing: 0) {
                Text(shotMode == .label ? "Photograph the label" : "Photograph the receipt").font(.headline)
                Text("for \(current?.isUnnamed == false ? current!.name : "this item")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { shotMode = .item; showingDetails = true }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
        .padding(12)
        .background(.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(session) { item in
                        Button { select(item) } label: {
                            ItemThumbnail(data: item.photo, category: item.category)
                                .frame(width: 46, height: 46)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(item === current ? Color.accentColor : .white.opacity(0.4),
                                                lineWidth: item === current ? 3 : 1)
                                }
                                .overlay(alignment: .topTrailing) {
                                    if item.needsReview {
                                        Circle().fill(.orange).frame(width: 10, height: 10).offset(x: 3, y: -3)
                                    }
                                }
                        }
                        .id(item.persistentModelID)
                        .accessibilityLabel(item.isUnnamed ? "Unnamed item" : item.name)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            .onChange(of: session.count) {
                if let last = session.last { withAnimation { proxy.scrollTo(last.persistentModelID, anchor: .trailing) } }
            }
        }
    }

    private func itemCard(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ItemThumbnail(data: item.photo, category: item.category)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("What is it?", text: $nameDraft)
                        .font(.title3.weight(.semibold))
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { commitDraft() }
                    Text(cardSubtitle(item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button {
                    commitDraft()
                    showingDetails = true
                } label: {
                    Label("Details", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }

            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips, id: \.self) { chip in
                            let selected = chip.name == item.name && !item.isUnnamed
                            Button {
                                apply(name: chip.name, category: chip.category, to: item)
                            } label: {
                                HStack(spacing: 4) {
                                    if chip.isSameAsLast { Image(systemName: "arrow.counterclockwise") }
                                    Text(chip.label)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(selected ? Color.black : .white)
                                .background(selected ? Color.accentColor : .white.opacity(0.14), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                QuantityControl(quantity: Binding(get: { item.quantity }, set: { item.quantity = $0 }))
                Spacer()
                Button(role: .destructive) { undoCurrent() } label: {
                    Label("Delete photo", systemImage: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .tint(.red.opacity(0.9))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 12)
    }

    private func cardSubtitle(_ item: Item) -> String {
        var parts = [item.category == .other && item.isUnnamed ? "Tap a name or type one" : item.category.title]
        if !item.makeAndModel.isEmpty { parts.append(item.makeAndModel) }
        if let price = item.purchasePrice {
            parts.append(price.formatted(.currency(code: currencyCode)) + (item.quantity > 1 ? " each" : ""))
        }
        return parts.joined(separator: " · ")
    }

    private var shutterBar: some View {
        HStack {
            Text(session.isEmpty ? "Point at one thing" : "\(session.count) this session")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await shoot() }
            } label: {
                ZStack {
                    Circle().stroke(shotMode == .item ? .white : .yellow, lineWidth: 4)
                        .frame(width: 76, height: 76)
                    Circle().fill(shotMode == .item ? .white : .yellow)
                        .frame(width: 62, height: 62)
                        .scaleEffect(busy ? 0.86 : 1)
                    if shotMode != .item {
                        Image(systemName: "text.viewfinder").font(.title2).foregroundStyle(.black)
                    }
                }
            }
            .disabled(cameraState != .ready)
            .accessibilityLabel(shotMode == .item ? "Take photo of item" : "Photograph label")
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Chips

    struct Chip: Hashable {
        let label: String
        let name: String
        let category: ItemCategory
        var isSameAsLast = false
    }

    /// Suggestions for this photo, then "same as last", then names already used in this room.
    private var chips: [Chip] {
        var seen = Set<String>()
        var result: [Chip] = []
        func add(_ chip: Chip) {
            guard !chip.name.isEmpty, chip.name != Item.placeholderName,
                  seen.insert(chip.name.lowercased()).inserted else { return }
            result.append(chip)
        }
        for s in suggestions { add(Chip(label: s.name, name: s.name, category: s.category)) }
        if let last = itemBefore(current), !last.isUnnamed {
            add(Chip(label: "Same as last", name: last.name, category: last.category, isSameAsLast: true))
        }
        let recent = room.items
            .filter { !$0.isUnnamed && $0 !== current }
            .sorted { $0.createdAt > $1.createdAt }
        for item in recent.prefix(12) { add(Chip(label: item.name, name: item.name, category: item.category)) }
        return Array(result.prefix(10))
    }

    private func itemBefore(_ item: Item?) -> Item? {
        guard let item, let index = session.firstIndex(where: { $0 === item }), index > 0 else { return nil }
        return session[index - 1]
    }

    // MARK: - Actions

    private func startCamera() async {
        // Load the detector model in the background so the first shot isn't slow.
        Task.detached(priority: .utility) { _ = ObjectDetector.shared.isAvailable }
        guard await CameraController.requestAccess() else { cameraState = .denied; return }
        do {
            try await camera.start()
            cameraState = .ready
        } catch {
            cameraState = .failed(error.localizedDescription)
        }
    }

    private func shoot() async {
        commitDraft()
        nameFocused = false
        busy = true
        withAnimation(.easeOut(duration: 0.1)) { flash = true }
        defer { busy = false }
        let mode = shotMode
        do {
            let data = try await camera.capture()
            withAnimation(.easeIn(duration: 0.2)) { flash = false }
            guard let cg = UIImage(data: data)?.normalizedCGImage(maxDimension: 2400) else {
                throw CameraError.captureFailed
            }
            switch mode {
            case .item: await addItem(from: cg)
            case .label, .receipt: await readDetails(from: cg, isReceipt: mode == .receipt)
            }
        } catch {
            flash = false
            errorMessage = error.localizedDescription
        }
    }

    private func addItem(from image: CGImage) async {
        let item = Item(name: Item.placeholderName,
                        photo: ItemDetector.jpeg(image, maxDimension: 1600, quality: 0.8),
                        needsReview: true)
        item.room = room
        context.insert(item)
        session.append(item)
        current = item
        nameDraft = ""
        suggestions = []

        let result = await suggester.analyze(image)
        // Auto-name only if it's still unnamed (the user may have typed meanwhile).
        if item.isUnnamed, let top = result.autoName {
            item.name = top.name
            item.category = top.category
            if item.brand.isEmpty, let author = result.author { item.brand = author }
            if current === item, nameDraft.isEmpty { nameDraft = top.name }
        }
        if current === item { suggestions = result.chips }
    }

    private func readDetails(from image: CGImage, isReceipt: Bool) async {
        guard let item = current else { shotMode = .item; return }
        shotMode = .item
        if isReceipt { item.receiptPhoto = ItemDetector.jpeg(image, maxDimension: 2000, quality: 0.8) }
        let details = await DetailsExtractor().extract(from: image)
        var filled: [String] = []
        if let v = details.brand, item.brand.isEmpty { item.brand = v; filled.append("brand") }
        if let v = details.model, item.model.isEmpty { item.model = v; filled.append("model") }
        if let v = details.serialNumber, item.serialNumber.isEmpty { item.serialNumber = v; filled.append("serial number") }
        if isReceipt {
            if let v = details.price, item.purchasePrice == nil { item.purchasePrice = v; filled.append("price") }
            if let v = details.purchaseDate, item.purchaseDate == nil { item.purchaseDate = v; filled.append("date") }
        }
        if filled.isEmpty {
            showToast(isReceipt ? "Receipt saved. Couldn't read details from it." : "Couldn't read that label. Try closer.")
        } else {
            showToast("Filled in " + ListFormatter.localizedString(byJoining: filled))
        }
        showingDetails = true
    }

    private func select(_ item: Item) {
        commitDraft()
        current = item
        suggestions = []
        syncDraftFromItem()
    }

    private func apply(name: String, category: ItemCategory, to item: Item) {
        item.name = name
        item.category = category
        item.needsReview = false
        if item === current { nameDraft = name }
        nameFocused = false
    }

    /// Saves whatever is typed in the name field onto the current item.
    private func commitDraft() {
        guard let current else { return }
        let typed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only an actual edit counts as confirming; an untouched auto-name stays "needs review".
        guard !typed.isEmpty, typed != current.name else { return }
        current.name = typed
        current.needsReview = false
    }

    private func syncDraftFromItem() {
        nameDraft = current.map { $0.isUnnamed ? "" : $0.name } ?? ""
    }

    private func undoCurrent() {
        guard let item = current, let index = session.firstIndex(where: { $0 === item }) else { return }
        session.remove(at: index)
        context.delete(item)
        current = session.last
        suggestions = []
        syncDraftFromItem()
        showToast("Photo deleted")
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if toast == text { toast = nil }
        }
    }
}

// MARK: - Small components

struct QuantityControl: View {
    @Binding var quantity: Int

    var body: some View {
        HStack(spacing: 0) {
            Button { if quantity > 1 { quantity -= 1 } } label: {
                Image(systemName: "minus").frame(width: 34, height: 30)
            }
            .disabled(quantity <= 1)
            Text("×\(quantity)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 34)
            Button { quantity += 1 } label: {
                Image(systemName: "plus").frame(width: 34, height: 30)
            }
        }
        .buttonStyle(.borderless)
        .background(.white.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quantity \(quantity)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: quantity += 1
            case .decrement: if quantity > 1 { quantity -= 1 }
            @unknown default: break
            }
        }
    }
}

private struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

/// Corner brackets marking where to aim.
private struct Reticle: View {
    var color: Color = .white

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.68
            let rect = CGRect(x: (geo.size.width - side) / 2, y: (geo.size.height - side) / 2 - 60,
                              width: side, height: side)
            Path { p in
                let l: CGFloat = 30
                for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                         (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                         (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                         (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
                    p.move(to: CGPoint(x: corner.x, y: corner.y + dy * l))
                    p.addLine(to: corner)
                    p.addLine(to: CGPoint(x: corner.x + dx * l, y: corner.y))
                }
            }
            .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.4), radius: 2)
        }
        .allowsHitTesting(false)
    }
}
