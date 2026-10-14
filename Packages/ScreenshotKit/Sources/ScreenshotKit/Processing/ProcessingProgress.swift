import Foundation

/// What the progress bar and the import screen show for one processing run. The store feeds it events;
/// counts cover recognition and classification only, not the refinement pass that runs afterwards.
public struct ProcessingProgress: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case running
        /// Shown briefly with the run's counts, then cleared.
        case finished(ProcessingTally)
    }

    /// Smaller runs (a few new screenshots) finish without a progress bar.
    public static let visibilityThreshold = 20

    public private(set) var phase: Phase = .idle
    public private(set) var tally = ProcessingTally()
    /// In 處理中 and not yet looked at this run.
    public private(set) var remaining = 0
    /// Set once the run reaches the threshold; kept until the run ends so the bar never flickers away.
    public private(set) var isVisible = false

    public init() {}

    public var processed: Int {
        tally.processed
    }

    public var total: Int {
        processed + remaining
    }

    public var fraction: Double {
        total == 0 ? 0 : Double(processed) / Double(total)
    }

    public var isRunning: Bool {
        phase == .running
    }

    /// A run big enough to show the bar is worth keeping alive once the app leaves the screen.
    /// Before the run begins, `processingCount` (the library's 處理中 count) stands in for its size.
    public func isWorthContinuing(processingCount: Int) -> Bool {
        switch phase {
        case .running: isVisible
        case .idle: processingCount >= Self.visibilityThreshold
        case .finished: false
        }
    }

    /// `processingCount` is the library's 處理中 count.
    public mutating func begin(processingCount: Int) {
        self = ProcessingProgress()
        phase = .running
        updateRemaining(processingCount: processingCount)
    }

    public mutating func record(_ batch: ProcessingTally, processingCount: Int) {
        tally = tally + batch
        updateRemaining(processingCount: processingCount)
    }

    /// Screenshots were added or hidden mid-run. Failed ones stay in 處理中 but are already counted as processed.
    public mutating func updateRemaining(processingCount: Int) {
        guard isRunning else { return }
        remaining = max(0, processingCount - tally.failed)
        if total >= Self.visibilityThreshold { isVisible = true }
    }

    /// A run too small to show a bar ends without a summary.
    public mutating func finish() {
        guard isRunning else { return }
        if isVisible {
            phase = .finished(tally)
            remaining = 0
        } else {
            self = ProcessingProgress()
        }
    }

    public mutating func clear() {
        self = ProcessingProgress()
    }
}
