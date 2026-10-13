import Foundation

/// Everything a classifier layer may look at for one screenshot.
public struct ClassifierInput: Sendable {
    public var text: String
    public var signals: ScreenshotSignals
    /// Targets no layer may answer, e.g. built-in categories the user deleted.
    public var excluded: Set<ClassificationTarget>

    public init(text: String, signals: ScreenshotSignals, excluded: Set<ClassificationTarget> = []) {
        self.text = text
        self.signals = signals
        self.excluded = excluded
    }
}

public struct ClassifierVerdict: Hashable, Sendable {
    public var target: ClassificationTarget
    /// 0…1. Each layer has its own scale; the pipeline compares it with that layer's threshold only.
    public var confidence: Double
    public var source: ClassifierSource

    public init(target: ClassificationTarget, confidence: Double, source: ClassifierSource) {
        self.target = target
        self.confidence = confidence
        self.source = source
    }
}

/// One layer of the classification cascade (rules, kNN, on-device LLM).
public protocol ScreenshotClassifier: Sendable {
    /// `nil` when the layer has no opinion on this screenshot, including when it can never judge it.
    /// Throws only when it cannot answer right now (e.g. a model that is unavailable or busy), so the
    /// caller may try the same screenshot again later.
    func classify(_ input: ClassifierInput) async throws -> ClassifierVerdict?
}
