import Foundation
import UIKit

/// A plain-value snapshot of the inventory, so rendering never touches live SwiftData objects.
struct InventoryReport {
    struct Line {
        var name: String
        var category: String
        var quantity: Int
        var makeAndModel: String
        var serialNumber: String
        var purchaseDate: Date?
        var purchasePrice: Decimal?
        var unitValue: Decimal?
        var total: Decimal
        var notes: String
        var photo: Data?
        var receipt: Data?
    }

    struct RoomSection {
        var name: String
        var lines: [Line]
        var total: Decimal { lines.reduce(0) { $0 + $1.total } }
    }

    var ownerName: String
    var address: String
    var insurer: String
    var policyNumber: String
    var currencyCode: String
    var generatedAt: Date
    var rooms: [RoomSection]

    var grandTotal: Decimal { rooms.reduce(0) { $0 + $1.total } }
    var itemCount: Int { rooms.reduce(0) { $0 + $1.lines.reduce(0) { $0 + max($1.quantity, 1) } } }

    init(rooms: [Room], defaults: UserDefaults = .standard, now: Date = .now) {
        ownerName = defaults.string(forKey: SettingsKey.ownerName) ?? ""
        address = defaults.string(forKey: SettingsKey.propertyAddress) ?? ""
        insurer = defaults.string(forKey: SettingsKey.insurer) ?? ""
        policyNumber = defaults.string(forKey: SettingsKey.policyNumber) ?? ""
        currencyCode = defaults.string(forKey: SettingsKey.currencyCode) ?? Locale.defaultCurrencyCode
        generatedAt = now
        self.rooms = rooms.sorted { $0.sortIndex < $1.sortIndex }.map { room in
            RoomSection(name: room.name, lines: room.sortedItems.map { item in
                Line(
                    name: item.name, category: item.category.title, quantity: item.quantity,
                    makeAndModel: item.makeAndModel, serialNumber: item.serialNumber,
                    purchaseDate: item.purchaseDate, purchasePrice: item.purchasePrice,
                    unitValue: item.unitValue, total: item.insuredValue, notes: item.notes,
                    photo: item.photo, receipt: item.receiptPhoto
                )
            })
        }
    }

    func money(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: currencyCode))
    }
}

// MARK: - CSV

