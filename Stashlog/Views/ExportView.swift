import PDFKit
import SwiftUI

struct ExportView: View {
    let rooms: [Room]
    @Environment(\.dismiss) private var dismiss

    @State private var pdfURL: URL?
    @State private var csvURL: URL?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let pdfURL {
                    PDFPreview(url: pdfURL)
                } else if let error {
                    ContentUnavailableView("Export failed", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else {
                    ProgressView("Building report…")
                }
            }
            .navigationTitle("Insurance Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    if let pdfURL {
                        ShareLink(item: pdfURL) { Label("Share PDF", systemImage: "doc.richtext") }
                    }
                    Spacer()
                    if let csvURL {
                        ShareLink(item: csvURL) { Label("Share CSV", systemImage: "tablecells") }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                Text("Keep a copy somewhere other than this phone — iCloud Drive, email, or a USB drive — so it survives if the phone doesn't.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
        }
        .task { build() }
    }

    private func build() {
        let report = InventoryReport(rooms: rooms)
        let stamp = report.generatedAt.formatted(.iso8601.year().month().day())
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let pdf = dir.appendingPathComponent("Home Inventory \(stamp).pdf")
            let csv = dir.appendingPathComponent("Home Inventory \(stamp).csv")
            try report.pdfData().write(to: pdf, options: [.atomic, .completeFileProtection])
            try Data(report.csv().utf8).write(to: csv, options: [.atomic, .completeFileProtection])
            pdfURL = pdf
            csvURL = csv
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
