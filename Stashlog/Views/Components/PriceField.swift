import SwiftUI

/// Money entry for a per-unit price. When there's more than one of something, the user can type
/// either the price of one ("Each") or of all of them ("Total"); it's always stored per unit.
struct PriceField: View {
    let title: String
    @Binding var unitPrice: Decimal?
    let quantity: Int
    let currencyCode: String

    @State private var mode: Mode = .each

    enum Mode: String, CaseIterable, Identifiable {
        case each = "Each"
        case total = "Total"
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if unitPrice != nil {
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField(title, value: entered, format: .currency(code: currencyCode))
                    .keyboardType(.decimalPad)
                    .id(mode)  // re-render the text when switching each/total
                if quantity > 1 {
                    Picker("Price is for", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            if quantity > 1, let unitPrice {
                Text(summary(unitPrice))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summary(_ unit: Decimal) -> String {
        switch mode {
        case .each:
            "\((unit * Decimal(quantity)).formatted(.currency(code: currencyCode))) for all \(quantity)"
        case .total:
            "\(unit.formatted(.currency(code: currencyCode))) each"
        }
    }

    private var entered: Binding<Decimal?> {
        Binding {
            guard let unitPrice else { return nil }
            return mode == .total ? unitPrice * Decimal(quantity) : unitPrice
        } set: { value in
            unitPrice = value.map { PriceField.unit(from: $0, mode: mode, quantity: quantity) }
        }
    }

    /// Converts what was typed into a per-unit price, rounded to cents.
    nonisolated static func unit(from value: Decimal, mode: Mode, quantity: Int) -> Decimal {
        guard mode == .total, quantity > 1 else { return value }
        var raw = value / Decimal(quantity)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 2, .bankers)
        return rounded
    }
}
