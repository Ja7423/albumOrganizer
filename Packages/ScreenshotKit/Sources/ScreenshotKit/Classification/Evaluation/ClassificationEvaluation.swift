import Foundation

/// The right answer and what the classifiers decided for one sample; `nil` is 未分類.
public struct EvaluationOutcome: Hashable, Sendable {
    public var expected: BuiltInCategory?
    public var predicted: BuiltInCategory?

    public init(expected: BuiltInCategory?, predicted: BuiltInCategory?) {
        self.expected = expected
        self.predicted = predicted
    }
}

public enum ClassificationEvaluation {
    /// One outcome per sample, in order, using the pipeline's thresholds. Throws when a layer cannot
    /// answer right now (e.g. the model is unavailable), so that is never counted as "no answer".
    public static func outcomes(of samples: [LabeledSample], using pipeline: ClassificationPipeline) async throws -> [EvaluationOutcome] {
        var outcomes: [EvaluationOutcome] = []
        outcomes.reserveCapacity(samples.count)
        for sample in samples {
            let verdict = try await pipeline.classifyOrThrow(sample.classifierInput)
            outcomes.append(EvaluationOutcome(expected: sample.expected, predicted: verdict.flatMap(builtInCategory)))
        }
        return outcomes
    }

    /// Indices of the samples a pass left in 未分類: the ones the next pass gets, as in the app.
    public static func unsortedIndices(_ outcomes: [EvaluationOutcome]) -> [Int] {
        outcomes.indices.filter { outcomes[$0].predicted == nil }
    }

    /// The first pass's answers, with each sample it left in 未分類 replaced by the second pass's outcome.
    /// `second` holds one outcome per index in `unsortedIndices(first)`, in the same order.
    public static func cascade(_ first: [EvaluationOutcome], then second: [EvaluationOutcome]) -> [EvaluationOutcome] {
        var combined = first
        for (index, outcome) in zip(unsortedIndices(first), second) {
            combined[index] = outcome
        }
        return combined
    }

    private static func builtInCategory(_ verdict: ClassifierVerdict) -> BuiltInCategory? {
        guard case let .builtIn(category) = verdict.target else { return nil }
        return category
    }
}
