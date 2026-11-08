import CoreGraphics
import Foundation
import Vision

nonisolated struct BookCover: Sendable, Equatable {
    let title: String
    let author: String?
}

/// Reads a book's title (and author, if printed) from a photo of its cover, on-device.
/// The title is the largest text in the middle of the frame; a line like "a novel by …"
/// is taken as the author.
nonisolated struct TitleReader: Sendable {
    struct Line: Sendable, Equatable {
        let text: String
        /// Text height as a fraction of the image height.
        let height: CGFloat
        /// Vertical centre, 0 = top.
        let midY: CGFloat
        let midX: CGFloat
    }

    /// Smallest title text worth reading (fraction of image height). Screen/UI text is smaller.
    var minimumTitleHeight: CGFloat = 0.03

    func read(in image: CGImage) async -> BookCover? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        guard let observations = try? await request.perform(on: image) else { return nil }
        let lines = observations.compactMap { o -> Line? in
            guard let text = o.topCandidates(1).first?.string else { return nil }
            let box = o.boundingBox.toImageCoordinates(CGSize(width: 1, height: 1), origin: .upperLeft)
            return Line(text: text, height: box.height, midY: box.midY, midX: box.midX)
        }
        return assemble(lines)
    }

    /// Pure assembly step, separated for testing.
    func assemble(_ lines: [Line]) -> BookCover? {
        let central = lines.filter { abs($0.midX - 0.5) < 0.4 }
        var author: String?
        var titleLines: [Line] = []
        for line in central {
            if let byRange = line.text.range(of: #"\bby\s+"#, options: [.regularExpression, .caseInsensitive]) {
                let name = line.text[byRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { author = author ?? Self.titleCase(name, keepInitials: true) }
            } else {
                titleLines.append(line)
            }
        }
        guard let tallest = titleLines.map(\.height).max(), tallest >= minimumTitleHeight else { return nil }
        let title = titleLines
            .filter { $0.height >= tallest * 0.6 && $0.text.count >= 2 }
            .sorted { $0.midY < $1.midY }
            .map(\.text)
            .joined(separator: " ")
        let cleaned = Self.titleCase(title)
        guard (2...80).contains(cleaned.count), cleaned.contains(where: \.isLetter) else { return nil }
        return BookCover(title: cleaned, author: author)
    }

    private static let smallWords: Set<String> = [
        "a", "an", "and", "as", "at", "but", "by", "for", "in", "of", "on", "or", "the", "to", "with",
    ]

    /// "the CATCHER in the RYE" → "The Catcher in the Rye".
    static func titleCase(_ text: String, keepInitials: Bool = false) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            if keepInitials, word.count <= 3, word.contains(".") { return word.uppercased() }  // "J. D."
            if index > 0, index < words.count - 1, smallWords.contains(lower) { return lower }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
        .joined(separator: " ")
    }
}
