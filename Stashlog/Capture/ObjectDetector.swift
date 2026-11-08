import CoreGraphics
import CoreML
import Foundation
import Vision
import os

/// One entry of the detector's vocabulary: what the model looks for, and how we show it.
nonisolated struct VocabularyEntry: Decodable, Sendable {
    let prompt: String
    let name: String
    let category: ItemCategory
}

/// An object found in a photo by the household detector.
nonisolated struct DetectedObject: Sendable, Equatable {
    let name: String
    let category: ItemCategory
    let confidence: Float
    /// Normalized to 0...1, origin top-left.
    let box: CGRect

    /// How likely this is the thing the user aimed at: confident, near the centre, and not tiny.
    var focusScore: Float {
        let dx = box.midX - 0.5, dy = box.midY - 0.45  // the reticle sits slightly above centre
        let centrality = max(0, 1 - sqrt(dx * dx + dy * dy) / 0.5)
        let size = min(1, (box.width * box.height) / 0.12)
        return confidence * Float(0.35 + 0.65 * centrality) * Float(0.45 + 0.55 * size)
    }
}

/// Open-vocabulary household object detector (YOLO-World v2 with Stashlog's vocabulary baked in),
/// running entirely on-device through Core ML. See tools/detector/ to rebuild it.
nonisolated final class ObjectDetector: Sendable {
    static let shared = ObjectDetector()
    static let log = Logger(subsystem: "com.rshamilton.stashlog", category: "ObjectDetector")

    private let container: CoreMLModelContainer?
    private let vocabulary: [String: VocabularyEntry]

    init(bundle: Bundle = .main) {
        vocabulary = Self.loadVocabulary(from: bundle)
        container = Self.loadModel(from: bundle)
    }

    var isAvailable: Bool { container != nil }
    var vocabularySize: Int { vocabulary.count }

    func detect(in image: CGImage) async -> [DetectedObject] {
        guard let container else { return [] }
        var request = CoreMLRequest(model: container)
        request.cropAndScaleAction = .scaleToFill
        let results: [any VisionObservation]
        do {
            results = try await request.perform(on: image)
        } catch {
            Self.log.error("Detection failed: \(String(describing: error))")
            return []
        }
        return results
            .compactMap { $0 as? RecognizedObjectObservation }
            .compactMap { observation in
                guard let top = observation.labels.first, let entry = vocabulary[top.identifier] else { return nil }
                let box = observation.boundingBox.toImageCoordinates(CGSize(width: 1, height: 1), origin: .upperLeft)
                return DetectedObject(name: entry.name, category: entry.category, confidence: top.confidence, box: box)
            }
            .sorted { $0.focusScore > $1.focusScore }
    }

    private static func loadVocabulary(from bundle: Bundle) -> [String: VocabularyEntry] {
        struct File: Decodable { let classes: [VocabularyEntry] }
        guard let url = bundle.url(forResource: "DetectorVocabulary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            log.error("Detector vocabulary missing")
            return [:]
        }
        return Dictionary(file.classes.map { ($0.prompt, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func loadModel(from bundle: Bundle) -> CoreMLModelContainer? {
        guard let url = bundle.url(forResource: "HouseholdDetector", withExtension: "mlmodelc") else {
            log.error("Detector model missing from bundle")
            return nil
        }
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let model = try MLModel(contentsOf: url, configuration: configuration)
            let thresholds = try MLDictionaryFeatureProvider(dictionary: [
                "iouThreshold": 0.45,
                "confidenceThreshold": 0.08,
            ])
            return try CoreMLModelContainer(model: model, featureProvider: thresholds)
        } catch {
            log.error("Couldn't load detector: \(String(describing: error))")
            return nil
        }
    }
}
