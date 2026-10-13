import Foundation
import NaturalLanguage
import ScreenshotKit

/// The learned layer: a text classifier trained on the device from the user's own placements
/// (`LearnedModelTrainer`). Answers nothing until a model is in place; the model can be swapped while running.
public final class LearnedTextClassifier: ScreenshotClassifier, @unchecked Sendable {
    /// Measured with cross-validation on a real library (doc/classification.md §4): with Apple
    /// Intelligence after it, 0.6 misplaced the fewest screenshots.
    public static let threshold = 0.6

    private let lock = NSLock()
    private var model: NLModel?

    public init(model: NLModel? = nil) {
        self.model = model
    }

    public var isTrained: Bool {
        lock.withLock { model != nil }
    }

    public func use(_ model: NLModel?) {
        lock.withLock { self.model = model }
    }

    public func classify(_ input: ClassifierInput) async throws -> ClassifierVerdict? {
        guard let model = lock.withLock({ model }),
              let best = model.predictedLabelHypotheses(for: TrainingSet.modelText(input.text), maximumCount: 1).first,
              let category = BuiltInCategory(rawValue: best.key)
        else { return nil }
        return ClassifierVerdict(target: .builtIn(category), confidence: best.value, source: .learned)
    }
}

public extension ClassificationPipeline {
    /// The rule layer, then the learned layer for what the rules could not decide.
    static func standard(learned: LearnedTextClassifier) -> ClassificationPipeline {
        ClassificationPipeline(layers: standard.layers + [Layer(learned, threshold: LearnedTextClassifier.threshold)])
    }
}
