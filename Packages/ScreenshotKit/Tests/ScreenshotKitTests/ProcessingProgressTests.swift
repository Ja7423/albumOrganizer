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
        XCTAssertEqual(progress.phase, .recognizing)
        XCTAssertEqual(progress.completed, 0)
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

    // MARK: - Refinement stage

    /// A visible run of 30: 20 placed in folders, 10 in 未分類 awaiting refinement.
    private func recognizedRun() -> ProcessingProgress {
        var progress = ProcessingProgress()
        progress.begin(workCount: 30)
        let unsortedIDs = Set((0 ..< 10).map { "u\($0)" })
        progress.record(ProcessingTally(processed: 30, classified: 20, unsorted: 10), unsortedIDs: unsortedIDs, workCount: 0)
        return progress
    }

    func testRecognitionHandsOverToRefinementWithItsOwnCounts() {
        var progress = recognizedRun()
        progress.finishRecognition(refinementCount: 10)
        XCTAssertEqual(progress.phase, .refining)
        XCTAssertEqual(progress.completed, 0)
        XCTAssertEqual(progress.total, 10)
        XCTAssertTrue(progress.isVisible)
    }

    func testRefinementMovesCountAsClassified() {
        var progress = recognizedRun()
        progress.finishRecognition(refinementCount: 10)
        progress.recordRefinement("u0", movedToFolder: true, refinementCount: 9)
        progress.recordRefinement("u1", movedToFolder: false, refinementCount: 8)
        XCTAssertEqual(progress.completed, 2)
        XCTAssertEqual(progress.total, 10)
        progress.finish()
        XCTAssertEqual(progress.phase, .finished(ProcessingTally(processed: 30, classified: 21, unsorted: 9)))
        XCTAssertEqual(progress.fraction, 1)
    }

    func testLeftoverFromAnEarlierRunOnlyAddsToClassified() {
        var progress = ProcessingProgress()
        progress.begin(workCount: 0)
        progress.finishRecognition(refinementCount: 25)
        XCTAssertTrue(progress.isVisible, "a large refinement shows the bar on its own")
        progress.recordRefinement("old", movedToFolder: true, refinementCount: 24)
        progress.recordRefinement("old2", movedToFolder: false, refinementCount: 23)
        XCTAssertEqual(progress.tally, ProcessingTally(classified: 1), "never counted as this run's 未分類, so nothing to take off")
    }

    func testNothingToRefineFinishesRightAway() {
        var progress = recognizedRun()
        progress.finishRecognition(refinementCount: 0)
        XCTAssertEqual(progress.phase, .finished(ProcessingTally(processed: 30, classified: 20, unsorted: 10)))
    }

    func testSmallRunStaysHiddenThroughRefinement() {
        var progress = ProcessingProgress()
        progress.begin(workCount: 3)
        progress.record(ProcessingTally(processed: 3, unsorted: 3), unsortedIDs: ["a", "b", "c"], workCount: 0)
        progress.finishRecognition(refinementCount: 3)
        XCTAssertFalse(progress.isVisible)
        progress.finish()
        XCTAssertEqual(progress, ProcessingProgress())
    }

    func testRefinementTotalFollowsScreenshotsMovedMeanwhile() {
        var progress = recognizedRun()
        progress.finishRecognition(refinementCount: 10)
        progress.updateRemaining(refinementCount: 7)
        XCTAssertEqual(progress.total, 7)
        progress.updateRemaining(workCount: 50)
        XCTAssertEqual(progress.total, 7, "recognition counts don't apply while refining")
    }

    func testNewWorkDuringRefinementContinuesTheRun() {
        var progress = recognizedRun()
        progress.finishRecognition(refinementCount: 10)
        progress.recordRefinement("u0", movedToFolder: true, refinementCount: 9)
        progress.begin(workCount: 2)
        XCTAssertEqual(progress.phase, .recognizing)
        XCTAssertEqual(progress.completed, 0)
        XCTAssertEqual(progress.total, 2)
        XCTAssertTrue(progress.isVisible, "the bar stays up for the rest of the run")
        XCTAssertEqual(progress.tally, ProcessingTally(processed: 30, classified: 21, unsorted: 9))
    }

    func testRefinementIsNotContinuedInBackground() {
        var progress = recognizedRun()
        XCTAssertTrue(progress.isWorthContinuing(workCount: 0))
        progress.finishRecognition(refinementCount: 10)
        XCTAssertFalse(progress.isWorthContinuing(workCount: 0))
    }

    func testRefinementEventsAreIgnoredOutsideTheRefiningStage() {
        var progress = recognizedRun()
        progress.recordRefinement("u0", movedToFolder: true, refinementCount: 9)
        progress.updateRemaining(refinementCount: 9)
        XCTAssertEqual(progress, recognizedRun())
    }
}
