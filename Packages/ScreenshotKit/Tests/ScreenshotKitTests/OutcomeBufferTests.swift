import ScreenshotKit
import XCTest

final class OutcomeBufferTests: XCTestCase {
    private let start = ContinuousClock.now

    private func outcome(_ id: String) -> ProcessingOutcome {
        ProcessingOutcome(id: id, recognition: .failed, classification: nil)
    }

    func testEmptyBufferNeverFlushes() {
        let buffer = OutcomeBuffer()
        XCTAssertFalse(buffer.shouldFlush(at: start + .seconds(10)))
    }

    func testFlushesWhenFull() {
        var buffer = OutcomeBuffer(maxCount: 3, maxDelay: .seconds(60))
        buffer.append(outcome("a"), at: start)
        buffer.append(outcome("b"), at: start)
        XCTAssertFalse(buffer.shouldFlush(at: start))
        buffer.append(outcome("c"), at: start)
        XCTAssertTrue(buffer.shouldFlush(at: start))
    }

    func testFlushesAfterDelayFromFirstOutcome() {
        var buffer = OutcomeBuffer(maxCount: 20, maxDelay: .milliseconds(500))
        buffer.append(outcome("a"), at: start)
        buffer.append(outcome("b"), at: start + .milliseconds(400))
        XCTAssertFalse(buffer.shouldFlush(at: start + .milliseconds(499)))
        XCTAssertTrue(buffer.shouldFlush(at: start + .milliseconds(500)))
    }

    func testDrainEmptiesAndRestartsTheTimer() {
        var buffer = OutcomeBuffer(maxCount: 20, maxDelay: .milliseconds(500))
        buffer.append(outcome("a"), at: start)
        XCTAssertEqual(buffer.drain().map(\.id), ["a"])
        XCTAssertFalse(buffer.shouldFlush(at: start + .seconds(1)))
        buffer.append(outcome("b"), at: start + .seconds(1))
        XCTAssertFalse(buffer.shouldFlush(at: start + .milliseconds(1400)))
    }
}
