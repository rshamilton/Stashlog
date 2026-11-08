import CoreGraphics
import Foundation
import FoundationModels
import Vision

/// Structured details pulled from a photo of a label, nameplate, or receipt.
nonisolated struct ExtractedDetails: Sendable, Equatable {
    var brand: String?
    var model: String?
    var serialNumber: String?
    var price: Decimal?
    var purchaseDate: Date?

    var isEmpty: Bool {
        brand == nil && model == nil && serialNumber == nil && price == nil && purchaseDate == nil
    }

    /// Fills only the fields this value is missing.
    func merged(with other: ExtractedDetails) -> ExtractedDetails {
        ExtractedDetails(
            brand: brand ?? other.brand,
            model: model ?? other.model,
            serialNumber: serialNumber ?? other.serialNumber,
            price: price ?? other.price,
            purchaseDate: purchaseDate ?? other.purchaseDate
        )
    }
}

/// Reads text on-device with Vision, then structures it — with Apple's on-device language
/// model when available, otherwise with pattern matching. Never uses a network model.
nonisolated struct DetailsExtractor: Sendable {
    @concurrent
    func extract(from image: CGImage) async -> ExtractedDetails {
        let lines = await recognizeText(in: image)
        guard !lines.isEmpty else { return ExtractedDetails() }
        let parsed = PatternParser.parse(lines)
        if let ai = await OnDeviceDetailsModel.extract(from: lines) {
            // Patterns are precise for serials/prices; the model is better at brand/model.
            return parsed.merged(with: ai)
        }
        return parsed
    }

    func recognizeText(in image: CGImage) async -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false  // serial numbers aren't words
        guard let observations = try? await request.perform(on: image) else { return [] }
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}

// MARK: - Pattern parsing (always available)

nonisolated enum PatternParser {
    static func parse(_ lines: [String]) -> ExtractedDetails {
        var result = ExtractedDetails()
        let joined = lines.joined(separator: "\n")

        result.serialNumber = firstMatch(
            in: joined,
            pattern: #"(?i)\b(?:s\/?n|serial(?:\s*(?:no|number|#))?)\s*[:#.]?\s*([A-Z0-9][A-Z0-9\-]{4,})"#
        )
        result.model = firstMatch(
            in: joined,
            pattern: #"(?i)\b(?:m\/?n|model(?:\s*(?:no|number|#))?|mod\.)\s*[:#.]?\s*([A-Z0-9][A-Z0-9\-\/\.]{2,})"#
        )
        result.price = totalPrice(in: lines)
        result.purchaseDate = firstDate(in: joined)
        return result
    }

    static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r]).uppercased()
    }

    /// Prefers a line labelled TOTAL; otherwise the largest amount on the receipt.
    static func totalPrice(in lines: [String]) -> Decimal? {
        let amount = #"\$?\s?(\d{1,3}(?:,\d{3})*(?:\.\d{2})|\d+\.\d{2})"#
        let totalLines = lines.filter {
            let l = $0.lowercased()
            return l.contains("total") && !l.contains("subtotal")
        }
        if let value = totalLines.compactMap({ amounts(in: $0, pattern: amount).last }).last {
            return value
        }
        return lines.flatMap { amounts(in: $0, pattern: amount) }.max()
    }

    private static func amounts(in line: String, pattern: String) -> [Decimal] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { m in
            guard let r = Range(m.range(at: 1), in: line) else { return nil }
            return Decimal(string: line[r].replacingOccurrences(of: ",", with: ""),
                           locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    static func firstDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.date)
            .first { $0 <= .now && $0 > Date(timeIntervalSince1970: 0) }
    }
}

// MARK: - On-device Foundation Models (iOS 26+, Apple Intelligence devices)

@Generable
nonisolated struct GeneratedDetails {
    @Guide(description: "Manufacturer or brand name, e.g. 'Samsung'. Empty if not present.")
    var brand: String
    @Guide(description: "Model name or model number. Empty if not present.")
    var model: String
    @Guide(description: "Serial number exactly as printed. Empty if not present.")
    var serialNumber: String
}

nonisolated enum OnDeviceDetailsModel {
    static func extract(from lines: [String]) async -> ExtractedDetails? {
        // Explicitly the on-device system model — never Private Cloud Compute.
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }
        let session = LanguageModelSession(
            model: model,
            instructions: """
            You read OCR text from a product label, nameplate, or store receipt and extract \
            the product's brand, model, and serial number. Only use text that is present. \
            Never invent values; leave a field empty if unsure.
            """
        )
        let prompt = "OCR text:\n" + lines.prefix(60).joined(separator: "\n")
        guard let response = try? await session.respond(to: prompt, generating: GeneratedDetails.self) else {
            return nil
        }
        let g = response.content
        func clean(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return ExtractedDetails(brand: clean(g.brand), model: clean(g.model), serialNumber: clean(g.serialNumber))
    }
}
