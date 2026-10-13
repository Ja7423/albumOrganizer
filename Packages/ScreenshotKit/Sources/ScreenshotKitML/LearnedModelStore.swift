import CoreML
import Foundation
import NaturalLanguage

/// Keeps the learned model on disk next to the library, with the training set fingerprint it was trained on.
/// The model holds words from the user's screenshots: it stays on the device and is never bundled or synced.
public struct LearnedModelStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var modelURL: URL { directory.appendingPathComponent("learned-classifier.mlmodelc") }
    private var fingerprintURL: URL { directory.appendingPathComponent("learned-classifier.fingerprint") }

    /// `nil` when nothing was saved or the saved model can't be read.
    public func load() -> (model: NLModel, fingerprint: String)? {
        guard let fingerprint = try? String(contentsOf: fingerprintURL, encoding: .utf8),
              let mlModel = try? MLModel(contentsOf: modelURL),
              let model = try? NLModel(mlModel: mlModel)
        else { return nil }
        return (model, fingerprint)
    }

    /// Compiles the `.mlmodel` at `source`, saves it in place of the previous one and returns it ready to use.
    public func save(modelAt source: URL, fingerprint: String) async throws -> NLModel {
        let fileManager = FileManager.default
        let compiled = try await MLModel.compileModel(at: source)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // The fingerprint goes first: if the app dies in between, the next launch sees a stale fingerprint
        // and trains again instead of trusting an old model.
        try? fileManager.removeItem(at: fingerprintURL)
        if fileManager.fileExists(atPath: modelURL.path) {
            _ = try fileManager.replaceItemAt(modelURL, withItemAt: compiled)
        } else {
            try fileManager.moveItem(at: compiled, to: modelURL)
        }
        try fingerprint.write(to: fingerprintURL, atomically: true, encoding: .utf8)
        return try NLModel(mlModel: MLModel(contentsOf: modelURL))
    }

    /// Forgets the model, e.g. when the user no longer has enough samples.
    public func remove() {
        try? FileManager.default.removeItem(at: modelURL)
        try? FileManager.default.removeItem(at: fingerprintURL)
    }
}
