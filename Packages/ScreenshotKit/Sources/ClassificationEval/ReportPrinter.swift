import Foundation
import ScreenshotKit

/// Lays out `EvaluationReport`s as plain-text tables. All the numbers come from the report.
struct ReportPrinter {
    var showsErrors: Bool

    private static let noneLabel = "none"

    func printOverview(of samples: [LabeledSample]) {
        let belongInNone = samples.filter { $0.expected == nil }.count
        print("評估集：\(samples.count) 筆（應放進資料夾 \(samples.count - belongInNone)、應留在未分類 \(belongInNone)）")
    }

    func printPass(_ title: String, samples: [LabeledSample], outcomes: [EvaluationOutcome]) {
        let report = EvaluationReport(outcomes)
        print("\n== \(title) ==")
        printCategories(report)
        printSummary(report)
        printConfusion(report)
        if showsErrors { printMisplaced(samples: samples, outcomes: outcomes) }
    }

    private func printCategories(_ report: EvaluationReport) {
        print(row(["category", "support", "placed", "correct", "precision", "recall"]))
        for category in BuiltInCategory.allCases {
            guard let metrics = report.categories[category], metrics.support + metrics.placed > 0 else { continue }
            print(row([category.rawValue, "\(metrics.support)", "\(metrics.placed)", "\(metrics.correct)",
                       percent(metrics.precision), percent(metrics.recall)]))
        }
    }

    private func printSummary(_ report: EvaluationReport) {
        print("錯放率 \(percent(report.misplacementRate))（\(report.misplaced)/\(report.total)）")
        print("未分類率 \(percent(report.unsortedRate))（\(report.unsorted)/\(report.total)）")
        print("放入資料夾的正確率 \(percent(report.placedPrecision))（\(report.placed - report.misplaced)/\(report.placed)）")
        print("應留在未分類、也留住的比例 \(percent(report.noneAccuracy))")
    }

    /// Rows are right answers, columns are what the classifiers decided; rows with no samples are left out.
    private func printConfusion(_ report: EvaluationReport) {
        let labels: [BuiltInCategory?] = BuiltInCategory.allCases + [nil]
        print("混淆矩陣（列：正解，欄：結果）")
        print(row([""] + labels.map(shortLabel), width: 6))
        for expected in labels {
            let counts = labels.map { report.count(expected: expected, predicted: $0) }
            guard counts.contains(where: { $0 > 0 }) else { continue }
            print(row([shortLabel(expected)] + counts.map { $0 == 0 ? "." : "\($0)" }, width: 6))
        }
    }

    private func printMisplaced(samples: [LabeledSample], outcomes: [EvaluationOutcome]) {
        let misplaced = zip(samples, outcomes).filter { $1.predicted != nil && $1.predicted != $1.expected }
        guard !misplaced.isEmpty else { return }
        print("放錯的樣本")
        for (sample, outcome) in misplaced {
            let text = sample.text.replacingOccurrences(of: "\n", with: " / ").prefix(60)
            print("  \(label(outcome.expected)) → \(label(outcome.predicted))  \(sample.id ?? "-")  \(text)")
        }
    }

    private func label(_ category: BuiltInCategory?) -> String {
        category?.rawValue ?? Self.noneLabel
    }

    private func shortLabel(_ category: BuiltInCategory?) -> String {
        String(label(category).prefix(5))
    }

    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0 * 100) } ?? "-"
    }

    private func row(_ cells: [String], width: Int = 11) -> String {
        cells.map { $0.padding(toLength: max(width, $0.count), withPad: " ", startingAt: 0) }.joined()
    }
}
