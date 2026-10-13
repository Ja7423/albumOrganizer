import ScreenshotKit
import ScreenshotKitML
import XCTest

final class LearnedLayerTests: XCTestCase {
    /// The seed samples standing in for a user's own placements.
    private var userSet: TrainingSet {
        TrainingSet(samples: LabeledSample.seedSamples.enumerated().map { index, sample in
            LabeledSample(id: "\(index)", expected: sample.expected, text: sample.text)
        })
    }

    private func input(_ text: String) -> ClassifierInput {
        ClassifierInput(text: text, signals: SignalExtractor.extract(blocks: [], barcodes: []))
    }

    func testAnswersNothingUntilTrained() async throws {
        let verdict = try await LearnedTextClassifier().classify(input("電子發票證明聯\n總計 $185"))
        XCTAssertNil(verdict)
    }

    private func temporaryStore() -> LearnedModelStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return LearnedModelStore(directory: directory)
    }

    func testTooFewSamplesTrainNothing() async throws {
        let few = TrainingSet(samples: Array(userSet.samples.prefix(LearnedModelTrainer.minimumSamples - 1)))
        let store = temporaryStore()
        let model = try await LearnedModelTrainer.train(few, into: store)
        XCTAssertNil(model)
        XCTAssertNil(store.load())
    }

    func testTrainedModelAnswersWithLearnedSource() async throws {
        let store = temporaryStore()
        let model = try await LearnedModelTrainer.train(userSet, into: store)
        let classifier = try LearnedTextClassifier(model: XCTUnwrap(model))

        let verdict = try await classifier.classify(input("電子發票證明聯\n2026-10\n總計 $185"))
        XCTAssertEqual(verdict?.target, .builtIn(.receipt))
        XCTAssertEqual(verdict?.source, .learned)
        XCTAssertEqual(store.load()?.fingerprint, userSet.fingerprint)
    }

    func testStoreLoadsNothingAfterRemove() async throws {
        let store = temporaryStore()
        XCTAssertNil(store.load())

        _ = try await LearnedModelTrainer.train(userSet, into: store)
        XCTAssertNotNil(store.load())
        store.remove()
        XCTAssertNil(store.load())
    }

    func testStandardPipelineRunsRulesThenTheLearnedLayer() {
        let pipeline = ClassificationPipeline.standard(learned: LearnedTextClassifier())
        XCTAssertEqual(pipeline.layers.map(\.threshold), [0.7, LearnedTextClassifier.threshold])
        XCTAssertTrue(pipeline.layers.last?.classifier is LearnedTextClassifier)
    }
}
