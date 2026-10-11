@testable import LibraryPersistence
import ScreenshotKit
import XCTest

final class JSONLibraryFileTests: XCTestCase {
    func testMissingFileIsEmpty() throws {
        let file = try JSONLibraryFile(fileURL: temporaryDirectory().appendingPathComponent("library.json"))

        guard case .empty = try file.load() else { return XCTFail("expected empty") }
    }

    func testSavedLibraryLoadsBack() throws {
        let file = try JSONLibraryFile(fileURL: temporaryDirectory().appendingPathComponent("library.json"))
        let library = try fixtureLibrary()
        try file.save(library, changes: LibraryChanges())

        guard case let .loaded(loaded) = try file.load() else { return XCTFail("expected loaded") }
        XCTAssertEqual(loaded, library)
    }

    func testUnreadableFileIsMovedAsideWithTimestamp() throws {
        let dir = try temporaryDirectory()
        let url = dir.appendingPathComponent("library.json")
        try Data("not json".utf8).write(to: url)
        let file = JSONLibraryFile(fileURL: url, now: { Date(timeIntervalSinceReferenceDate: 0) })

        guard case let .unreadable(backupURL, _) = try file.load() else { return XCTFail("expected unreadable") }
        XCTAssertEqual(backupURL.lastPathComponent, "library.unreadable-20010101T000000.json")
        XCTAssertEqual(try Data(contentsOf: backupURL), Data("not json".utf8))
        XCTAssertEqual(try fileNames(in: dir), ["library.unreadable-20010101T000000.json"])
    }
}
