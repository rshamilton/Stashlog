import SwiftData
import SwiftUI

/// Shows a running scan and lets the user confirm which suggestions become inventory items.
/// The scan itself is owned by `ScanSession`, not this view, so rebuilding the sheet can't stop it.
struct ScanReviewView: View {
    let room: Room
    @Bindable var session: ScanSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var selectedCount: Int { session.candidates.filter(\.isSelected).count }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Review Items")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { session.cancel(); dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add \(selectedCount)") { save() }
                            .disabled(session.phase != .finished || selectedCount == 0)
                    }
                }
        }
        // Swiping away mid-scan would leave it running unseen; use Cancel instead.
        .interactiveDismissDisabled(session.isRunning || (session.phase == .finished && selectedCount > 0))
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .starting, .extractingFrames, .detecting:
            VStack(spacing: 16) {
                ProgressView(value: session.progress)
                    .frame(maxWidth: 260)
                Text(statusText).font(.headline)
                Label("Processing on this iPhone. Nothing is uploaded.", systemImage: "lock.iphone")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .cancelled:
            ContentUnavailableView("Scan cancelled", systemImage: "xmark.circle")
        case let .failed(message):
            ContentUnavailableView("Scan failed", systemImage: "exclamationmark.triangle", description: Text(message))
        case .finished where session.candidates.isEmpty:
            ContentUnavailableView {
                Label("Nothing recognized", systemImage: "eye.slash")
            } description: {
                Text("Try a slower pan with good lighting, or add items manually.")
            }
        case .finished:
            List {
                Section {
                    ForEach($session.candidates) { $candidate in
                        CandidateRow(candidate: $candidate)
                    }
                } footer: {
                    Text("Suggestions are a starting point. You can rename items and add brand, serial number, value, and receipts afterwards.")
                }
            }
        }
    }

    private var statusText: String {
        switch session.phase {
        case .extractingFrames: "Reading video…"
        case let .detecting(done, total): "Looking for items… \(done)/\(total)"
        default: "Starting…"
        }
    }

    private func save() {
        for candidate in session.candidates where candidate.isSelected {
            let item = Item(
                name: candidate.name,
                category: candidate.category,
                quantity: candidate.quantity,
                photo: candidate.thumbnail,
                needsReview: true
            )
            item.room = room
            context.insert(item)
        }
        dismiss()
    }
}

private struct CandidateRow: View {
    @Binding var candidate: ScanCandidate

    var body: some View {
        HStack(spacing: 12) {
            Button {
                candidate.isSelected.toggle()
            } label: {
                Image(systemName: candidate.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(candidate.isSelected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(candidate.isSelected ? "Selected" : "Not selected")

            ItemThumbnail(data: candidate.thumbnail, category: candidate.category)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: $candidate.name).font(.headline)
                Text("\(candidate.category.title) · \(Int(candidate.confidence * 100))% match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Stepper(value: $candidate.quantity, in: 1...99) {
                Text("×\(candidate.quantity)").monospacedDigit()
            }
            .fixedSize()
        }
        .opacity(candidate.isSelected ? 1 : 0.6)
    }
}
