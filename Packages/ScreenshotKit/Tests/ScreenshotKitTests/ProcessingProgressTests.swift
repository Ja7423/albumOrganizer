import ScreenshotKit
import XCTest

final class ProcessingProgressTests: XCTestCase {
    func testSmallRunStaysHiddenAndEndsWithoutSummary() {
        var progress = ProcessingProgress()
        progress.begin(workCount: 5)
        XCTAssertFalse(progress.isVisible)
        progress.record(ProcessingTally(processed: 5, unsorted: 5), workCount: 0)
        progress.finish()
        XCTAssertEqual(progress, ProcessingProgress())
    }

    func testLargeRunStaysVisibleUntilItEnds() {
        var progress = ProcessingProgress()
        progress.begin(workCount: 30)
        XCTAssertTrue(progress.isVisible)
        progress.record(ProcessingTally(processed: 25, classified: 25), workCount: 5)
        XCTAssertTrue(progress.isVisible, "the bar does not vanish once fewer than the threshold remain")
        XCTAssertEqual(progress.total, 30)
        XCTAssertEqual(progress.fraction, 25.0 / 30.0, accuracy: 0.0001)
    }

    func testFailedOnesCountAsProcessedNotRemaining() {
        var progress = ProcessingProgress()
        progress.begin(workCount: 30)
        progress.record(ProcessingTally(processed: 10, failed: 2, classified: 8), workCount: 22)
        XCTAssertEqual(progress.remaining, 20, "the 2 failed ones are still in 處理中 but already processed")
        XCTAssertEqual(progress.total, 30)
    }

    func testTotalFollowsScreenshotsAddedOrHiddenMidRun() {
        var progress = ProcessingProgress()
        progress.begin(workCount: 30)
        progress.record(ProcessingTally(processed: 10), workCount: 20)
        progress.updateRemaining(workCount: 25)
        XCTAssertEqual(progress.total, 35)
        progress.updateRemaining(workCount: 15)
        XCTAssertEqual(progress.total, 25)
    }

    func testRunReachingThresholdLaterBecomesVisible() {
        var progress = ProcessingProgress()
        progress.begin(workCount: 3)
        progress.updateRemaining(workCount: 40)
        XCTAssertTrue(progress.isVisible)
    }

    func testFinishShowsTheRunTallyThenClears() {
        var progress = ProcessingProgress()
        progress.begin(workCount: 30)
        let tally = ProcessingTally(processed: 30, failed: 1, classified: 20, unsorted: 9)
        progress.record(tally, workCount: 1)
        progress.finish()
        XCTAssertEqual(progress.phase, .finished(tally))
        XCTAssertEqual(progress.fraction, 1)

        progress.updateRemaining(workCount: 50)
        XCTAssertEqual(progress.phase, .finished(tally), "a finished run ignores later counts")

        progress.clear()
        XCTAssertEqual(progress, ProcessingProgress())
    }

    func testBeginResetsAPreviousRun() {
        var progress = ProcessingProgress()
        progress.begin(workCount: 30)
        progress.record(ProcessingTally(processed: 30), workCount: 0)
        progress.finish()
        progress.begin(workCount: 4)
        XCTAssertEqual(progress.phase, .running)
        XCTAssertEqual(progress.processed, 0)
        XCTAssertFalse(progress.isVisible)
    }

    func testOnlyLargeRunsAreWorthContinuing() {
        var progress = ProcessingProgress()
        XCTAssertFalse(progress.isWorthContinuing(workCount: 19), "before the run begins, the queue's size decides")
        XCTAssertTrue(progress.isWorthContinuing(workCount: 20))

        progress.begin(workCount: 5)
        XCTAssertFalse(progress.isWorthContinuing(workCount: 5))
        progress.updateRemaining(workCount: 30)
        XCTAssertTrue(progress.isWorthContinuing(workCount: 30))

        progress.record(ProcessingTally(processed: 30), workCount: 0)
        progress.finish()
        XCTAssertFalse(progress.isWorthContinuing(workCount: 0), "a finished run has nothing left to continue")
    }
}
