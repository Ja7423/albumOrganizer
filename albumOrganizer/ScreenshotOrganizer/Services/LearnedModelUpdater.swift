import Foundation
import os
import ScreenshotKit
import ScreenshotKitML

/// Keeps the learned layer trained on the user's own placements. Training runs off the main thread a few
/// seconds after the placements stop changing, and only when they changed since the saved model.
@MainActor
final class LearnedModelUpdater {
    let classifier = LearnedTextClassifier()
    /// Called after a new model is in use, so screenshots it might now place can be classified again.
    var onModelChanged: () -> Void = {}

    private let store: LearnedModelStore
    private var trainedFingerprint: String?
    private var task: Task<Void, Never>?

    private static let debounce = Duration.seconds(5)
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "albumOrganizer", category: "classification")

    init(store: LearnedModelStore) {
        self.store = store
        if let saved = store.load() {
            classifier.use(saved.model)
            trainedFingerprint = saved.fingerprint
        }
    }

    /// `learned/` in Application Support, next to the library. Never backed up to a shared place or bundled.
    nonisolated static var defaultStore: LearnedModelStore {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LearnedModelStore(directory: dir.appendingPathComponent("learned", isDirectory: true))
    }

    /// Trains again if `set` differs from what the current model learned. A newer call replaces a pending one.
    func update(for set: TrainingSet) {
        guard LearnedModelTrainer.isSupported, set.fingerprint != trainedFingerprint else { return }
        let previous = task
        previous?.cancel()
        let store = store
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            // A run already training finishes first, so an older model never replaces a newer one.
            await previous?.value
            guard !Task.isCancelled else { return }
            guard let classifier = self?.classifier else { return }
            do {
                // The model is handed to the classifier off the main actor: `NLModel` is not Sendable.
                let isTrained = try await Task.detached(priority: .utility) {
                    let model = try await LearnedModelTrainer.train(set, into: store)
                    if model == nil { store.remove() }
                    classifier.use(model)
                    return model != nil
                }.value
                guard let self else { return }
                trainedFingerprint = set.fingerprint
                Self.log.info("Learned layer: \(set.samples.count) samples, \(isTrained ? "trained" : "too few, off", privacy: .public)")
                if isTrained { onModelChanged() }
            } catch {
                Self.log.error("Training the learned layer failed: \(error, privacy: .public)")
            }
        }
    }
}
