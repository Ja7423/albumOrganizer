import ScreenshotKit
import XCTest

final class LibraryTests: XCTestCase {
    private func asset(_ id: String, _ minutesAgo: Double) -> AssetInfo {
        AssetInfo(id: id, createdAt: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60), pixelWidth: 1179, pixelHeight: 2556)
    }

    private func block(_ text: String, y: Double = 0.3) -> TextBlock {
        TextBlock(id: 0, text: text, box: NormalizedRect(x: 0.1, y: y, width: 0.5, height: 0.02))
    }

    func testSyncAddsNewestFirstAndDropsDeleted() {
        var lib = Library()
        lib.sync(with: [asset("a", 10), asset("b", 1)])
        XCTAssertEqual(lib.shots.map(\.id), ["b", "a"])
        XCTAssertEqual(lib.pendingRecognitionIDs, ["b", "a"])

        let result = lib.sync(with: [asset("b", 1), asset("c", 0)])
        XCTAssertEqual(result, Library.SyncResult(added: ["c"], removed: 1))
        XCTAssertEqual(lib.shots.map(\.id), ["c", "b"])
    }

    func testHiddenShotsStayHiddenAcrossSync() {
        var lib = Library()
        lib.sync(with: [asset("a", 1), asset("b", 2)])
        lib.hide(["a"])
        lib.sync(with: [asset("a", 1), asset("b", 2)])
        XCTAssertEqual(lib.shots.map(\.id), ["b"])
    }

    func testFailedRecognitionRetriesThenGivesUp() {
        var lib = Library()
        lib.sync(with: [asset("a", 1)])
        lib.setRecognition("a", blocks: nil)
        XCTAssertEqual(lib.shot("a")?.recognition, .failed)
        XCTAssertEqual(lib.pendingRecognitionIDs, ["a"], "a failed attempt is retried")

        lib.setRecognition("a", blocks: nil)
        lib.setRecognition("a", blocks: nil)
        XCTAssertEqual(lib.pendingRecognitionIDs, [])
        XCTAssertEqual(lib.pendingClassificationIDs, ["a"], "out of retries, it is classified as textless")
    }

    func testRecognitionAloneDoesNotPlace() throws {
        var lib = Library()
        lib.sync(with: [asset("a", 1)])
        lib.setRecognition("a", blocks: [block("電子發票證明聯")], barcodes: ["https://einvoice"])
        let shot = try XCTUnwrap(lib.shot("a"))
        XCTAssertEqual(shot.recognition, .done)
        XCTAssertEqual(shot.barcodes, ["https://einvoice"])
        XCTAssertTrue(shot.isProcessing)
        XCTAssertEqual(lib.count(in: .processing), 1)
        XCTAssertEqual(lib.count(in: .unsorted), 0, "processing shots are not 未分類")
        XCTAssertEqual(lib.pendingClassificationIDs, ["a"])
    }

    func testOneFolderPerShot() throws {
        var lib = Library()
        lib.sync(with: [asset("a", 1), asset("b", 2)])
        let work = try XCTUnwrap(lib.createFolder(named: " 工作 "))
        let travel = try XCTUnwrap(lib.createFolder(named: "旅行"))
        XCTAssertEqual(work.name, "工作")
        XCTAssertEqual(lib.createFolder(named: "工作")?.id, work.id)

        lib.move(["a", "b"], to: work.id)
        lib.move(["a"], to: travel.id)
        XCTAssertEqual(lib.count(in: .folder(work.id)), 1)
        XCTAssertEqual(lib.count(in: .folder(travel.id)), 1)
        XCTAssertEqual(lib.count(in: .unsorted), 0)

        lib.deleteFolder(travel.id)
        XCTAssertNil(lib.shot("a")?.folderID)
        XCTAssertEqual(lib.folderName(nil), "未分類")
    }

    func testToggleTagAddsToAllUnlessAllHaveIt() {
        var lib = Library()
        lib.sync(with: [asset("a", 1), asset("b", 2)])
        lib.addTag("#收據", to: ["a"])
        XCTAssertEqual(lib.tags, ["收據"])

        lib.toggleTag("收據", on: ["a", "b"])
        XCTAssertEqual(lib.count(in: .tag("收據")), 2)

        lib.toggleTag("收據", on: ["a", "b"])
        XCTAssertEqual(lib.count(in: .tag("收據")), 0)
        XCTAssertEqual(lib.tags, ["收據"], "removing a tag from shots keeps the tag itself")
    }

    func testDeleteTagRemovesItEverywhere() {
        var lib = Library()
        lib.sync(with: [asset("a", 1)])
        lib.addTag("靈感", to: ["a"])
        lib.deleteTag("靈感")
        XCTAssertEqual(lib.tags, [])
        XCTAssertEqual(lib.shot("a")?.tags, [])
    }

    func testTitleSkipsClockAndShortLines() {
        let shot = Shot(id: "x", createdAt: Date(), pixelWidth: 1, pixelHeight: 2,
                        blocks: [block("9:41"), block("<"), block("訂單已成立")])
        XCTAssertEqual(shot.title, "訂單已成立")
        XCTAssertEqual(Shot(id: "y", createdAt: Date(), pixelWidth: 1, pixelHeight: 2).title, "螢幕截圖")
    }

    func testStatusBarLinesAreDropped() {
        let blocks = [block("9:41", y: 0.01), block("5G", y: 0.012), block("訂單明細", y: 0.08)]
        let kept = TextBlockFilter.droppingStatusBar(blocks)
        XCTAssertEqual(kept.map(\.text), ["訂單明細"])
        XCTAssertEqual(kept.map(\.id), [0])
    }

    func testLanguageSummary() {
        let shot = Shot(id: "x", createdAt: Date(), pixelWidth: 1, pixelHeight: 2, blocks: [block("航班 BR 198")])
        XCTAssertEqual(shot.languageSummary, "繁體中文 / 英文")
    }

    // MARK: - Classification

    private func verdict(_ category: BuiltInCategory) -> ClassifierVerdict {
        ClassifierVerdict(target: .builtIn(category), confidence: 0.9, source: .rule)
    }

    private func builtInFolder(_ lib: Library, _ category: BuiltInCategory) -> Folder? {
        lib.folders.first { $0.builtIn == category }
    }

    func testNewLibraryHasBuiltInFolders() {
        let lib = Library()
        XCTAssertEqual(lib.folders.compactMap(\.builtIn), BuiltInCategory.allCases)
        XCTAssertEqual(lib.folders.first?.name, "收據")
    }

    func testClassificationPlacesIntoBuiltInFolder() throws {
        var lib = Library()
        lib.sync(with: [asset("a", 1), asset("b", 2)])
        lib.applyClassification("a", verdict: verdict(.receipt), features: [.qrCode], version: 3)
        lib.applyClassification("b", verdict: nil, features: [], version: 3)

        let receipts = try XCTUnwrap(builtInFolder(lib, .receipt))
        XCTAssertEqual(lib.shot("a")?.folderID, receipts.id)
        XCTAssertEqual(lib.shot("a")?.placement, .auto(AutoPlacement(source: .rule, classifierVersion: 3)))
        XCTAssertEqual(lib.shot("a")?.featureTags, [.qrCode])
        XCTAssertEqual(lib.shot("b")?.placement, .auto(AutoPlacement(source: nil, classifierVersion: 3)))
        XCTAssertEqual(lib.shots(in: .unsorted).map(\.id), ["b"])
        XCTAssertEqual(lib.count(in: .processing), 0)
        XCTAssertEqual(lib.classificationSummary, ClassificationSummary(classified: 1, unsorted: 1))
        XCTAssertEqual(lib.count(in: .feature(.qrCode)), 1)
        XCTAssertEqual(lib.presentFeatureTags, [.qrCode])
    }

    func testEmptyFoldersSortLastAndFollowMoves() throws {
        var lib = Library()
        lib.sync(with: [asset("a", 1)])
        let receipts = try XCTUnwrap(builtInFolder(lib, .receipt))
        let last = try XCTUnwrap(lib.folders.last)
        XCTAssertEqual(lib.foldersEmptyLast.map(\.id), lib.folders.map(\.id))

        lib.move(["a"], to: last.id)
        XCTAssertEqual(lib.foldersEmptyLast.first?.id, last.id)
        XCTAssertEqual(lib.foldersEmptyLast.dropFirst().map(\.id), lib.folders.dropLast().map(\.id))

        lib.move(["a"], to: receipts.id)
        XCTAssertEqual(lib.foldersEmptyLast.map(\.id), lib.folders.map(\.id))
    }

    func testManualMoveWinsOverRunningClassification() {
        var lib = Library()
        lib.sync(with: [asset("a", 1)])
        lib.move(["a"], to: nil)
        lib.applyClassification("a", verdict: verdict(.receipt), features: [.link], version: 1)
        XCTAssertNil(lib.shot("a")?.folderID)
        XCTAssertEqual(lib.shot("a")?.placement, .user)
        XCTAssertEqual(lib.count(in: .unsorted), 1)
    }

    func testDeletingBuiltInFolderRequeuesAutomaticShotsOnly() throws {
        var lib = Library()
        lib.sync(with: [asset("auto", 1), asset("mine", 2)])
        let social = try XCTUnwrap(builtInFolder(lib, .social))
        lib.applyClassification("auto", verdict: verdict(.social), features: [], version: 1)
        lib.move(["mine"], to: social.id)

        lib.deleteFolder(social.id)
        XCTAssertNil(builtInFolder(lib, .social))
        XCTAssertEqual(lib.shot("auto")?.placement, .pending)
        XCTAssertNil(lib.shot("auto")?.folderID)
        XCTAssertEqual(lib.shot("mine")?.placement, .user)
        XCTAssertNil(lib.shot("mine")?.folderID)
        XCTAssertEqual(lib.classifierInput(for: "auto")?.excluded, [.builtIn(.social)])

        lib.applyClassification("auto", verdict: verdict(.social), features: [], version: 1)
        XCTAssertNil(lib.shot("auto")?.folderID, "a deleted category is never a destination")
        XCTAssertEqual(lib.shot("auto")?.autoPlacement?.source, nil)
    }

    func testDeletedBuiltInIsNotRecreatedAfterReload() throws {
        var lib = Library()
        try lib.deleteFolder(XCTUnwrap(builtInFolder(lib, .note)?.id))
        let reloaded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(lib))
        XCTAssertNil(builtInFolder(reloaded, .note))
        XCTAssertEqual(reloaded.folders.count, BuiltInCategory.allCases.count - 1)
        XCTAssertEqual(reloaded.deletedBuiltIns, [.note])
    }

    func testRequeueOutdatedLeavesUserAndCurrentPlacements() {
        var lib = Library()
        lib.sync(with: [asset("old", 1), asset("new", 2), asset("mine", 3)])
        lib.applyClassification("old", verdict: verdict(.code), features: [], version: 1)
        lib.applyClassification("new", verdict: verdict(.code), features: [], version: 2)
        lib.move(["mine"], to: nil)

        lib.requeueOutdated(version: 2)
        XCTAssertEqual(lib.shots(in: .processing).map(\.id), ["old"])
        XCTAssertEqual(lib.shot("mine")?.placement, .user)
    }

    func testDismissedFeatureTagIsNotAddedBack() {
        var lib = Library()
        lib.sync(with: [asset("a", 1)])
        lib.applyClassification("a", verdict: nil, features: [.date, .link], version: 1)
        lib.dismissFeatureTag(.date, from: "a")
        XCTAssertEqual(lib.shot("a")?.featureTags, [.link])

        lib.requeueOutdated(version: 2)
        lib.applyClassification("a", verdict: nil, features: [.date, .link], version: 2)
        XCTAssertEqual(lib.shot("a")?.featureTags, [.link])
    }

    func testRenameFolderRejectsEmptyAndDuplicateNames() throws {
        var lib = Library()
        let receipts = try XCTUnwrap(builtInFolder(lib, .receipt))
        XCTAssertTrue(lib.renameFolder(receipts.id, to: " 帳單 "))
        XCTAssertEqual(lib.folderName(receipts.id), "帳單")
        XCTAssertEqual(lib.folder(receipts.id)?.builtIn, .receipt, "renaming keeps the category key")
        XCTAssertFalse(lib.renameFolder(receipts.id, to: "  "))
        XCTAssertFalse(lib.renameFolder(receipts.id, to: "票券"))
        XCTAssertEqual(lib.folderName(receipts.id), "帳單")
    }
}
