import Foundation

/// One run's work list, built from the library once instead of scanning it for every screenshot.
/// Each screenshot is handed out at most once per run, so a failed recognition waits for the next run.
public struct ProcessingQueue: Sendable {
    /// Carries what a worker needs, so it never has to look the screenshot up in the library.
    public enum Work: Hashable, Sendable {
        /// Needs recognition, then classification. On the last allowed attempt a failure is classified as textless.
        case recognizeAndClassify(String, isLastAttempt: Bool)
        /// Recognition is done or out of retries; only classification is left.
        case classify(String, blocks: [TextBlock], barcodes: [String])

        public var id: String {
            switch self {
            case let .recognizeAndClassify(id, _), let .classify(id, _, _): return id
            }
        }
    }

    private var recognitions: [Work] = []
    private var classifications: [Work] = []
    private var recognitionCursor = 0
    private var classificationCursor = 0
    private var priority: [Work] = []
    /// Queued this run, handed out or not.
    private var known: [String: Work] = [:]
    private var handedOut: Set<String> = []

    public init(library: Library) {
        refill(from: library)
    }

    /// Adds screenshots that became pending since the queue was built. Recognition work still comes first.
    public mutating func refill(from library: Library) {
        var freshRecognitions: [Work] = []
        var freshClassifications: [Work] = []
        for shot in library.shots where known[shot.id] == nil {
            if shot.needsRecognition {
                let isLastAttempt = shot.recognitionAttempts + 1 >= Shot.maxRecognitionAttempts
                freshRecognitions.append(.recognizeAndClassify(shot.id, isLastAttempt: isLastAttempt))
            } else if shot.isProcessing {
                freshClassifications.append(.classify(shot.id, blocks: shot.blocks, barcodes: shot.barcodes))
            }
        }
        recognitions += freshRecognitions
        classifications += freshClassifications
        for work in freshRecognitions + freshClassifications {
            known[work.id] = work
        }
    }

    /// Moves a queued screenshot to the front. Ones not queued or already handed out are ignored.
    public mutating func prioritize(_ id: String) {
        guard let work = known[id], !handedOut.contains(id) else { return }
        priority.removeAll { $0.id == id }
        priority.insert(work, at: 0)
    }

    /// The next work item; it is not handed out again this run.
    public mutating func next() -> Work? {
        let work = nextPriority() ?? next(in: recognitions, cursor: &recognitionCursor) ?? next(in: classifications, cursor: &classificationCursor)
        if let work { handedOut.insert(work.id) }
        return work
    }

    public var isEmpty: Bool {
        known.count == handedOut.count
    }

    private mutating func nextPriority() -> Work? {
        while !priority.isEmpty {
            let work = priority.removeFirst()
            if !handedOut.contains(work.id) { return work }
        }
        return nil
    }

    private func next(in list: [Work], cursor: inout Int) -> Work? {
        while cursor < list.count {
            let work = list[cursor]
            cursor += 1
            if !handedOut.contains(work.id) { return work }
        }
        return nil
    }
}
