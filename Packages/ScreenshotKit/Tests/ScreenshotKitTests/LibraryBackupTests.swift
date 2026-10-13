import ScreenshotKit
import XCTest

final class LibraryBackupTests: XCTestCase {
    private let auto = Placement.auto(AutoPlacement(source: .rule, classifierVersion: 1))

    private func asset(_ id: String, _ seconds: Double = 0) -> AssetInfo {
        AssetInfo(id: id, createdAt: Date(timeIntervalSinceReferenceDate: seconds), pixelWidth: 1179, pixelHeight: 2556)
    }

    private func backup(_ id: String, folder: UUID?, placement: Placement, tags: [String] = []) -> BackupShot {
        BackupShot(
            key: BackupShotKey(localID: id, cloudID: nil, createdAt: .distantPast, pixelWidth: 1, pixelHeight: 1),
            folderID: folder,
            placement: placement,
            tags: tags
        )
    }

    private func block(_ text: String) -> TextBlock {
        TextBlock(id: 0, text: text, box: NormalizedRect(x: 0.1, y: 0.3, width: 0.5, height: 0.02))
    }

    private func folderID(_ lib: Library, _ category: BuiltInCategory) -> UUID {
        lib.folders.first { $0.builtIn == category }!.id
    }

    // MARK: - Snapshot

    func testSnapshotLeavesOutTextAndProcessingScreenshots() throws {
        var lib = Library()
        lib.sync(with: [asset("a", 2), asset("b", 1)])
        lib.setRecognition("a", blocks: [block("機密內容")])
        lib.move(["a"], to: folderID(lib, .receipt))

        let snapshot = lib.backupSnapshot(createdAt: .distantPast, cloudIDsByLocalID: ["a": "c-a"], hiddenAssets: [])
        XCTAssertEqual(snapshot.shots.map(\.key.localID), ["a"], "b is still 處理中")
        XCTAssertEqual(snapshot.shots.first?.key.cloudID, "c-a")
        let json = try String(decoding: BackupCodec.encode(snapshot), as: UTF8.self)
        XCTAssertFalse(json.contains("機密內容"))
    }

    func testSnapshotCarriesHiddenAndPendingScreenshots() {
        var lib = Library()
        lib.sync(with: [asset("a"), asset("h", 5)])
        lib.hide(["h"])
        let pending = BackupSnapshot(
            createdAt: .distantPast,
            shots: [backup("not-yet", folder: nil, placement: .user)],
            hiddenShots: [BackupShotKey(localID: "hidden-not-yet", cloudID: nil, createdAt: .distantPast, pixelWidth: 1, pixelHeight: 1)]
        )

        let snapshot = lib.backupSnapshot(createdAt: .distantPast, cloudIDsByLocalID: [:], hiddenAssets: [asset("h", 5)], pending: pending)
        XCTAssertEqual(snapshot.shots.map(\.key.localID), ["not-yet"])
        XCTAssertEqual(snapshot.hiddenShots.map(\.localID), ["h", "hidden-not-yet"])
        XCTAssertEqual(snapshot.hiddenShots.first?.createdAt, Date(timeIntervalSinceReferenceDate: 5))
    }

    // MARK: - Restore

    func testRestoreOntoFreshInstallMapsBuiltInFoldersByCategory() {
        let old = Library()
        var fresh = Library()
        fresh.sync(with: [asset("a"), asset("b")])
        XCTAssertNotEqual(folderID(old, .receipt), folderID(fresh, .receipt), "built-in folders get new ids on a new install")

        let restored = fresh.restoring(BackupRestore(
            folders: old.folders,
            shots: [
                "a": backup("a", folder: folderID(old, .receipt), placement: .user),
                "b": backup("b", folder: folderID(old, .ticket), placement: auto),
            ]
        ), mergingFolders: true)

        XCTAssertEqual(restored.shot("a")?.folderID, folderID(fresh, .receipt))
        XCTAssertEqual(restored.shot("a")?.placement, .user)
        XCTAssertEqual(restored.shot("b")?.folderID, folderID(fresh, .ticket))
        XCTAssertEqual(restored.shot("b")?.placement, auto)
        XCTAssertEqual(restored.folders.count, fresh.folders.count, "no duplicate folders")
        XCTAssertTrue(restored.pendingClassificationIDs.isEmpty)
    }

    func testPlacementPrecedence() {
        var lib = Library()
        lib.sync(with: [asset("localUser"), asset("localAuto"), asset("localPending")])
        let receipt = folderID(lib, .receipt)
        let ticket = folderID(lib, .ticket)
        lib.move(["localUser"], to: receipt)
        lib.setRecognition("localAuto", blocks: [])
        lib.applyClassification("localAuto", verdict: nil, features: [], version: 1)

        let restored = lib.restoring(BackupRestore(folders: lib.folders, shots: [
            "localUser": backup("localUser", folder: ticket, placement: .user),
            "localAuto": backup("localAuto", folder: ticket, placement: .user),
            "localPending": backup("localPending", folder: ticket, placement: auto),
        ]), mergingFolders: true)

        XCTAssertEqual(restored.shot("localUser")?.folderID, receipt, "a placement made on this device wins")
        XCTAssertEqual(restored.shot("localAuto")?.folderID, ticket)
        XCTAssertEqual(restored.shot("localAuto")?.placement, .user)
        XCTAssertEqual(restored.shot("localPending")?.folderID, ticket)
        XCTAssertEqual(restored.shot("localPending")?.placement, auto)
    }

