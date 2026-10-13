import Foundation

/// Accuracy figures for a set of outcomes. Putting a screenshot in the wrong folder is worse than leaving
/// it in 未分類, so precision and `misplacementRate` matter more than recall.
public struct EvaluationReport: Sendable {
    public struct CategoryMetrics: Hashable, Sendable {
        /// Samples whose right answer is this category.
        public var support: Int
        /// Samples the classifiers put in this category.
        public var placed: Int
        /// Samples put in this category that belong there.
        public var correct: Int

        /// `nil` when nothing was put in this category.
        public var precision: Double? { ratio(correct, placed) }
        /// `nil` when no sample belongs to this category.
        public var recall: Double? { ratio(correct, support) }
    }

    public let total: Int
    public let categories: [BuiltInCategory: CategoryMetrics]
    /// How many samples had each (expected, predicted) pair.
    public let confusion: [EvaluationOutcome: Int]

    public init(_ outcomes: [EvaluationOutcome]) {
        total = outcomes.count
        confusion = outcomes.reduce(into: [:]) { counts, outcome in counts[outcome, default: 0] += 1 }
        categories = Dictionary(uniqueKeysWithValues: BuiltInCategory.allCases.map { category in
            (category, CategoryMetrics(
                support: outcomes.filter { $0.expected == category }.count,
                placed: outcomes.filter { $0.predicted == category }.count,
                correct: outcomes.filter { $0.expected == category && $0.predicted == category }.count
            ))
        })
    }

    public func count(expected: BuiltInCategory?, predicted: BuiltInCategory?) -> Int {
        confusion[EvaluationOutcome(expected: expected, predicted: predicted)] ?? 0
    }

    /// Put in a folder that is not the right answer, including screenshots that belong in 未分類.
    public var misplaced: Int {
        confusion.filter { $0.key.predicted != nil && $0.key.predicted != $0.key.expected }.values.reduce(0, +)
    }

    /// Left in 未分類, whatever the right answer.
    public var unsorted: Int {
        confusion.filter { $0.key.predicted == nil }.values.reduce(0, +)
    }

    /// Put in a folder at all.
    public var placed: Int { total - unsorted }

    /// Share of all samples put in the wrong folder.
    public var misplacementRate: Double? { ratio(misplaced, total) }
    /// Share of all samples left in 未分類.
    public var unsortedRate: Double? { ratio(unsorted, total) }
    /// Share of the samples put in a folder that went to the right one.
    public var placedPrecision: Double? { ratio(placed - misplaced, placed) }
    /// Share of the samples whose right answer is 未分類 that stayed there.
    public var noneAccuracy: Double? {
        let belongInNone = confusion.filter { $0.key.expected == nil }.values.reduce(0, +)
        return ratio(count(expected: nil, predicted: nil), belongInNone)
    }
}

private func ratio(_ part: Int, _ whole: Int) -> Double? {
    whole > 0 ? Double(part) / Double(whole) : nil
}
