import XCTest
import ScreenshotKit

final class RuleClassifierTests: XCTestCase {
    private struct LabeledCase: Decodable {
        var text: String
        var expected: BuiltInCategory?
        var layout: String?
        var barcodes: Int?
    }

    private let classifier = RuleClassifier()

    private func input(_ c: LabeledCase, excluding excluded: Set<ClassificationTarget> = []) -> ClassifierInput {
        let lines = c.text.split(separator: "\n").map(String.init)
        let blocks = lines.enumerated().map { index, line in
            let isRight = c.layout == "chat" && index.isMultiple(of: 2) == false
            let box = NormalizedRect(x: isRight ? 0.5 : 0.05, y: 0.1 + Double(index) * 0.05, width: c.layout == "chat" ? 0.42 : 0.9, height: 0.02)
            return TextBlock(id: index, text: line, box: box)
        }
        let barcodes = Array(repeating: "payload", count: c.barcodes ?? 0)
        return ClassifierInput(text: c.text, signals: SignalExtractor.extract(blocks: blocks, barcodes: barcodes), excluded: excluded)
    }

    private func labeledCases() throws -> [LabeledCase] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "labeled-ocr", withExtension: "json"))
        return try JSONDecoder().decode([LabeledCase].self, from: Data(contentsOf: url))
    }

    /// Regression guard over synthetic samples. Real accuracy needs a labeled set of actual screenshots.
    func testLabeledSamples() async throws {
        let cases = try labeledCases()
        XCTAssertGreaterThanOrEqual(cases.count, BuiltInCategory.allCases.count * 3)
        for c in cases {
            let verdict = try await classifier.classify(input(c))
            let got: BuiltInCategory? = verdict.flatMap {
                if case .builtIn(let category) = $0.target, $0.confidence >= 0.7 { return category }
                return nil
            }
            XCTAssertEqual(got, c.expected, "\(c.text.replacingOccurrences(of: "\n", with: " / ")) scores: \(classifier.scores(for: input(c)).filter { $0.value > 0 })")
        }
    }

    func testEveryCategoryHasSamples() throws {
        let covered = Set(try labeledCases().compactMap(\.expected))
        XCTAssertEqual(covered, Set(BuiltInCategory.allCases))
    }

    func testCloseCallsReturnNothing() async throws {
        // Receipt and ticket keywords in equal measure.
        let tied = LabeledCase(text: "發票 合計\n航班 座位", expected: nil)
        let verdict = try await classifier.classify(input(tied))
        XCTAssertNil(verdict)
    }

    func testExcludedCategoryIsNeverAnswered() async throws {
        let receipt = LabeledCase(text: "電子發票證明聯\n總計 $185", expected: .receipt)
        let verdict = try await classifier.classify(input(receipt, excluding: [.builtIn(.receipt)]))
        XCTAssertNotEqual(verdict?.target, .builtIn(.receipt))
        XCTAssertNil(classifier.scores(for: input(receipt, excluding: [.builtIn(.receipt)]))[.receipt])
    }

    func testVerdictsComeFromTheRuleLayer() async throws {
        let verdict = try await classifier.classify(input(LabeledCase(text: "密碼 1234\nWi-Fi", expected: .credential)))
        XCTAssertEqual(verdict?.source, .rule)
    }
}