    func testUserFoldersMatchByIdThenNameAndOtherwiseAreAdded() throws {
        var lib = Library()
        lib.sync(with: [asset("a"), asset("b"), asset("c")])
        let local = try XCTUnwrap(lib.createFolder(named: "旅行"))
        let sameID = Folder(id: local.id, name: "舊名字")
        let sameName = Folder(name: "旅行")
        let added = Folder(name: "家")

        let restored = lib.restoring(BackupRestore(folders: [sameID, sameName, added], shots: [
            "a": backup("a", folder: sameID.id, placement: .user),
            "b": backup("b", folder: sameName.id, placement: .user),
            "c": backup("c", folder: added.id, placement: .user),
        ]), mergingFolders: true)

        XCTAssertEqual(restored.folder(local.id)?.name, "旅行", "the local name wins")
        XCTAssertEqual(restored.shot("a")?.folderID, local.id)
        XCTAssertEqual(restored.shot("b")?.folderID, local.id)
        XCTAssertEqual(restored.shot("c")?.folderID, added.id)
        XCTAssertEqual(restored.folders.filter { $0.name == "旅行" }.count, 1)
        XCTAssertEqual(restored.folder(added.id)?.name, "家")
    }

    func testTagsAreUnionedInOrder() {
        var lib = Library()
        lib.sync(with: [asset("a")])
        lib.addTag("本機", to: ["a"])

        let restored = lib.restoring(BackupRestore(
            tags: ["備份", "本機", "空的"],
            shots: ["a": backup("a", folder: nil, placement: .user, tags: ["備份", "本機"])]
        ), mergingFolders: true)

        XCTAssertEqual(restored.tags, ["本機", "備份", "空的"])
        XCTAssertEqual(restored.shot("a")?.tags, ["本機", "備份"])
    }

    func testDismissedFeatureTagsStayDismissed() {
        var lib = Library()
        lib.sync(with: [asset("a")])
        var shot = backup("a", folder: nil, placement: auto)
        shot.featureTags = [.qrCode, .link]
        shot.dismissedFeatureTags = [.link]

        let restored = lib.restoring(BackupRestore(shots: ["a": shot]), mergingFolders: true)
        XCTAssertEqual(restored.shot("a")?.featureTags, [.qrCode])
        XCTAssertEqual(restored.shot("a")?.dismissedFeatureTags, [.link])
    }

    func testAFolderThatCannotBeMappedLeavesTheScreenshotAlone() {
        var lib = Library()
        lib.sync(with: [asset("a")])
        let gone = Folder(name: "已刪掉的資料夾")

        let restored = lib.restoring(BackupRestore(
            folders: [gone],
            shots: ["a": backup("a", folder: gone.id, placement: .user)]
        ), mergingFolders: false)

        XCTAssertNil(restored.folder(gone.id), "leftover matching never re-adds folders")
        XCTAssertEqual(restored.shot("a")?.placement, .pending, "stays in the queue to be classified")
    }

    func testLocallyDeletedBuiltInStaysDeleted() {
        let old = Library()
        var lib = Library()
        lib.sync(with: [asset("a")])
        lib.deleteFolder(folderID(lib, .receipt))

        let restored = lib.restoring(BackupRestore(
            folders: old.folders,
            shots: ["a": backup("a", folder: folderID(old, .receipt), placement: .user)]
        ), mergingFolders: true)

        XCTAssertFalse(restored.folders.contains { $0.builtIn == .receipt })
        XCTAssertEqual(restored.shot("a")?.placement, .pending)
    }

    func testBuiltInDeletedInBackupIsDeletedOnlyWhenEmptyHere() {
        var lib = Library()
        lib.sync(with: [asset("a")])
        lib.move(["a"], to: folderID(lib, .ticket))

        let restored = lib.restoring(BackupRestore(deletedBuiltIns: [.receipt, .ticket]), mergingFolders: true)

        XCTAssertEqual(restored.deletedBuiltIns, [.receipt])
        XCTAssertFalse(restored.folders.contains { $0.builtIn == .receipt })
        XCTAssertTrue(restored.folders.contains { $0.builtIn == .ticket })
    }

    func testHiddenScreenshotsAreRemovedAndStayHiddenAcrossSync() {
        var lib = Library()
        lib.sync(with: [asset("a"), asset("h")])

        var restored = lib.restoring(BackupRestore(hiddenIDs: ["h"]), mergingFolders: true)
        restored.sync(with: [asset("a"), asset("h")])

        XCTAssertEqual(restored.shots.map(\.id), ["a"])
        XCTAssertEqual(restored.hiddenShotIDs, ["h"])
    }

    func testPendingRestoreExpiresAfterThirtyDays() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let pending = PendingRestore(restoredAt: start, snapshot: BackupSnapshot(createdAt: start))
        XCTAssertFalse(pending.isExpired(now: start.addingTimeInterval(PendingRestore.lifetime)))
        XCTAssertTrue(pending.isExpired(now: start.addingTimeInterval(PendingRestore.lifetime + 1)))
    }
}
