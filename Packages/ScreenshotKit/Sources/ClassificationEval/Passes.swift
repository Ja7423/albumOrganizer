import Foundation
import ScreenshotKit
import ScreenshotKitLLM
import ScreenshotKitML

/// Rules then the learned layer, each sample judged by a model trained on the other folds (as in the app,
/// plus the seed samples), so no sample is graded by a model that saw its answer.
func crossValidatedLearnedOutcomes(
    of samples: [LabeledSample],
    folds: Int,
    excluding excluded: Set<ClassificationTarget>
) async throws -> [EvaluationOutcome] {
    let deleted = Set(excluded.compactMap { target -> BuiltInCategory? in
        if case let .builtIn(category) = target { return category }
        return nil
    })
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: scratch) }
    var outcomes = [EvaluationOutcome?](repeating: nil, count: samples.count)
    for fold in 0..<folds {
        let held = samples.indices.filter { $0 % folds == fold }
        let training = samples.indices.filter { $0 % folds != fold }.map { samples[$0] }
        let store = LearnedModelStore(directory: scratch.appendingPathComponent("\(fold)"))
        let model = try await LearnedModelTrainer.train(TrainingSet(samples: training, excluded: deleted), into: store)
        let pipeline = ClassificationPipeline.standard(learned: LearnedTextClassifier(model: model))
        let results = try await ClassificationEvaluation.outcomes(of: held.map { samples[$0] }, using: pipeline, excluding: excluded)
        for (index, outcome) in zip(held, results) { outcomes[index] = outcome }
    }
    return outcomes.map { $0! }
}

/// The refinement pass on what the rules left in 未分類. Returns the exit status.
@available(macOS 26.0, *)
func evaluateAppleIntelligence(
    samples: [LabeledSample],
    rules: [EvaluationOutcome],
    excluding excluded: Set<ClassificationTarget>,
    printer: ReportPrinter
) async -> Int32 {
    let unsorted = ClassificationEvaluation.unsortedIndices(rules).map { samples[$0] }
    let refined: [EvaluationOutcome]
    do {
        refined = try await ClassificationEvaluation.outcomes(of: unsorted, using: .appleIntelligence, excluding: excluded)
    } catch {
        print("\nApple Intelligence 無法使用（\(error)），只輸出規則層。")
        return 1
    }
    printer.printPass("Apple Intelligence（前面各層未分類的 \(unsorted.count) 筆）", samples: unsorted, outcomes: refined)
    printer.printPass("各層合併（App 的結果）", samples: samples, outcomes: ClassificationEvaluation.cascade(rules, then: refined))
    return 0
}
