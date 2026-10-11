import Foundation
import ScreenshotKit
import ScreenshotKitLLM

// Usage: classification-eval <labeled.json> [--rules-only] [--show-errors] [--exclude <key,...>]
// Runs the rule layer on every sample, then Apple Intelligence on the ones the rules left in 未分類,
// exactly as the app does, and prints accuracy for each pass and for both combined.
// `--exclude chat,social` plays a library where those built-ins were deleted.

let usage = "usage: classification-eval <labeled.json> [--rules-only] [--show-errors] [--exclude <key,...>]\n"
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
let rules = try await ClassificationEvaluation.outcomes(of: samples, using: .standard, excluding: excluded)
printer.printPass("規則層（全部 \(samples.count) 筆）", samples: samples, outcomes: rules)

guard !arguments.contains("--rules-only") else { exit(0) }
if #available(macOS 26.0, *) {
    exit(await evaluateAppleIntelligence(samples: samples, rules: rules, printer: printer))
}
print("\nApple Intelligence 需要 macOS 26，只輸出規則層。")
exit(1)

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
    printer.printPass("Apple Intelligence（規則層未分類的 \(unsorted.count) 筆）", samples: unsorted, outcomes: refined)
    printer.printPass("兩層合併（App 的結果）", samples: samples, outcomes: ClassificationEvaluation.cascade(rules, then: refined))
    return 0
}
