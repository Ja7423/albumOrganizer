import ScreenshotKit
import XCTest

private struct FixedClassifier: ScreenshotClassifier {
    var verdict: ClassifierVerdict?
    var fails = false

    func classify(_: ClassifierInput) async throws -> ClassifierVerdict? {
        if fails { throw CocoaError(.featureUnsupported) }
        return verdict
    }
}

final class ClassificationPipelineTests: XCTestCase {
    private let input = ClassifierInput(text: "x", signals: ScreenshotSignals())

    private func verdict(_ category: BuiltInCategory, _ confidence: Double, _ source: ClassifierSource) -> ClassifierVerdict {
        ClassifierVerdict(target: .builtIn(category), confidence: confidence, source: source)
    }

    func testFallsThroughUnconfidentLayers() async {
        let pipeline = ClassificationPipeline(layers: [
            .init(FixedClassifier(verdict: verdict(.note, 0.5, .rule)), threshold: 0.7),
            .init(FixedClassifier(verdict: nil), threshold: 0.7),
            .init(FixedClassifier(verdict: verdict(.article, 0.8, .llm)), threshold: 0.6),
        ])
        let result = await pipeline.classify(input)
        XCTAssertEqual(result, verdict(.article, 0.8, .llm))
    }

    func testStopsAtFirstConfidentLayer() async {
        let pipeline = ClassificationPipeline(layers: [
            .init(FixedClassifier(verdict: verdict(.code, 0.9, .rule)), threshold: 0.7),
            .init(FixedClassifier(verdict: verdict(.article, 1, .llm)), threshold: 0),
        ])
        let result = await pipeline.classify(input)
        XCTAssertEqual(result?.target, .builtIn(.code))
    }

    func testSkipsThrowingLayers() async {
        let pipeline = ClassificationPipeline(layers: [
            .init(FixedClassifier(fails: true), threshold: 0),
            .init(FixedClassifier(verdict: verdict(.note, 0.9, .knn)), threshold: 0.7),
        ])
        let result = await pipeline.classify(input)
        XCTAssertEqual(result?.source, .knn)
    }

    func testRejectsExcludedTargets() async {
        let pipeline = ClassificationPipeline(layers: [.init(FixedClassifier(verdict: verdict(.social, 1, .llm)), threshold: 0)])
        let excluded = ClassifierInput(text: "x", signals: ScreenshotSignals(), excluded: [.builtIn(.social)])
        let result = await pipeline.classify(excluded)
        XCTAssertNil(result)
    }

    func testNoLayersMeansUnsorted() async {
        let result = await ClassificationPipeline(layers: []).classify(input)
        XCTAssertNil(result)
    }

    func testClassifyOrThrowAppliesTheSameThresholdAndExclusions() async throws {
        let pipeline = ClassificationPipeline(layers: [
            .init(FixedClassifier(verdict: verdict(.note, 0.5, .llm)), threshold: 0.6),
            .init(FixedClassifier(verdict: verdict(.social, 0.9, .llm)), threshold: 0.6),
            .init(FixedClassifier(verdict: verdict(.note, 0.9, .llm)), threshold: 0.6),
        ])
        let excluded = ClassifierInput(text: "x", signals: ScreenshotSignals(), excluded: [.builtIn(.social)])
        let result = try await pipeline.classifyOrThrow(excluded)
        XCTAssertEqual(result?.target, .builtIn(.note))
    }

    func testClassifyOrThrowPropagatesLayerErrors() async {
        let pipeline = ClassificationPipeline(layers: [
            .init(FixedClassifier(fails: true), threshold: 0),
            .init(FixedClassifier(verdict: verdict(.note, 0.9, .llm)), threshold: 0),
        ])
        do {
            _ = try await pipeline.classifyOrThrow(input)
            XCTFail("expected the layer's error")
        } catch {}
    }
}
