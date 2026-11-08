import SwiftData
import SwiftUI

/// Rapid capture: point at one thing, tap, it's saved. Name it with a tap on a chip, by typing,
/// or later. Never makes the user wait before the next shot.
struct CaptureView: View {
    let room: Room

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var camera = CameraController()
    @State private var cameraState: CameraState = .starting
    @State private var current: Item?
    @State private var previous: Item?
    @State private var suggestions: [Suggestion] = []
    @State private var nameDraft = ""
    @State private var captureCount = 0
    @State private var inFlight = 0
    @State private var flash = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    private let suggester = ItemSuggester()

    enum CameraState: Equatable { case starting, ready, denied, failed(String) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch cameraState {
            case .ready, .starting:
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                    .overlay { Reticle() }
                    .overlay { if flash { Color.white.opacity(0.6).ignoresSafeArea() } }
                    .onTapGesture { nameFocused = false }
            case .denied:
                permissionMessage
            case let .failed(message):
                ContentUnavailableView("Camera unavailable", systemImage: "camera.badge.ellipsis",
                                       description: Text(message))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let current { itemCard(current) }
                shutterBar
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .medium), trigger: captureCount)
        .task { await startCamera() }
        .onDisappear {
            commitDraft()
            camera.stop()
        }
        .alert("Couldn't take photo", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(room.name).font(.headline)
                Text("\(room.items.count) items").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { commitDraft(); dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func itemCard(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ItemThumbnail(data: item.photo, category: item.category)
                    .frame(width: 52, height: 52)
                TextField("What is it?", text: $nameDraft)
                    .font(.headline)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { commitDraft() }
                    .textInputAutocapitalization(.sentences)
                Button {
                    item.quantity += 1
                } label: {
                    Text(item.quantity > 1 ? "×\(item.quantity)" : "+1")
                        .font(.subheadline.bold().monospacedDigit())
                        .frame(minWidth: 40, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Add another one, now \(item.quantity)")
                Button("Undo", systemImage: "arrow.uturn.backward") { undoLast() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Button {
                            apply(name: chip.name, category: chip.category, to: item)
                        } label: {
                            Text(chip.label).font(.subheadline).lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .tint(chip.name == item.name && !item.isUnnamed ? .accentColor : .white)
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
    }

    private var shutterBar: some View {
        HStack {
            Text(captureCount == 0 ? "Point at one thing" : "\(captureCount) this session")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await shoot() }
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 74, height: 74)
                    Circle().fill(.white).frame(width: 60, height: 60)
                        .scaleEffect(inFlight > 0 ? 0.85 : 1)
                }
            }
            .disabled(cameraState != .ready)
            .accessibilityLabel("Take photo of item")
            Color.clear.frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
    }

    private var permissionMessage: some View {
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
        .foregroundStyle(.white)
    }

    // MARK: - Chips

    struct Chip: Hashable {
        let label: String
        let name: String
        let category: ItemCategory
    }

    /// Suggestions for this photo, then "same as last", then names already used in this room.
    private var chips: [Chip] {
        var seen = Set<String>()
        var result: [Chip] = []
        func add(_ label: String, _ name: String, _ category: ItemCategory) {
            guard !name.isEmpty, name != Item.placeholderName, seen.insert(name.lowercased()).inserted else { return }
            result.append(Chip(label: label, name: name, category: category))
        }
        for s in suggestions { add(s.name, s.name, s.category) }
        if let previous, !previous.isUnnamed { add("Same as last: \(previous.name)", previous.name, previous.category) }
        let recent = room.items
            .filter { !$0.isUnnamed && $0 !== current }
            .sorted { $0.createdAt > $1.createdAt }
        for item in recent.prefix(12) { add(item.name, item.name, item.category) }
        return Array(result.prefix(10))
    }

    // MARK: - Actions

    private func startCamera() async {
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
        inFlight += 1
        withAnimation(.easeOut(duration: 0.12)) { flash = true }
        defer { inFlight -= 1 }
        do {
            let data = try await camera.capture()
            withAnimation(.easeIn(duration: 0.2)) { flash = false }
            guard let cg = UIImage(data: data)?.normalizedCGImage(maxDimension: 2048) else {
                errorMessage = CameraError.captureFailed.localizedDescription
                return
            }
            let item = Item(name: Item.placeholderName, photo: ItemDetector.jpeg(cg, maxDimension: 1600, quality: 0.8),
                            needsReview: true)
            item.room = room
            context.insert(item)
            previous = current
            current = item
            nameDraft = ""
            suggestions = []
            captureCount += 1

            let found = await suggester.suggestions(for: cg)
            // Auto-name only if the user hasn't named it already (they may have typed meanwhile).
            if item.isUnnamed, let top = suggester.autoName(from: found) {
                item.name = top.name
                item.category = top.category
                if current === item, nameDraft.isEmpty { nameDraft = top.name }
            }
            if current === item { suggestions = found }
        } catch {
            flash = false
            errorMessage = error.localizedDescription
        }
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

    private func undoLast() {
        guard let item = current else { return }
        context.delete(item)
        current = previous
        previous = nil
        nameDraft = current.map { $0.isUnnamed ? "" : $0.name } ?? ""
        suggestions = []
    }
}

/// Corner brackets marking where to aim.
private struct Reticle: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.7
            let rect = CGRect(x: (geo.size.width - side) / 2, y: (geo.size.height - side) / 2 - 40,
                              width: side, height: side)
            Path { p in
                let l: CGFloat = 28
                for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                         (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                         (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                         (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
                    p.move(to: CGPoint(x: corner.x, y: corner.y + dy * l))
                    p.addLine(to: corner)
                    p.addLine(to: CGPoint(x: corner.x + dx * l, y: corner.y))
                }
            }
            .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}