extension InventoryReport {
    func csv() -> String {
        let header = ["Room", "Item", "Category", "Quantity", "Make/Model", "Serial Number",
                      "Purchase Date", "Purchase Price", "Unit Value", "Total Value", "Notes"]
        var rows = [header]
        for room in rooms {
            for l in room.lines {
                rows.append([
                    room.name, l.name, l.category, String(l.quantity), l.makeAndModel, l.serialNumber,
                    l.purchaseDate?.formatted(.iso8601.year().month().day()) ?? "",
                    l.purchasePrice.map { "\($0)" } ?? "", l.unitValue.map { "\($0)" } ?? "",
                    "\(l.total)", l.notes,
                ])
            }
        }
        return rows.map { $0.map(Self.escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - PDF

extension InventoryReport {
    nonisolated private enum Layout {
        static let page = CGRect(x: 0, y: 0, width: 612, height: 792)  // US Letter, points
        static let margin: CGFloat = 40
        static let thumb: CGFloat = 56
        static let rowHeight: CGFloat = 68
        static var content: CGRect { page.insetBy(dx: margin, dy: margin) }
    }

    func pdfData() -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: Layout.page, format: {
            let f = UIGraphicsPDFRendererFormat()
            f.documentInfo = [
                kCGPDFContextTitle as String: "Home Inventory",
                kCGPDFContextCreator as String: "Stashlog",
            ]
            return f
        }())

        return renderer.pdfData { ctx in
            var y = Layout.content.minY
            func newPage() { ctx.beginPage(); y = Layout.content.minY }
            func ensure(_ height: CGFloat) { if y + height > Layout.content.maxY { newPage() } }

            // Cover / summary
            newPage()
            y = draw("Home Inventory", font: .boldSystemFont(ofSize: 26), at: y)
            y = draw("Generated \(generatedAt.formatted(date: .long, time: .shortened)) with Stashlog",
                     font: .systemFont(ofSize: 10), color: .darkGray, at: y + 2)
            y += 14
            for (label, value) in [("Policyholder", ownerName), ("Property", address),
                                   ("Insurer", insurer), ("Policy number", policyNumber)] where !value.isEmpty {
                y = drawPair(label, value, at: y)
            }
            y += 10
            y = drawPair("Items", "\(itemCount)", at: y, bold: true)
            y = drawPair("Total estimated value", money(grandTotal), at: y, bold: true)
            y += 16
            y = draw("By room", font: .boldSystemFont(ofSize: 14), at: y)
            for room in rooms {
                ensure(18)
                y = drawPair(room.name, "\(room.lines.count) lines · \(money(room.total))", at: y)
            }

            // Room sections
            for room in rooms where !room.lines.isEmpty {
                newPage()
                y = draw(room.name, font: .boldSystemFont(ofSize: 20), at: y)
                y = draw("Room total: \(money(room.total))", font: .systemFont(ofSize: 11),
                         color: .darkGray, at: y + 2)
                y += 10
                for line in room.lines {
                    ensure(Layout.rowHeight)
                    drawRow(line, at: y)
                    y += Layout.rowHeight
                }
            }

            // Receipts appendix
            let receipts = rooms.flatMap { room in room.lines.compactMap { l in
                l.receipt.flatMap(UIImage.init(data:)).map { ("\(room.name) — \(l.name)", $0) }
            } }
            if !receipts.isEmpty {
                for (title, image) in receipts {
                    newPage()
                    y = draw("Receipt: \(title)", font: .boldSystemFont(ofSize: 14), at: y)
                    let box = CGRect(x: Layout.content.minX, y: y + 8, width: Layout.content.width,
                                     height: Layout.content.maxY - y - 8)
                    image.draw(in: Self.aspectFit(image.size, in: box))
                }
            }
        }
    }

    private func drawRow(_ line: Line, at y: CGFloat) {
        let x = Layout.content.minX
        let thumbRect = CGRect(x: x, y: y, width: Layout.thumb, height: Layout.thumb)
        if let data = line.photo, let image = UIImage(data: data) {
            // The rounded clip must not leak into the rest of the page.
            let cg = UIGraphicsGetCurrentContext()
            cg?.saveGState()
            image.draw(in: Self.aspectFill(image.size, in: thumbRect, clip: true))
            cg?.restoreGState()
        } else {
            UIColor(white: 0.92, alpha: 1).setFill()
            UIBezierPath(roundedRect: thumbRect, cornerRadius: 6).fill()
        }

        let textX = x + Layout.thumb + 10
        let valueWidth: CGFloat = 110
        let textWidth = Layout.content.maxX - textX - valueWidth - 8
        let title = line.quantity > 1 ? "\(line.name) ×\(line.quantity)" : line.name
        _ = draw(title, font: .boldSystemFont(ofSize: 12), at: y, x: textX, width: textWidth)

        var details = [line.category]
        if !line.makeAndModel.isEmpty { details.append(line.makeAndModel) }
        if !line.serialNumber.isEmpty { details.append("S/N \(line.serialNumber)") }
        if let d = line.purchaseDate { details.append("Bought \(d.formatted(date: .abbreviated, time: .omitted))") }
        if line.receipt != nil { details.append("Receipt attached") }
        _ = draw(details.joined(separator: " · "), font: .systemFont(ofSize: 9), color: .darkGray,
                 at: y + 16, x: textX, width: textWidth)
        if !line.notes.isEmpty {
            _ = draw(line.notes, font: .italicSystemFont(ofSize: 9), color: .darkGray,
                     at: y + 40, x: textX, width: textWidth, maxLines: 1)
        }

        let valueX = Layout.content.maxX - valueWidth
        _ = draw(money(line.total), font: .boldSystemFont(ofSize: 12), at: y, x: valueX,
                 width: valueWidth, alignment: .right)
        if line.quantity > 1 {
            _ = draw("\(money(line.unitValue)) each", font: .systemFont(ofSize: 9), color: .darkGray,
                     at: y + 16, x: valueX, width: valueWidth, alignment: .right)
        }

        UIColor(white: 0.82, alpha: 1).setStroke()
        let rule = UIBezierPath()
        rule.move(to: CGPoint(x: x, y: y + Layout.rowHeight - 6))
        rule.addLine(to: CGPoint(x: Layout.content.maxX, y: y + Layout.rowHeight - 6))
        rule.lineWidth = 0.5
        rule.stroke()
    }

    @discardableResult
    private func draw(
        _ text: String, font: UIFont, color: UIColor = .black, at y: CGFloat,
        x: CGFloat = Layout.content.minX, width: CGFloat = Layout.content.width,
        alignment: NSTextAlignment = .left, maxLines: Int = 0
    ) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = maxLines == 1 ? .byTruncatingTail : .byWordWrapping
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style,
        ])
        let limit = maxLines > 0 ? font.lineHeight * CGFloat(maxLines) + 1 : .greatestFiniteMagnitude
        let bounds = attributed.boundingRect(
            with: CGSize(width: width, height: limit), options: [.usesLineFragmentOrigin], context: nil
        )
        let height = min(ceil(bounds.height), limit)
        attributed.draw(with: CGRect(x: x, y: y, width: width, height: height),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        return y + height
    }

    private func drawPair(_ label: String, _ value: String, at y: CGFloat, bold: Bool = false) -> CGFloat {
        let font: UIFont = bold ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 12)
        draw(label, font: font, color: .darkGray, at: y, width: 180)
        let end = draw(value, font: font, at: y, x: Layout.content.minX + 190,
                       width: Layout.content.width - 190)
        return end + 4
    }

    static func aspectFit(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: box.midX - w / 2, y: box.minY, width: w, height: h)
    }

    static func aspectFill(_ size: CGSize, in box: CGRect, clip: Bool) -> CGRect {
        guard size.width > 0, size.height > 0 else { return box }
        if clip { UIBezierPath(roundedRect: box, cornerRadius: 6).addClip() }
        let scale = max(box.width / size.width, box.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }
}
