import ScreenshotKit
import XCTest

final class ProcessingProgressTests: XCTestCase {
    func testSmallRunStaysHiddenAndEndsWithoutSummary() {
        var progress = ProcessingProgress()
        progress.begin(processingCount: 5)
        XCTAssertFalse(progress.isVisible)
        progress.record(ProcessingTally(processed: 5, unsorted: 5), processingCount: 0)
        progress.finish()
        XCTAssertEqual(progress, ProcessingProgress())
    }

    func testLargeRunStaysVisibleUntilItEnds() {
        var progress = ProcessingProgress()
        progress.begin(processingCount: 30)
        XCTAssertTrue(progress.isVisible)
        progress.record(ProcessingTally(processed: 25, classified: 25), processingCount: 5)
        XCTAssertTrue(progress.isVisible, "the bar does not vanish once fewer than the threshold remain")
        XCTAssertEqual(progress.total, 30)
        XCTAssertEqual(progress.fraction, 25.0 / 30.0, accuracy: 0.0001)
    }

    func testFailedOnesCountAsProcessedNotRemaining() {
        var progress = ProcessingProgress()
        progress.begin(processingCount: 30)
        progress.record(ProcessingTally(processed: 10, failed: 2, classified: 8), processingCount: 22)
        XCTAssertEqual(progress.remaining, 20, "the 2 failed ones are still in 處理中 but already processed")
        XCTAssertEqual(progress.total, 30)
    }

    func testTotalFollowsScreenshotsAddedOrHiddenMidRun() {
        var progress = ProcessingProgress()
        progress.begin(processingCount: 30)
        progress.record(ProcessingTally(processed: 10), processingCount: 20)
        progress.updateRemaining(processingCount: 25)
        XCTAssertEqual(progress.total, 35)
        progress.updateRemaining(processingCount: 15)
        XCTAssertEqual(progress.total, 25)
    }

    func testRunReachingThresholdLaterBecomesVisible() {
        var progress = ProcessingProgress()
        progress.begin(processingCount: 3)
        progress.updateRemaining(processingCount: 40)
        XCTAssertTrue(progress.isVisible)
    }

    func testFinishShowsTheRunTallyThenClears() {
        var progress = ProcessingProgress()
        progress.begin(processingCount: 30)
        let tally = ProcessingTally(processed: 30, failed: 1, classified: 20, unsorted: 9)
        progress.record(tally, processingCount: 1)
        progress.finish()
        XCTAssertEqual(progress.phase, .finished(tally))
        XCTAssertEqual(progress.fraction, 1)

        progress.updateRemaining(processingCount: 50)
        XCTAssertEqual(progress.phase, .finished(tally), "a finished run ignores later counts")

        progress.clear()
        XCTAssertEqual(progress, ProcessingProgress())
    }

    func testBeginResetsAPreviousRun() {
        var progress = ProcessingProgress()
        progress.begin(processingCount: 30)
        progress.record(ProcessingTally(processed: 30), processingCount: 0)
        progress.finish()
        progress.begin(processingCount: 4)
        XCTAssertEqual(progress.phase, .running)
        XCTAssertEqual(progress.processed, 0)
        XCTAssertFalse(progress.isVisible)
    }
}
