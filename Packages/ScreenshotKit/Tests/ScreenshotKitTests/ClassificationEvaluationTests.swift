import ScreenshotKit
import XCTest

final class ClassificationEvaluationTests: XCTestCase {
    private func outcome(_ expected: BuiltInCategory?, _ predicted: BuiltInCategory?) -> EvaluationOutcome {
        EvaluationOutcome(expected: expected, predicted: predicted)
    }

    // MARK: EvaluationReport

    func testPerCategoryPrecisionAndRecall() throws {
        let report = EvaluationReport([
            outcome(.receipt, .receipt),
            outcome(.receipt, nil),
            outcome(.ticket, .receipt),
            outcome(nil, .receipt),
        ])
        let receipt = try XCTUnwrap(report.categories[.receipt])
        XCTAssertEqual([receipt.support, receipt.placed, receipt.correct], [2, 3, 1])
        XCTAssertEqual(try XCTUnwrap(receipt.precision), 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(receipt.recall, 0.5)
        XCTAssertEqual(report.categories[.ticket]?.recall, 0)
    }

    func testRatiosAreNilWithoutADenominator() {
        let report = EvaluationReport([outcome(.recipe, nil)])
        XCTAssertNil(report.categories[.recipe]?.precision)
        XCTAssertNil(report.categories[.note]?.recall)
        XCTAssertNil(report.placedPrecision)
        XCTAssertNil(report.noneAccuracy)
        XCTAssertNil(EvaluationReport([]).misplacementRate)
    }

    func testPlacingAScreenThatBelongsInNoneIsMisplaced() {
        let report = EvaluationReport([
            outcome(nil, .code),
            outcome(nil, nil),
            outcome(.code, .code),
            outcome(.code, nil),
        ])
        XCTAssertEqual(report.misplaced, 1)
        XCTAssertEqual(report.misplacementRate, 0.25)
        XCTAssertEqual(report.unsorted, 2)
        XCTAssertEqual(report.unsortedRate, 0.5)
        XCTAssertEqual(report.placedPrecision, 0.5)
        XCTAssertEqual(report.noneAccuracy, 0.5)
    }

    func testConfusionCountsEachPair() {
        let report = EvaluationReport([outcome(.recipe, .article), outcome(.recipe, .article), outcome(.recipe, .recipe)])
        XCTAssertEqual(report.count(expected: .recipe, predicted: .article), 2)
        XCTAssertEqual(report.count(expected: .recipe, predicted: .recipe), 1)
        XCTAssertEqual(report.count(expected: .article, predicted: .recipe), 0)
    }

    // MARK: Cascade

    func testCascadeOnlyFillsWhatTheFirstPassLeftUnsorted() {
        let first = [outcome(.recipe, .recipe), outcome(.note, nil), outcome(nil, nil)]
        XCTAssertEqual(ClassificationEvaluation.unsortedIndices(first), [1, 2])
        let second = [outcome(.note, .note), outcome(nil, nil)]
        XCTAssertEqual(ClassificationEvaluation.cascade(first, then: second), [outcome(.recipe, .recipe), outcome(.note, .note), outcome(nil, nil)])
    }

    // MARK: Running a pipeline

    private struct Fixed: ScreenshotClassifier {
        var verdict: ClassifierVerdict?
        func classify(_: ClassifierInput) async throws -> ClassifierVerdict? { verdict }
    }

    private struct Unavailable: ScreenshotClassifier {
        struct Failure: Error {}
        func classify(_: ClassifierInput) async throws -> ClassifierVerdict? { throw Failure() }
    }

    func testOutcomesApplyTheLayerThreshold() async throws {
        let sample = LabeledSample(expected: .shopping, text: "x")
        let weak = ClassificationPipeline(layers: [.init(Fixed(verdict: .init(target: .builtIn(.shopping), confidence: 0.3, source: .llm)), threshold: 0.6)])
        let strong = ClassificationPipeline(layers: [.init(Fixed(verdict: .init(target: .builtIn(.shopping), confidence: 0.9, source: .llm)), threshold: 0.6)])
        let weakOutcomes = try await ClassificationEvaluation.outcomes(of: [sample], using: weak)
        let strongOutcomes = try await ClassificationEvaluation.outcomes(of: [sample], using: strong)
        XCTAssertEqual(weakOutcomes, [outcome(.shopping, nil)])
        XCTAssertEqual(strongOutcomes, [outcome(.shopping, .shopping)])
    }

    func testALayerThatCannotAnswerStopsTheRun() async {
        let pipeline = ClassificationPipeline(layers: [.init(Unavailable(), threshold: 0.6)])
        do {
            _ = try await ClassificationEvaluation.outcomes(of: [LabeledSample(expected: nil, text: "x")], using: pipeline)
            XCTFail("expected the layer's error")
        } catch {
            XCTAssertTrue(error is Unavailable.Failure)
        }
    }

    func testRulesOnTheSyntheticSetPlaceNothingWrongly() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "labeled-ocr", withExtension: "json"))
        let samples = try JSONDecoder().decode([LabeledSample].self, from: Data(contentsOf: url))
        let report = try await EvaluationReport(ClassificationEvaluation.outcomes(of: samples, using: .standard))
        XCTAssertEqual(report.total, samples.count)
        XCTAssertEqual(report.misplaced, 0)
    }

    // MARK: LabeledSample

    func testRealBlocksDriveTheLayoutSignals() throws {
        let json = """
        { "expected": "social", "text": "a\\nb\\nc\\nd",
          "blocks": [
            { "id": 0, "text": "a", "box": { "x": 0.05, "y": 0.1, "width": 0.3, "height": 0.02 } },
            { "id": 1, "text": "b", "box": { "x": 0.6, "y": 0.2, "width": 0.3, "height": 0.02 } },
            { "id": 2, "text": "c", "box": { "x": 0.05, "y": 0.3, "width": 0.3, "height": 0.02 } },
            { "id": 3, "text": "d", "box": { "x": 0.6, "y": 0.4, "width": 0.3, "height": 0.02 } }
          ] }
        """
        let sample = try JSONDecoder().decode(LabeledSample.self, from: Data(json.utf8))
        XCTAssertTrue(sample.classifierInput.signals.hasAlternatingBubbles)
        XCTAssertFalse(LabeledSample(expected: .social, text: "a\nb\nc\nd").classifierInput.signals.hasAlternatingBubbles)
    }

    func testSyntheticChatLayoutAlternates() {
        let sample = LabeledSample(expected: .social, text: "a\nb\nc\nd", layout: "chat", barcodes: 2)
        XCTAssertTrue(sample.classifierInput.signals.hasAlternatingBubbles)
        XCTAssertEqual(sample.classifierInput.signals.barcodes, 2)
    }
}
