#if canImport(CreateML)
import CreateML
#endif
import Foundation
import NaturalLanguage
import ScreenshotKit

/// Trains the learned layer's model with Create ML, on the device, and saves it. Takes well under a second
/// for a few hundred samples. Create ML is missing from the iOS Simulator, where the layer stays off.
public enum LearnedModelTrainer {
    /// Fewer of the user's own samples than this and the model would mostly echo the seed samples.
    public static let minimumSamples = 20

    #if canImport(CreateML)
    public static let isSupported = true
    #else
    public static let isSupported = false
    #endif

    /// Trains on `set`, saves the model in `store` and returns it ready to use. `nil` when the user has not
    /// placed enough screenshots yet, or Create ML is unavailable; the store is left alone then.
    public static func train(_ set: TrainingSet, into store: LearnedModelStore) async throws -> NLModel? {
        guard set.samples.count >= minimumSamples else { return nil }
        #if canImport(CreateML)
        // Maximum entropy over words: on a real library it beat the BERT embedding (doc/classification.md §4).
        let parameters = MLTextClassifier.ModelParameters(validation: .none, algorithm: .maxEnt(revision: 1), language: .traditionalChinese)
        let classifier = try MLTextClassifier(trainingData: set.labeledTexts(), parameters: parameters)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let source = scratch.appendingPathComponent("learned-classifier.mlmodel")
        try classifier.write(to: source)
        return try await store.save(modelAt: source, fingerprint: set.fingerprint)
        #else
        return nil
        #endif
    }
}
