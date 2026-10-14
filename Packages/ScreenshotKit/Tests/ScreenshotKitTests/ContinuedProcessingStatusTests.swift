import ScreenshotKit
import XCTest

final class ContinuedProcessingStatusTests: XCTestCase {
    func testRunningShowsTheBarsCounts() {
        var progress = ProcessingProgress()
        progress.begin(processingCount: 50)
        progress.record(ProcessingTally(processed: 12, classified: 12), processingCount: 38)

        let status = ContinuedProcessingStatus(progress: progress)
        XCTAssertEqual(status.title, "正在整理截圖")
        XCTAssertEqual(status.subtitle, "已完成 12 / 50 張")
        XCTAssertEqual(status.completed, 12)
        XCTAssertEqual(status.total, 50)
    }

    func testFinishedShowsTheSummaryAtFullProgress() {
        var progress = ProcessingProgress()
        progress.begin(processingCount: 30)
        progress.record(ProcessingTally(processed: 30, classified: 20, unsorted: 10), processingCount: 0)
        progress.finish()

        let status = ContinuedProcessingStatus(progress: progress)
        XCTAssertEqual(status.title, "整理完成")
        XCTAssertEqual(status.subtitle, "已分類 20 張，未分類 10 張")
        XCTAssertEqual(status.completed, status.total)
    }

    func testPreparingHasNoCountsYet() {
        XCTAssertEqual(ContinuedProcessingStatus.preparing.title, "正在整理截圖")
        XCTAssertEqual(ContinuedProcessingStatus.preparing.total, 0)
    }

    func testSummaryMentionsFailedOnesOnlyWhenThereAreSome() {
        XCTAssertEqual(ProcessingTally(processed: 3, classified: 1, unsorted: 2).summary, "已分類 1 張，未分類 2 張")
        XCTAssertEqual(
            ProcessingTally(processed: 4, failed: 1, classified: 1, unsorted: 2).summary,
            "已分類 1 張，未分類 2 張（1 張稍後重試）"
        )
    }
}
