import Foundation

/// A proposed inventory line, shown on the review screen before anything is saved.
nonisolated struct ScanCandidate: Identifiable, Sendable, Equatable {
    let id: UUID
    let identifier: String
    var name: String
    var category: ItemCategory
    var quantity: Int
    var confidence: Float
    var framesSeen: Int
    var thumbnail: Data?
    var isSelected: Bool
}

/// Merges per-frame detections from a walkthrough into one candidate per item type.
///
/// The same sofa appears in many frames, so detections are grouped by label. Quantity is the
/// most copies of that label seen in any single frame (four chairs in one shot → 4), which
/// avoids counting one chair forty times as the camera pans past it.
nonisolated struct ScanAggregator: Sendable {
    /// Labels seen in only one frame at low confidence are likely noise; start them unselected.
    var preselectConfidence: Float = 0.5

    func aggregate(_ detections: [Detection]) -> [ScanCandidate] {
        let byLabel = Dictionary(grouping: detections, by: \.identifier)
        return byLabel.compactMap { identifier, group -> ScanCandidate? in
            guard let best = group.max(by: { $0.confidence < $1.confidence }) else { return nil }
            let perFrame = Dictionary(grouping: group, by: \.frameTime).values.map(\.count)
            let frames = Set(group.map(\.frameTime)).count
            let preselect = best.confidence >= preselectConfidence || frames >= 2
            return ScanCandidate(
                id: UUID(),
                identifier: identifier,
                name: best.entry.name,
                category: best.entry.category,
                quantity: max(perFrame.max() ?? 1, 1),
                confidence: best.confidence,
                framesSeen: frames,
                thumbnail: best.thumbnail,
                isSelected: preselect
            )
        }
        .sorted { ($0.isSelected ? 1 : 0, $0.confidence) > ($1.isSelected ? 1 : 0, $1.confidence) }
    }
}
