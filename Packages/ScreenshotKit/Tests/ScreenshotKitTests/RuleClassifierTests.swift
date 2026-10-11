import ScreenshotKit
import XCTest

final class RuleClassifierTests: XCTestCase {
    private let classifier = RuleClassifier()

    private func input(_ sample: LabeledSample, excluding excluded: Set<ClassificationTarget> = []) -> ClassifierInput {
        var input = sample.classifierInput
        input.excluded = excluded
        return input
    }

    private func labeledCases() throws -> [LabeledSample] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "labeled-ocr", withExtension: "json"))
        return try JSONDecoder().decode([LabeledSample].self, from: Data(contentsOf: url))
    }

    /// Regression guard over synthetic samples. Real accuracy needs a labeled set of actual screenshots.
    func testLabeledSamples() async throws {
        let cases = try labeledCases()
        XCTAssertGreaterThanOrEqual(cases.count, BuiltInCategory.allCases.count * 3)
        for c in cases {
            let verdict = try await classifier.classify(input(c))
            let got: BuiltInCategory? = verdict.flatMap {
                if case let .builtIn(category) = $0.target, $0.confidence >= 0.7 { return category }
                return nil
            }
            XCTAssertEqual(got, c.expected, "\(c.text.replacingOccurrences(of: "\n", with: " / ")) scores: \(classifier.scores(for: input(c)).filter { $0.value > 0 })")
        }
    }

    func testEveryCategoryHasSamples() throws {
        let covered = try Set(labeledCases().compactMap(\.expected))
        XCTAssertEqual(covered, Set(BuiltInCategory.allCases))
    }

    func testCloseCallsReturnNothing() async throws {
        // Receipt and ticket keywords in equal measure.
        let tied = LabeledSample(expected: nil, text: "發票 合計\n航班 座位")
        let verdict = try await classifier.classify(input(tied))
        XCTAssertNil(verdict)
    }

    func testExcludedCategoryIsNeverAnswered() async throws {
        let receipt = LabeledSample(expected: .receipt, text: "電子發票證明聯\n總計 $185")
        let verdict = try await classifier.classify(input(receipt, excluding: [.builtIn(.receipt)]))
        XCTAssertNotEqual(verdict?.target, .builtIn(.receipt))
        XCTAssertNil(classifier.scores(for: input(receipt, excluding: [.builtIn(.receipt)]))[.receipt])
    }

    func testVerdictsComeFromTheRuleLayer() async throws {
        let verdict = try await classifier.classify(input(LabeledSample(expected: .credential, text: "密碼 1234\nWi-Fi")))
        XCTAssertEqual(verdict?.source, .rule)
    }
}
