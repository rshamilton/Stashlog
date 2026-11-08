import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Room.sortIndex) private var rooms: [Room]
    @AppStorage(SettingsKey.currencyCode) private var currencyCode = Locale.defaultCurrencyCode

    @State private var showingAddRoom = false
    @State private var showingExport = false
    @State private var showingSettings = false

    private var grandTotal: Decimal { rooms.reduce(0) { $0 + $1.totalValue } }
    private var itemCount: Int { rooms.reduce(0) { $0 + $1.items.count } }

    var body: some View {
        NavigationStack {
            Group {
                if rooms.isEmpty {
                    ContentUnavailableView {
                        Label("Start with a room", systemImage: "house")
                    } description: {
                        Text("Add a room, then point your camera at each thing in it and tap. Stashlog suggests names, and nothing is uploaded.")
                    } actions: {
                        Button("Add a Room") { showingAddRoom = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            LabeledContent("Items", value: "\(itemCount)")
                            LabeledContent("Estimated value") {
                                Text(grandTotal, format: .currency(code: currencyCode)).bold()
                            }
                        }
                        Section("Rooms") {
                            ForEach(rooms) { room in
                                NavigationLink(value: room) { RoomRow(room: room, currencyCode: currencyCode) }
                            }
                            .onDelete(perform: deleteRooms)
                            .onMove(perform: moveRooms)
                        }
                    }
                }
            }
            .navigationTitle("Stashlog")
            .navigationDestination(for: Room.self) { RoomDetailView(room: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Export", systemImage: "square.and.arrow.up") { showingExport = true }
                        .disabled(itemCount == 0)
                    Button("Add Room", systemImage: "plus") { showingAddRoom = true }
                }
            }
            .sheet(isPresented: $showingAddRoom) { AddRoomView(nextIndex: (rooms.map(\.sortIndex).max() ?? -1) + 1) }
            .sheet(isPresented: $showingExport) { ExportView(rooms: rooms) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }

    private func deleteRooms(at offsets: IndexSet) {
        for index in offsets { context.delete(rooms[index]) }
    }

    private func moveRooms(from source: IndexSet, to destination: Int) {
        var ordered = rooms
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, room) in ordered.enumerated() { room.sortIndex = index }
    }
}

private struct RoomRow: View {
    let room: Room
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: room.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading) {
                Text(room.name).font(.headline)
                Text("\(room.items.count) items").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(room.totalValue, format: .currency(code: currencyCode))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

struct AddRoomView: View {
    let nextIndex: Int
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Room name", text: $name)
                Section("Suggestions") {
                    ForEach(Room.suggestions, id: \.self) { suggestion in
                        Button(suggestion) { add(suggestion) }
                    }
                }
            }
            .navigationTitle("New Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add(name) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        context.insert(Room(name: trimmed, symbol: Room.defaultSymbol(for: trimmed), sortIndex: nextIndex))
        dismiss()
    }
}
