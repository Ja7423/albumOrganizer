import GRDB
@testable import LibraryPersistence
import ScreenshotKit
import XCTest

final class SQLiteLibraryDatabaseTests: XCTestCase {
    private func savedFixture() throws -> (InMemoryLibrary, Library) {
        let db = try InMemoryLibrary()
        let library = try fixtureLibrary()
        try db.store.save(library, changes: .everything(in: library))
        return (db, library)
    }

    func testMigrationCreatesEveryTable() throws {
        let db = try InMemoryLibrary()
        let tables = try db.queue.read { db in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'") }

        XCTAssertTrue(Set(tables).isSuperset(of: ["folder", "tag", "shot", "hiddenShot", "deletedBuiltIn", "recognition"]))
    }

    func testEmptyDatabaseLoadsEmpty() throws {
        guard case .empty = try InMemoryLibrary().store.load() else { return XCTFail("expected empty") }
    }

    func testRoundTripsTheWholeLibrary() throws {
        let (db, library) = try savedFixture()

        XCTAssertEqual(try db.loadLibrary(), library)
    }

    func testSavesOnlyTheChangedShots() throws {
        let (db, library) = try savedFixture()
        // Tamper with a shot the next save must not touch.
        try db.queue.write { db in try db.execute(sql: "UPDATE shot SET pixelWidth = 1 WHERE id = 'pending-shot'") }

        var changed = library
        changed.addTag("報帳", to: ["user-shot"])
        try db.store.save(changed, changes: changed.changes(since: library))

        let loaded = try XCTUnwrap(db.loadLibrary())
        XCTAssertEqual(loaded.shot("user-shot")?.tags, ["報帳"])
        XCTAssertEqual(loaded.shot("pending-shot")?.pixelWidth, 1)
    }

    func testUpdatingAShotKeepsItsRecognition() throws {
        let (db, library) = try savedFixture()
        var changed = library
        changed.move(["receipt-shot"], to: nil)
        try db.store.save(changed, changes: changed.changes(since: library))

        XCTAssertEqual(try db.loadLibrary()?.shot("receipt-shot")?.blocks.map(\.text), ["電子發票證明聯"])
        XCTAssertEqual(try db.count("recognition"), library.shots.count)
    }

    func testRemovingAShotRemovesItsRecognition() throws {
        let (db, library) = try savedFixture()
        var changed = library
        changed.hide(["receipt-shot"])
        try db.store.save(changed, changes: changed.changes(since: library))

        XCTAssertEqual(try db.loadLibrary(), changed)
        XCTAssertEqual(try db.count("recognition"), library.shots.count - 1)
    }

    func testDeletingAFolderKeepsItsShots() throws {
        let (db, library) = try savedFixture()
        let travel = try XCTUnwrap(library.folders.first { $0.name == "旅行" })
        var changed = library
        changed.deleteFolder(travel.id)
        try db.store.save(changed, changes: changed.changes(since: library))

        let loaded = try XCTUnwrap(db.loadLibrary())
        XCTAssertEqual(loaded, changed)
        XCTAssertNil(loaded.folder(travel.id))
        XCTAssertNil(loaded.shot("user-shot")?.folderID)
    }

    func testFolderAndTagOrderSurvives() throws {
        let (db, library) = try savedFixture()
        var changed = library
        _ = changed.createTag("旅遊")
        _ = changed.createFolder(named: "工作")
        try db.store.save(changed, changes: changed.changes(since: library))

        let loaded = try XCTUnwrap(db.loadLibrary())
        XCTAssertEqual(loaded.tags, ["報帳", "旅遊"])
        XCTAssertEqual(loaded.folders.map(\.name), changed.folders.map(\.name))
    }

    func testValuesFromAnotherAppVersionAreTolerated() throws {
        let (db, _) = try savedFixture()
        try db.queue.write { db in
            try db.execute(sql: """
            UPDATE shot SET featureTags = '["date","email"]', placement = 'suggested' WHERE id = 'receipt-shot';
            UPDATE shot SET placement = 'auto', autoSource = 'vision', classifierVersion = 9 WHERE id = 'user-shot';
            UPDATE recognition SET state = 'partial' WHERE shotID = 'pending-shot';
            INSERT INTO folder (id, name, builtIn, position) VALUES ('\(UUID().uuidString)', '郵件', 'email', 99);
            INSERT INTO deletedBuiltIn (category) VALUES ('sticker');
            """)
        }

        let loaded = try XCTUnwrap(db.loadLibrary())
        XCTAssertEqual(loaded.shot("receipt-shot")?.featureTags, [.date])
        XCTAssertEqual(loaded.shot("receipt-shot")?.placement, .pending)
        XCTAssertEqual(loaded.shot("user-shot")?.placement, .pending)
        XCTAssertEqual(loaded.shot("pending-shot")?.recognition, .pending)
        XCTAssertEqual(loaded.folders.first { $0.name == "郵件" }?.builtIn, nil)
        XCTAssertEqual(loaded.deletedBuiltIns, [.recipe])
    }

    func testDatabaseThatCannotOpenThrowsInsteadOfSaving() {
        struct Locked: Error {}
        let store = SQLiteLibraryDatabase(opening: { throw Locked() })

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(Library(), changes: LibraryChanges()))
    }
}
