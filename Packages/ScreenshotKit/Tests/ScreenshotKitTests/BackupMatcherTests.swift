import ScreenshotKit
import XCTest

final class BackupMatcherTests: XCTestCase {
    private func date(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private func key(_ localID: String, cloud: String? = nil, at seconds: Double, width: Int = 1179) -> BackupShotKey {
        BackupShotKey(localID: localID, cloudID: cloud, createdAt: date(seconds), pixelWidth: width, pixelHeight: 2556)
    }

    private func asset(_ id: String, at seconds: Double, width: Int = 1179) -> AssetInfo {
        AssetInfo(id: id, createdAt: date(seconds), pixelWidth: width, pixelHeight: 2556)
    }

    private func shot(_ key: BackupShotKey) -> BackupShot {
        BackupShot(key: key, folderID: nil, placement: .user)
    }

    func testMatchesByCloudIdentifier() {
        let snapshot = BackupSnapshot(createdAt: date(0), shots: [shot(key("old-a", cloud: "c-a", at: 100))])
        let result = BackupMatcher.match(snapshot, assets: [asset("new-a", at: 999)], localIDsByCloudID: ["c-a": "new-a"])
        XCTAssertEqual(result.restore.shots.keys.sorted(), ["new-a"])
        XCTAssertTrue(result.leftover.hasNoScreenshots)
    }

    func testFallsBackToCaptureTimeAndSizeWhenUnique() {
        let snapshot = BackupSnapshot(createdAt: date(0), shots: [shot(key("old-a", at: 100.2))])
        let result = BackupMatcher.match(snapshot, assets: [asset("new-a", at: 100), asset("new-b", at: 100, width: 750)], localIDsByCloudID: [:])
        XCTAssertEqual(result.restore.shots.keys.sorted(), ["new-a"])
    }

    func testAmbiguousCaptureKeyIsLeftUnmatched() {
        let twoAssets = BackupMatcher.match(
            BackupSnapshot(createdAt: date(0), shots: [shot(key("old-a", at: 100))]),
            assets: [asset("new-a", at: 100), asset("new-b", at: 100)],
            localIDsByCloudID: [:]
        )
        XCTAssertTrue(twoAssets.restore.isEmpty)
        XCTAssertEqual(twoAssets.leftover.shots.count, 1)

        let twoBackups = BackupMatcher.match(
            BackupSnapshot(createdAt: date(0), shots: [shot(key("old-a", at: 100)), shot(key("old-b", at: 100))]),
            assets: [asset("new-a", at: 100)],
            localIDsByCloudID: [:]
        )
        XCTAssertTrue(twoBackups.restore.isEmpty)
    }

    func testAnAssetClaimedByCloudIdentifierIsNotMatchedAgain() {
        let snapshot = BackupSnapshot(createdAt: date(0), shots: [
            shot(key("old-a", cloud: "c-a", at: 100)),
            shot(key("old-b", at: 100)),
        ])
        let result = BackupMatcher.match(snapshot, assets: [asset("new-a", at: 100)], localIDsByCloudID: ["c-a": "new-a"])
        XCTAssertEqual(result.restore.shots["new-a"]?.key.localID, "old-a")
        XCTAssertEqual(result.leftover.shots.map(\.key.localID), ["old-b"])
    }

    func testCloudIdentifierOfAMissingAssetFallsThrough() {
        let snapshot = BackupSnapshot(createdAt: date(0), shots: [shot(key("old-a", cloud: "c-a", at: 100))])
        let result = BackupMatcher.match(snapshot, assets: [], localIDsByCloudID: ["c-a": "gone"])
        XCTAssertTrue(result.restore.isEmpty)
        XCTAssertEqual(result.leftover.shots.count, 1)
    }

    func testHiddenScreenshotsAreReportedSeparately() {
        let folder = Folder(name: "旅行")
        let snapshot = BackupSnapshot(
            createdAt: date(0),
            folders: [folder],
            tags: ["t"],
            shots: [shot(key("old-a", cloud: "c-a", at: 1))],
            hiddenShots: [key("old-h", cloud: "c-h", at: 2), key("old-x", at: 3)]
        )
        let result = BackupMatcher.match(
            snapshot,
            assets: [asset("new-a", at: 1), asset("new-h", at: 2)],
            localIDsByCloudID: ["c-a": "new-a", "c-h": "new-h"]
        )
        XCTAssertEqual(result.restore.hiddenIDs, ["new-h"])
        XCTAssertEqual(result.restore.folders, [folder])
        XCTAssertEqual(result.leftover.hiddenShots.map(\.localID), ["old-x"])
        XCTAssertEqual(result.leftover.folders, [folder], "leftovers keep the folders to map onto later")
    }
}
