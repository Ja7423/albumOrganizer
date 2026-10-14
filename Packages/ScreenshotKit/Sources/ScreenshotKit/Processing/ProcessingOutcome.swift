import Foundation

/// What processing found for one screenshot: its recognition result and, when it can be placed now, its classification.
public struct ProcessingOutcome: Equatable, Sendable {
    public enum Recognition: Equatable, Sendable {
        case recognized(blocks: [TextBlock], barcodes: [String])
        case failed
        /// Classification-only work: recognition was already settled.
        case unchanged
    }

    public struct Classification: Equatable, Sendable {
        public var verdict: ClassifierVerdict?
        public var features: Set<FeatureTag>

        public init(verdict: ClassifierVerdict?, features: Set<FeatureTag>) {
            self.verdict = verdict
            self.features = features
        }
    }

    public var id: String
    public var recognition: Recognition
    /// `nil` when recognition failed and will be retried, so the screenshot stays in 處理中.
    public var classification: Classification?

    public init(id: String, recognition: Recognition, classification: Classification?) {
        self.id = id
        self.recognition = recognition
        self.classification = classification
    }
}

/// Counts from applying outcomes; added up over a run for the progress bar and its summary.
public struct ProcessingTally: Equatable, Sendable {
    /// Every outcome that landed on a screenshot still in the library.
    public var processed = 0
    /// Failed recognitions left in 處理中 for the next run.
    public var failed = 0
    /// Placed in a folder.
    public var classified = 0
    /// Placed in 未分類.
    public var unsorted = 0

    public init(processed: Int = 0, failed: Int = 0, classified: Int = 0, unsorted: Int = 0) {
        self.processed = processed
        self.failed = failed
        self.classified = classified
        self.unsorted = unsorted
    }

    public static func + (lhs: ProcessingTally, rhs: ProcessingTally) -> ProcessingTally {
        ProcessingTally(
            processed: lhs.processed + rhs.processed,
            failed: lhs.failed + rhs.failed,
            classified: lhs.classified + rhs.classified,
            unsorted: lhs.unsorted + rhs.unsorted
        )
    }
}

public extension Library {
    /// Applies a batch in one pass over the screenshots. Ids no longer in the library are skipped, and a
    /// classification is ignored for screenshots the user placed meanwhile, as in `applyClassification`.
    @discardableResult
    mutating func applyProcessingOutcomes(_ outcomes: [ProcessingOutcome], version: Int) -> ProcessingTally {
        let byID = Dictionary(outcomes.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        // Resolved up front: the update below holds `shots` exclusively and can't read `folders`.
        let destinations = byID.compactMapValues { $0.classification.map { autoDestination(for: $0.verdict) } }
        var tally = ProcessingTally()
        update(Array(byID.keys)) { shot in
            guard let outcome = byID[shot.id] else { return }
            shot.recordRecognition(outcome.recognition)
            if let classification = outcome.classification, let destination = destinations[shot.id] {
                shot.applyAutoPlacement(folderID: destination.folderID, source: destination.source, features: classification.features, version: version)
            }
            tally = tally + ProcessingTally(shot: shot, outcome: outcome)
        }
        return tally
    }
}

extension Shot {
    mutating func recordRecognition(_ recognition: ProcessingOutcome.Recognition) {
        switch recognition {
        case let .recognized(blocks, barcodes): recordRecognition(blocks: blocks, barcodes: barcodes)
        case .failed: recordRecognition(blocks: nil, barcodes: [])
        case .unchanged: break
        }
    }
}

private extension ProcessingTally {
    /// One screenshot's contribution, read after its outcome was applied.
    init(shot: Shot, outcome: ProcessingOutcome) {
        let isAutoPlaced = shot.autoPlacement != nil && outcome.classification != nil
        self.init(
            processed: 1,
            failed: outcome.recognition == .failed && shot.isProcessing ? 1 : 0,
            classified: isAutoPlaced && shot.folderID != nil ? 1 : 0,
            unsorted: isAutoPlaced && shot.folderID == nil ? 1 : 0
        )
    }
}

public extension ProcessingTally {
    /// A finished run's counts, as the progress bar and the system's progress UI show them.
    var summary: String {
        let placed = "已分類 \(classified.formatted()) 張，未分類 \(unsorted.formatted()) 張"
        return failed > 0 ? "\(placed)（\(failed.formatted()) 張稍後重試）" : placed
    }
}
