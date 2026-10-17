import ScreenshotKit
import XCTest

final class ProcessingQueueTests: XCTestCase {
    private func asset(_ id: String, _ minutesAgo: Double) -> AssetInfo {
        AssetInfo(id: id, createdAt: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60), pixelWidth: 1179, pixelHeight: 2556)
    }

    private func block(_ text: String) -> TextBlock {
        TextBlock(id: 0, text: text, box: NormalizedRect(x: 0.1, y: 0.3, width: 0.5, height: 0.02))
    }

    /// Newest first: the first id is the newest screenshot.
    private func library(_ ids: [String]) -> Library {
        var lib = Library()
        lib.sync(with: ids.enumerated().map { asset($1, Double($0)) })
        return lib
    }

    private func drainIDs(_ queue: inout ProcessingQueue) -> [String] {
        var ids: [String] = []
        while let work = queue.next() {
            ids.append(work.id)
        }
        return ids
    }

    func testRecognitionComesBeforeClassificationOnly() {
        var lib = library(["a", "b", "c"])
        lib.setRecognition("b", blocks: [block("已辨識")], barcodes: ["qr"])
        var queue = ProcessingQueue(library: lib)
        XCTAssertEqual(queue.next(), .recognizeAndClassify("a", isLastAttempt: false))
        XCTAssertEqual(queue.next(), .recognizeAndClassify("c", isLastAttempt: false))
        XCTAssertEqual(queue.next(), .classify("b", blocks: [block("已辨識")], barcodes: ["qr"]))
        XCTAssertNil(queue.next())
        XCTAssertTrue(queue.isEmpty)
    }

    func testFinalRetryIsMarkedLastAttempt() {
        var lib = library(["a"])
        lib.setRecognition("a", blocks: nil)
        lib.setRecognition("a", blocks: nil)
        var queue = ProcessingQueue(library: lib)
        XCTAssertEqual(queue.next(), .recognizeAndClassify("a", isLastAttempt: true))
    }

    func testPlacedScreenshotsAreNotQueued() {
        var lib = library(["a", "b"])
        lib.setRecognition("a", blocks: [])
        lib.applyClassification("a", verdict: nil, features: [], version: 1)
        var queue = ProcessingQueue(library: lib)
        XCTAssertEqual(drainIDs(&queue), ["b"])
    }

    func testPrioritizedWorkJumpsTheLine() {
        var queue = ProcessingQueue(library: library(["a", "b", "c"]))
        queue.prioritize("c")
        XCTAssertEqual(drainIDs(&queue), ["c", "a", "b"])
    }

    func testPrioritizingUnknownOrHandedOutWorkIsIgnored() {
        var queue = ProcessingQueue(library: library(["a", "b"]))
        _ = queue.next()
        queue.prioritize("a")
        queue.prioritize("missing")
        XCTAssertEqual(drainIDs(&queue), ["b"])
    }

    func testRefillAddsOnlyNewScreenshots() {
        var lib = library(["a", "b"])
        var queue = ProcessingQueue(library: lib)
        XCTAssertEqual(queue.next()?.id, "a")
        // "a" failed and is still pending; it must not come back this run.
        lib.setRecognition("a", blocks: nil)
        lib.sync(with: [asset("new", -1), asset("a", 0), asset("b", 1)])
        queue.refill(from: lib)
        XCTAssertFalse(queue.isEmpty)
        XCTAssertEqual(drainIDs(&queue), ["b", "new"])
    }

    func testEmptyLibraryHasNoWork() {
        var queue = ProcessingQueue(library: Library())
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.next())
    }
}
