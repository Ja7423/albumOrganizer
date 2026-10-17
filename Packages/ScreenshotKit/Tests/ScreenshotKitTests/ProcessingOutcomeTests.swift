import ScreenshotKit
import XCTest

final class ProcessingOutcomeTests: XCTestCase {
    private func asset(_ id: String, _ minutesAgo: Double) -> AssetInfo {
        AssetInfo(id: id, createdAt: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60), pixelWidth: 1179, pixelHeight: 2556)
    }

    private func block(_ text: String) -> TextBlock {
        TextBlock(id: 0, text: text, box: NormalizedRect(x: 0.1, y: 0.3, width: 0.5, height: 0.02))
    }

    private func verdict(_ category: BuiltInCategory) -> ClassifierVerdict {
        ClassifierVerdict(target: .builtIn(category), confidence: 0.9, source: .rule)
    }

    private func library(_ ids: [String]) -> Library {
        var lib = Library()
        lib.sync(with: ids.enumerated().map { asset($1, Double($0)) })
        return lib
    }

    private func placed(_ id: String, blocks: [TextBlock], verdict: ClassifierVerdict?, features: Set<FeatureTag> = []) -> ProcessingOutcome {
        ProcessingOutcome(
            id: id,
            recognition: .recognized(blocks: blocks, barcodes: ["code-\(id)"]),
            classification: .init(verdict: verdict, features: features)
        )
    }

    func testBatchMatchesOneByOneCalls() {
        let outcomes = [
            placed("a", blocks: [block("電子發票")], verdict: verdict(.receipt), features: [.qrCode]),
            placed("b", blocks: [block("hello")], verdict: nil),
            ProcessingOutcome(id: "c", recognition: .failed, classification: nil),
        ]
        let base = library(["a", "b", "c"])
        var batched = base
        batched.applyProcessingOutcomes(outcomes, version: 7)

        var single = base
        single.setRecognition("a", blocks: [block("電子發票")], barcodes: ["code-a"])
        single.applyClassification("a", verdict: verdict(.receipt), features: [.qrCode], version: 7)
        single.setRecognition("b", blocks: [block("hello")], barcodes: ["code-b"])
        single.applyClassification("b", verdict: nil, features: [], version: 7)
        single.setRecognition("c", blocks: nil)

        XCTAssertEqual(batched, single)
    }

    func testTallyCountsPlacementsAndRetries() {
        var lib = library(["a", "b", "c"])
        let tally = lib.applyProcessingOutcomes([
            placed("a", blocks: [block("電子發票")], verdict: verdict(.receipt)),
            placed("b", blocks: [], verdict: nil),
            ProcessingOutcome(id: "c", recognition: .failed, classification: nil),
        ], version: 1)
        XCTAssertEqual(tally, ProcessingTally(processed: 3, failed: 1, classified: 1, unsorted: 1))
        XCTAssertEqual(lib.shot("c")?.isProcessing, true, "a failed recognition waits in 處理中 for the next run")
    }

    func testLastFailedAttemptIsClassifiedAsTextless() {
        var lib = library(["a"])
        lib.setRecognition("a", blocks: nil)
        lib.setRecognition("a", blocks: nil)
        let tally = lib.applyProcessingOutcomes([
            ProcessingOutcome(id: "a", recognition: .failed, classification: .init(verdict: nil, features: [])),
        ], version: 1)
        XCTAssertEqual(lib.shot("a")?.recognitionAttempts, Shot.maxRecognitionAttempts)
        XCTAssertEqual(lib.shot("a")?.isUnsorted, true)
        XCTAssertEqual(tally, ProcessingTally(processed: 1, failed: 0, classified: 0, unsorted: 1))
    }

    func testManualMoveDuringProcessingWins() throws {
        var lib = library(["a"])
        let folder = try XCTUnwrap(lib.createFolder(named: "旅行"))
        lib.move(["a"], to: folder.id)

        let tally = lib.applyProcessingOutcomes([placed("a", blocks: [block("發票")], verdict: verdict(.receipt))], version: 1)
        let shot = try XCTUnwrap(lib.shot("a"))
        XCTAssertEqual(shot.folderID, folder.id)
        XCTAssertEqual(shot.placement, .user)
        XCTAssertEqual(shot.recognition, .done, "the recognized text is still kept")
        XCTAssertEqual(tally, ProcessingTally(processed: 1))
    }

    func testOutcomeForHiddenShotIsSkipped() {
        var lib = library(["a", "b"])
        lib.hide(["a"])
        let tally = lib.applyProcessingOutcomes([placed("a", blocks: [], verdict: nil), placed("b", blocks: [], verdict: nil)], version: 1)
        XCTAssertNil(lib.shot("a"))
        XCTAssertEqual(tally.processed, 1)
    }

    func testClassifierInputFromFreshBlocksExcludesDeletedBuiltIns() throws {
        var lib = library(["a"])
        let receipts = try XCTUnwrap(lib.folders.first { $0.builtIn == .receipt })
        lib.deleteFolder(receipts.id)
        let input = ClassifierInput(blocks: [block("第一行"), block("第二行")], barcodes: [], excluded: lib.excludedTargets)
        XCTAssertEqual(input.text, "第一行\n第二行")
        XCTAssertEqual(input.excluded, [.builtIn(.receipt)])
    }
}

