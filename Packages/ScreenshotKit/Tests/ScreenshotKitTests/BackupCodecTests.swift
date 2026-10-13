import ScreenshotKit
import XCTest

final class BackupCodecTests: XCTestCase {
    private let key = BackupShotKey(localID: "a", cloudID: "c-a", createdAt: Date(timeIntervalSinceReferenceDate: 100), pixelWidth: 10, pixelHeight: 20)

    func testRoundTrip() throws {
        let folder = Folder(name: "旅行")
        let snapshot = BackupSnapshot(
            createdAt: Date(timeIntervalSinceReferenceDate: 500),
            folders: [folder],
            tags: ["工作"],
            deletedBuiltIns: [.receipt],
            shots: [
                BackupShot(key: key, folderID: folder.id, placement: .user, tags: ["工作"], featureTags: [.qrCode], dismissedFeatureTags: [.link]),
                BackupShot(key: key, folderID: nil, placement: .auto(AutoPlacement(source: .rule, classifierVersion: 3, isRefined: true))),
            ],
            hiddenShots: [key]
        )
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(snapshot)), snapshot)
    }

    func testRefusesNewerSchema() {
        let data = Data(#"{"schemaVersion": 99, "createdAt": 0}"#.utf8)
        XCTAssertThrowsError(try BackupCodec.decode(data)) { error in
            XCTAssertEqual(error as? BackupCodec.DecodeError, .newerSchema(99))
        }
    }

    func testDropsUnknownValuesInsteadOfFailing() throws {
        let json = """
        {"schemaVersion": 1, "createdAt": 0, "deletedBuiltIns": ["receipt", "fromTheFuture"],
         "shots": [{"key": {"localID": "a", "createdAt": 0, "pixelWidth": 1, "pixelHeight": 1},
                    "placement": {"user": {}}, "featureTags": ["qrCode", "fromTheFuture"]}]}
        """
        let snapshot = try BackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(snapshot.deletedBuiltIns, [.receipt])
        XCTAssertEqual(snapshot.shots.first?.featureTags, [.qrCode])
        XCTAssertEqual(snapshot.shots.first?.placement, .user)
    }

    func testUnreadableData() {
        XCTAssertThrowsError(try BackupCodec.decode(Data("nope".utf8))) { error in
            guard case .unreadable = error as? BackupCodec.DecodeError else { return XCTFail("\(error)") }
        }
    }
}
