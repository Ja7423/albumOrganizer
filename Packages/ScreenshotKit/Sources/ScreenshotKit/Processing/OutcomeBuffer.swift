import Foundation

/// Collects outcomes and says when to write them: every `maxCount` outcomes, or `maxDelay` after the first one.
/// Writing in batches keeps redraws and save diffs rare while the grid still looks live.
public struct OutcomeBuffer: Sendable {
    public let maxCount: Int
    public let maxDelay: Duration

    private var outcomes: [ProcessingOutcome] = []
    private var firstAppendedAt: ContinuousClock.Instant?

    public init(maxCount: Int = 20, maxDelay: Duration = .milliseconds(500)) {
        self.maxCount = maxCount
        self.maxDelay = maxDelay
    }

    /// `now` is passed in so the rule needs no clock.
    public mutating func append(_ outcome: ProcessingOutcome, at now: ContinuousClock.Instant) {
        if outcomes.isEmpty { firstAppendedAt = now }
        outcomes.append(outcome)
    }

    public func shouldFlush(at now: ContinuousClock.Instant) -> Bool {
        guard let firstAppendedAt else { return false }
        return outcomes.count >= maxCount || now - firstAppendedAt >= maxDelay
    }

    public mutating func drain() -> [ProcessingOutcome] {
        defer {
            outcomes = []
            firstAppendedAt = nil
        }
        return outcomes
    }
}