/// Screenshots restored from a backup keep their places but come back without recognized text.
final class RestoredShotProcessingTests: XCTestCase {
    private func shot(_ id: String, _ placement: Placement, folderID: UUID? = nil) -> Shot {
        Shot(id: id, createdAt: Date(timeIntervalSince1970: 1_000_000), pixelWidth: 1179, pixelHeight: 2556, folderID: folderID, placement: placement)
    }

    private func restoredLibrary() -> Library {
        var lib = Library()
        let receipts = lib.folders.first { $0.builtIn == .receipt }!.id
        lib = Library(
            shots: [
                shot("user", .user, folderID: receipts),
                shot("auto", .auto(AutoPlacement(source: .rule, classifierVersion: ClassificationPipeline.version)), folderID: receipts),
                shot("new", .pending),
            ],
            folders: lib.folders
        )
        return lib
    }

    func testWorkCountIncludesRestoredShotsAwaitingRecognition() {
        let lib = restoredLibrary()
        XCTAssertEqual(lib.count(in: .processing), 1, "only the new screenshot shows under 處理中")
        XCTAssertEqual(lib.processingWorkCount, 3, "all three still need recognition")
    }

    func testRestoredPlacementsAreNotCountedAsNewlyClassified() {
        var lib = restoredLibrary()
        let outcomes = ["user", "auto", "new"].map {
            ProcessingOutcome(id: $0, recognition: .recognized(blocks: [], barcodes: []), classification: .init(verdict: nil, features: []))
        }
        let tally = lib.applyProcessingOutcomes(outcomes, version: ClassificationPipeline.version)
        XCTAssertEqual(tally, ProcessingTally(processed: 3, failed: 0, classified: 0, unsorted: 1))
        XCTAssertEqual(lib.processingWorkCount, 0)
    }

    func testFailedRestoredShotWaitsForRetry() {
        var lib = restoredLibrary()
        let tally = lib.applyProcessingOutcomes([ProcessingOutcome(id: "user", recognition: .failed, classification: nil)], version: 1)
        XCTAssertEqual(tally.failed, 1, "it still needs recognition, so it is retried next run")
        XCTAssertEqual(lib.processingWorkCount, 3)
    }

    func testProgressTotalStaysPutWhileRestoredShotsAreProcessed() {
        var lib = restoredLibrary()
        var progress = ProcessingProgress()
        progress.begin(workCount: lib.processingWorkCount)
        XCTAssertEqual(progress.total, 3)
        let tally = lib.applyProcessingOutcomes(
            [ProcessingOutcome(id: "user", recognition: .recognized(blocks: [], barcodes: []), classification: .init(verdict: nil, features: []))],
            version: ClassificationPipeline.version
        )
        progress.record(tally, workCount: lib.processingWorkCount)
        XCTAssertEqual(progress.completed, 1)
        XCTAssertEqual(progress.total, 3)
    }
}
