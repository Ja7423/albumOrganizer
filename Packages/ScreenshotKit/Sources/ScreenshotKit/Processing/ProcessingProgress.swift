import Foundation

/// What the progress bar and the import screen show for one processing run. The store feeds it events.
/// A run has two stages: recognizing and classifying 處理中 screenshots, then refining the ones the rules
/// left in 未分類. The counts and the bar cover the current stage; the tally covers the whole run.
public struct ProcessingProgress: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Recognizing and classifying 處理中 screenshots.
        case recognizing
        /// Apple Intelligence looks again at screenshots left in 未分類.
        case refining
        /// Shown briefly with the run's counts, then cleared.
        case finished(ProcessingTally)
    }

    /// Smaller runs (a few new screenshots) finish without a progress bar.
    public static let visibilityThreshold = 20

    public private(set) var phase: Phase = .idle
    /// Where this run's screenshots ended up, refinement moves included.
    public private(set) var tally = ProcessingTally()
    /// Done in the current stage.
    public private(set) var completed = 0
    /// Still to do in the current stage.
    public private(set) var remaining = 0
    /// Set once a stage reaches the threshold; kept until the run ends so the bar never flickers away.
    public private(set) var isVisible = false
    /// This run's 未分類 placements that refinement may still move into a folder.
    private var unsortedIDs: Set<String> = []

    public init() {}

    public var total: Int {
        completed + remaining
    }

    public var fraction: Double {
        total == 0 ? 0 : Double(completed) / Double(total)
    }

    public var isRecognizing: Bool {
        phase == .recognizing
    }

    /// A run big enough to show the bar is worth keeping alive once the app leaves the screen. Only
    /// recognition continues there: refinement uses Apple Intelligence, which the system limits in the background.
    /// Before the run begins, `workCount` (`Library.processingWorkCount`) stands in for its size.
    public func isWorthContinuing(workCount: Int) -> Bool {
        switch phase {
        case .recognizing: isVisible
        case .idle: workCount >= Self.visibilityThreshold
        case .refining, .finished: false
        }
    }

    /// `workCount` is `Library.processingWorkCount`: everything the processor still has to do. New work that
    /// arrives during refinement continues the same run, so its counts carry on.
    public mutating func begin(workCount: Int) {
        if phase != .refining { self = ProcessingProgress() }
        phase = .recognizing
        completed = 0
        updateRemaining(workCount: workCount)
    }

    /// `unsortedIDs` are the batch's screenshots now in 未分類 and awaiting refinement.
    public mutating func record(_ batch: ProcessingTally, unsortedIDs: Set<String> = [], workCount: Int) {
        guard isRecognizing else { return }
        tally = tally + batch
        self.unsortedIDs.formUnion(unsortedIDs)
        completed += batch.processed
        updateRemaining(workCount: workCount)
    }

    /// Screenshots were added or hidden mid-run. Failed ones still need recognition but are already counted as done.
    public mutating func updateRemaining(workCount: Int) {
        guard isRecognizing else { return }
        remaining = max(0, workCount - tally.failed)
        revealIfLarge()
    }

    /// `refinementCount` is `Library.pendingRefinementCount`, or 0 when refinement is off or unavailable.
    public mutating func finishRecognition(refinementCount: Int) {
        guard isRecognizing else { return }
        guard refinementCount > 0 else { return finish() }
        phase = .refining
        completed = 0
        updateRemaining(refinementCount: refinementCount)
    }

    /// A screenshot refinement moved into a folder counts as classified instead of unsorted. One left over
    /// from an earlier run was never counted as unsorted here, so it only adds to classified.
    public mutating func recordRefinement(_ id: String, movedToFolder: Bool, refinementCount: Int) {
        guard phase == .refining else { return }
        completed += 1
        if movedToFolder {
            tally.classified += 1
            if unsortedIDs.remove(id) != nil { tally.unsorted -= 1 }
        }
        updateRemaining(refinementCount: refinementCount)
    }

    /// Screenshots were moved or hidden during refinement.
    public mutating func updateRemaining(refinementCount: Int) {
        guard phase == .refining else { return }
        remaining = refinementCount
        revealIfLarge()
    }

    /// A run too small to show a bar ends without a summary.
    public mutating func finish() {
        guard phase == .recognizing || phase == .refining else { return }
        if isVisible {
            phase = .finished(tally)
            completed = total
            remaining = 0
            unsortedIDs = []
        } else {
            self = ProcessingProgress()
        }
    }

    public mutating func clear() {
        self = ProcessingProgress()
    }

    private mutating func revealIfLarge() {
        if total >= Self.visibilityThreshold { isVisible = true }
    }
}
