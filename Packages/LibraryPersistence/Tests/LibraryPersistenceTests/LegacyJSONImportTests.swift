@testable import LibraryPersistence
import ScreenshotKit
import XCTest

final class LegacyJSONImportTests: XCTestCase {
    private func open(_ directory: URL) -> SQLiteLibraryDatabase {
        SQLiteLibraryDatabase(
            databaseURL: directory.appendingPathComponent("library.sqlite"),
            legacyJSONURL: directory.appendingPathComponent("library.json")
        )
    }

    private func loaded(_ store: SQLiteLibraryDatabase) throws -> Library? {
        guard case let .loaded(library) = try store.load() else { return nil }
        return library
    }

    func testImportsLibraryJSONOnceAndKeepsTheFile() throws {
        let dir = try temporaryDirectory()
        try FileManager.default.copyItem(at: fixtureURL(), to: dir.appendingPathComponent("library.json"))

        // Built-in folders the file predates get a new id on every decode, so compare contents, not ids.
        let imported = try XCTUnwrap(loaded(open(dir)))
        let fixture = try fixtureLibrary()
        XCTAssertEqual(imported.shots, fixture.shots)
        XCTAssertEqual(imported.folders.map(\.name), fixture.folders.map(\.name))
        XCTAssertEqual(imported.folders.map(\.builtIn), fixture.folders.map(\.builtIn))
        XCTAssertTrue(try fileNames(in: dir).contains("library.imported.json"))
        XCTAssertFalse(try fileNames(in: dir).contains("library.json"))

        // A library.json that shows up later is not imported again.
        try LibraryCodec.encode(Library()).write(to: dir.appendingPathComponent("library.json"))
        XCTAssertEqual(try loaded(open(dir)), imported)
        XCTAssertTrue(try fileNames(in: dir).contains("library.json"))
    }

    func testUnreadableLibraryJSONIsMovedAsideNotImported() throws {
        let dir = try temporaryDirectory()
        try Data("{\"shots\": [".utf8).write(to: dir.appendingPathComponent("library.json"))

        guard case .empty = try open(dir).load() else { return XCTFail("expected empty") }
        let names = try fileNames(in: dir)
        XCTAssertTrue(names.contains { $0.hasPrefix("library.unreadable-") })
        XCTAssertFalse(names.contains("library.imported.json"))
    }

    func testFreshInstallStartsEmpty() throws {
        let dir = try temporaryDirectory()

        guard case .empty = try open(dir).load() else { return XCTFail("expected empty") }
        XCTAssertFalse(try fileNames(in: dir).contains("library.imported.json"))
    }

    func testSavesSurviveReopening() throws {
        let dir = try temporaryDirectory()
        var library = Library()
        library.sync(with: [AssetInfo(id: "a", createdAt: Date(timeIntervalSinceReferenceDate: 781_000_000.123456), pixelWidth: 10, pixelHeight: 20)])
        try open(dir).save(library, changes: .everything(in: library))

        XCTAssertEqual(try loaded(open(dir)), library)
    }
}
