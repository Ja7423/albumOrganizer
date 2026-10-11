import ScreenshotKit
import XCTest

final class LibraryCodecTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "library-v0", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    /// `library-v0.json` was written by the app before `schemaVersion` existed.
    func testDecodesFileWithoutSchemaVersion() throws {
        let lib = try LibraryCodec.decode(fixture())

        XCTAssertEqual(lib.shots.map(\.id), ["receipt-shot", "user-shot", "pending-shot"])
        XCTAssertEqual(lib.hiddenShotIDs, ["hidden-shot"])
        XCTAssertEqual(lib.deletedBuiltIns, [.recipe])
        XCTAssertEqual(lib.tags, ["報帳"])
        XCTAssertFalse(lib.folders.contains { $0.builtIn == .recipe })

        let receipt = try XCTUnwrap(lib.shot("receipt-shot"))
        XCTAssertEqual(receipt.autoPlacement, AutoPlacement(source: .rule, classifierVersion: 3))
        XCTAssertEqual(receipt.folderID, lib.folders.first { $0.builtIn == .receipt }?.id)
        XCTAssertEqual(receipt.blocks.map(\.text), ["電子發票證明聯"])
        XCTAssertEqual(receipt.featureTags, [.date])
        XCTAssertEqual(receipt.dismissedFeatureTags, [.link])
        XCTAssertEqual(receipt.tags, ["報帳"])

        let user = try XCTUnwrap(lib.shot("user-shot"))
        XCTAssertEqual(user.placement, .user)
        XCTAssertEqual(try lib.folder(XCTUnwrap(user.folderID))?.name, "旅行")
        XCTAssertEqual(user.recognition, .failed)
        XCTAssertEqual(user.recognitionAttempts, 1)

        XCTAssertEqual(lib.shot("pending-shot")?.placement, .pending)
    }

    func testRoundTripsAndWritesSchemaVersion() throws {
        let lib = try LibraryCodec.decode(fixture())
        let data = try LibraryCodec.encode(lib)

        XCTAssertEqual(try LibraryCodec.decode(data), lib)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, LibraryCodec.currentSchemaVersion)
    }

    func testMissingLibraryKeysFallBackToEmpty() throws {
        let lib = try LibraryCodec.decode(Data(#"{"shots": []}"#.utf8))

        XCTAssertEqual(lib.shots, [])
        XCTAssertEqual(lib.tags, [])
        XCTAssertEqual(lib.hiddenShotIDs, [])
        XCTAssertEqual(lib.folders.count, BuiltInCategory.allCases.count)
    }

    func testMissingShotFieldsFallBackToDefaults() throws {
        let json = #"{"shots": [{"id": "a", "createdAt": 0, "pixelWidth": 10, "pixelHeight": 20}]}"#
        let shot = try XCTUnwrap(LibraryCodec.decode(Data(json.utf8)).shot("a"))

        XCTAssertEqual(shot.placement, .pending)
        XCTAssertEqual(shot.recognition, .pending)
        XCTAssertEqual(shot.blocks, [])
        XCTAssertEqual(shot.tags, [])
        XCTAssertNil(shot.folderID)
    }

    func testRefusesNewerSchema() {
        let json = #"{"schemaVersion": \#(LibraryCodec.currentSchemaVersion + 1), "shots": []}"#

        XCTAssertThrowsError(try LibraryCodec.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? LibraryCodec.DecodeError, .newerSchema(LibraryCodec.currentSchemaVersion + 1))
        }
    }

    func testCorruptDataIsUnreadable() {
        for raw in ["", "{\"shots\": [", "[]", #"{"shots": [{"id": "a"}]}"#] {
            XCTAssertThrowsError(try LibraryCodec.decode(Data(raw.utf8)), raw) { error in
                guard case .unreadable = error as? LibraryCodec.DecodeError else {
                    return XCTFail("\(raw): expected unreadable, got \(error)")
                }
            }
        }
    }

    // MARK: - Enum values from another app version

    private func shotJSON(_ fields: String) -> String {
        #"{"shots": [{"id": "a", "createdAt": 0, "pixelWidth": 10, "pixelHeight": 20, \#(fields)}]}"#
    }

    func testUnknownFeatureTagsAreDropped() throws {
        let json = shotJSON(#""featureTags": ["date", "email"], "dismissedFeatureTags": ["sticker", "link"]"#)
        let shot = try XCTUnwrap(LibraryCodec.decode(Data(json.utf8)).shot("a"))

        XCTAssertEqual(shot.featureTags, [.date])
        XCTAssertEqual(shot.dismissedFeatureTags, [.link])
    }

    func testUnknownRecognitionStateIsRecognizedAgain() throws {
        let json = shotJSON(#""recognition": "partial", "blocks": []"#)
        let shot = try XCTUnwrap(LibraryCodec.decode(Data(json.utf8)).shot("a"))

        XCTAssertEqual(shot.recognition, .pending)
    }

    func testUnknownPlacementIsClassifiedAgain() throws {
        let unknownCase = shotJSON(#""placement": {"suggested": {}}"#)
        let unknownSource = shotJSON(#""placement": {"auto": {"_0": {"source": "vision", "classifierVersion": 9}}}"#)

        XCTAssertEqual(try LibraryCodec.decode(Data(unknownCase.utf8)).shot("a")?.placement, .pending)
        XCTAssertEqual(try LibraryCodec.decode(Data(unknownSource.utf8)).shot("a")?.placement, .pending)
    }

    func testUnknownBuiltInFolderBecomesOrdinaryFolder() throws {
        let folderID = UUID()
        let json = """
        {"folders": [{"id": "\(folderID)", "name": "郵件", "builtIn": "email"}],
         "shots": [{"id": "a", "createdAt": 0, "pixelWidth": 10, "pixelHeight": 20, "folderID": "\(folderID)"}]}
        """
        let lib = try LibraryCodec.decode(Data(json.utf8))

        let folder = try XCTUnwrap(lib.folder(folderID))
        XCTAssertEqual(folder.name, "郵件")
        XCTAssertNil(folder.builtIn)
        XCTAssertEqual(lib.shot("a")?.folderID, folderID)
    }

    func testUnknownDeletedBuiltInsAreDropped() throws {
        let lib = try LibraryCodec.decode(Data(#"{"deletedBuiltIns": ["recipe", "email"]}"#.utf8))

        XCTAssertEqual(lib.deletedBuiltIns, [.recipe])
    }
}
