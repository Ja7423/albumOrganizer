import Foundation
import ScreenshotKit
import ScreenshotKitLLM
import ScreenshotKitML

// Usage: classification-eval <labeled.json> [--rules-only] [--learned] [--show-errors] [--exclude <key,...>]
// Runs the rule layer on every sample, then Apple Intelligence on the ones the rules left in 未分類,
// exactly as the app does, and prints accuracy for each pass and for both combined.
// `--learned` adds the learned layer after the rules, trained with 10-fold cross-validation on the same set.
// `--exclude recipe,shopping` plays a library where those built-ins were deleted.

let usage = "usage: classification-eval <labeled.json> [--rules-only] [--learned] [--show-errors] [--exclude <key,...>]\n"
let arguments = Array(CommandLine.arguments.dropFirst())
let excludeValueIndex = arguments.firstIndex(of: "--exclude").map { $0 + 1 }
guard let path = arguments.indices.first(where: { !arguments[$0].hasPrefix("--") && $0 != excludeValueIndex }).map({ arguments[$0] }) else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}
var excluded: Set<ClassificationTarget> = []
if let excludeValueIndex {
    guard excludeValueIndex < arguments.count else {
        FileHandle.standardError.write(Data(usage.utf8))
        exit(2)
    }
    for key in arguments[excludeValueIndex].split(separator: ",") {
        guard let category = BuiltInCategory(rawValue: String(key)) else {
            FileHandle.standardError.write(Data("unknown category: \(key)\n".utf8))
            exit(2)
        }
        excluded.insert(.builtIn(category))
    }
}
let printer = ReportPrinter(showsErrors: arguments.contains("--show-errors"))

let samples: [LabeledSample]
do {
    samples = try JSONDecoder().decode([LabeledSample].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
} catch {
    FileHandle.standardError.write(Data("cannot read \(path): \(error)\n".utf8))
    exit(2)
}

printer.printOverview(of: samples)
let rules: [EvaluationOutcome]
if arguments.contains("--learned") {
    rules = try await crossValidatedLearnedOutcomes(of: samples, folds: 10, excluding: excluded)
    printer.printPass("規則層 + 學習層（全部 \(samples.count) 筆，10 折交叉驗證）", samples: samples, outcomes: rules)
} else {
    rules = try await ClassificationEvaluation.outcomes(of: samples, using: .standard, excluding: excluded)
    printer.printPass("規則層（全部 \(samples.count) 筆）", samples: samples, outcomes: rules)
}

guard !arguments.contains("--rules-only") else { exit(0) }
if #available(macOS 26.0, *) {
    exit(await evaluateAppleIntelligence(samples: samples, rules: rules, printer: printer))
}
print("\nApple Intelligence 需要 macOS 26，只輸出規則層。")
exit(1)

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
func evaluateAppleIntelligence(samples: [LabeledSample], rules: [EvaluationOutcome], printer: ReportPrinter) async -> Int32 {
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
