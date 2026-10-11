import ScreenshotKit
import XCTest

final class LibraryChangesTests: XCTestCase {
    private func asset(_ id: String, _ minutesAgo: Double) -> AssetInfo {
        AssetInfo(id: id, createdAt: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60), pixelWidth: 1179, pixelHeight: 2556)
    }

    private func synced() -> Library {
        var lib = Library()
        lib.sync(with: [asset("a", 3), asset("b", 2), asset("c", 1)])
        return lib
    }

    func testUnchangedLibraryHasNoChanges() {
        var lib = synced()
        let old = lib
        lib.sync(with: [asset("a", 3), asset("b", 2), asset("c", 1)])

        XCTAssertTrue(lib.changes(since: old).isEmpty)
    }

    func testSyncReportsAddedAndDeletedShots() {
        var lib = synced()
        let old = lib
        lib.sync(with: [asset("b", 2), asset("c", 1), asset("d", 0)])

        let changes = lib.changes(since: old)
        XCTAssertEqual(changes.upsertedShotIDs, ["d"])
        XCTAssertEqual(changes.deletedShotIDs, ["a"])
        XCTAssertFalse(changes.hasHiddenChanges)
    }

    func testRecognitionAndClassificationTouchOnlyThatShot() {
        var lib = synced()
        let old = lib
        lib.setRecognition("b", blocks: [])
        lib.applyClassification("b", verdict: nil, features: [], version: 3)

        XCTAssertEqual(lib.changes(since: old), LibraryChanges(upsertedShotIDs: ["b"]))
    }

    func testDeletingAFolderReportsFolderAndItsShots() throws {
        var lib = synced()
        let folder = try XCTUnwrap(lib.createFolder(named: "旅行"))
        lib.move(["a", "c"], to: folder.id)
        let old = lib
        lib.deleteFolder(folder.id)

        let changes = lib.changes(since: old)
        XCTAssertEqual(changes.upsertedShotIDs, ["c", "a"])
        XCTAssertTrue(changes.hasFolderChanges)
        XCTAssertFalse(changes.hasDeletedBuiltInChanges)
    }

    func testDeletingABuiltInFolderIsRemembered() throws {
        var lib = synced()
        let old = lib
        try lib.deleteFolder(XCTUnwrap(lib.folders.first { $0.builtIn == .recipe }).id)

        let changes = lib.changes(since: old)
        XCTAssertTrue(changes.hasFolderChanges)
        XCTAssertTrue(changes.hasDeletedBuiltInChanges)
        XCTAssertEqual(changes.upsertedShotIDs, [])
    }

    func testRenamingAFolderTouchesNoShots() throws {
        var lib = synced()
        let folder = try XCTUnwrap(lib.createFolder(named: "旅行"))
        let old = lib
        lib.renameFolder(folder.id, to: "出差")

        XCTAssertEqual(lib.changes(since: old), LibraryChanges(hasFolderChanges: true))
    }

    func testTaggingReportsTagListAndShots() {
        var lib = synced()
        let old = lib
        _ = lib.createTag("報帳")
        lib.addTag("報帳", to: ["a"])

        XCTAssertEqual(lib.changes(since: old), LibraryChanges(upsertedShotIDs: ["a"], hasTagChanges: true))
    }

    func testHidingRemovesShotAndUpdatesHiddenSet() {
        var lib = synced()
        let old = lib
        lib.hide(["b"])

        XCTAssertEqual(lib.changes(since: old), LibraryChanges(deletedShotIDs: ["b"], hasHiddenChanges: true))
    }

    func testRequeueingOutdatedPlacementsReportsThoseShots() {
        var lib = synced()
        lib.setRecognition("a", blocks: [])
        lib.applyClassification("a", verdict: nil, features: [], version: 1)
        let old = lib
        lib.requeueOutdated(version: 2)

        XCTAssertEqual(lib.changes(since: old), LibraryChanges(upsertedShotIDs: ["a"]))
    }
}
