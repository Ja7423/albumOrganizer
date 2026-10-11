import Foundation

/// Runs the classifier layers in order and keeps the first verdict that clears its layer's threshold.
public struct ClassificationPipeline: Sendable {
    /// Bump whenever any layer's rules, thresholds or prompt change: older automatic results get redone.
    public static let version = 3

    public struct Layer: Sendable {
        public var classifier: any ScreenshotClassifier
        public var threshold: Double

        public init(_ classifier: any ScreenshotClassifier, threshold: Double) {
            self.classifier = classifier
            self.threshold = threshold
        }
    }

    public static let standard = ClassificationPipeline(layers: [Layer(RuleClassifier(), threshold: 0.7)])

    public var layers: [Layer]

    public init(layers: [Layer]) {
        self.layers = layers
    }

    /// `nil` sends the screenshot to 未分類. A layer that throws is skipped rather than failing the batch.
    public func classify(_ input: ClassifierInput) async -> ClassifierVerdict? {
        for layer in layers {
            guard let verdict = try? await layer.classifier.classify(input) else { continue }
            if Self.accepts(verdict, from: layer, for: input) { return verdict }
        }
        return nil
    }

    /// Like `classify`, but a throwing layer ends the run and its error propagates, so the caller can
    /// retry later instead of recording "no answer".
    public func classifyOrThrow(_ input: ClassifierInput) async throws -> ClassifierVerdict? {
        for layer in layers {
            guard let verdict = try await layer.classifier.classify(input) else { continue }
            if Self.accepts(verdict, from: layer, for: input) { return verdict }
        }
        return nil
    }

    private static func accepts(_ verdict: ClassifierVerdict, from layer: Layer, for input: ClassifierInput) -> Bool {
        verdict.confidence >= layer.threshold && !input.excluded.contains(verdict.target)
    }
}
