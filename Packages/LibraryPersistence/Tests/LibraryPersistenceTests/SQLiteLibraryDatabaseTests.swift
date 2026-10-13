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

    /// A fresh store starts from `Library()`, whose built-in folders exist only in memory, so the first
    /// save sees no folder changes. Placing a screenshot in one must still save.
    func testPlacingAShotInAnUnsavedBuiltInFolderSaves() throws {
        let db = try InMemoryLibrary()
        let empty = Library()
        var synced = empty
        synced.sync(with: [AssetInfo(id: "new-shot", createdAt: Date(), pixelWidth: 1170, pixelHeight: 2532)])
        try db.store.save(synced, changes: synced.changes(since: empty))

        let ticket = try XCTUnwrap(synced.folders.first { $0.builtIn != nil })
        var placed = synced
        placed.move(["new-shot"], to: ticket.id)
        try db.store.save(placed, changes: placed.changes(since: synced))

        let loaded = try XCTUnwrap(db.loadLibrary())
        XCTAssertEqual(loaded.shot("new-shot")?.folderID, ticket.id)
        XCTAssertEqual(loaded.folders, placed.folders)
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

    /// A database saved while 對話 was still a built-in category.
    func testRetiredChatFolderBecomesOrdinaryFolder() throws {
        let (db, library) = try savedFixture()
        let chat = try XCTUnwrap(library.folders.first { $0.name == "對話" })
        try db.queue.write { db in
            try db.execute(sql: """
            UPDATE folder SET builtIn = 'chat' WHERE id = '\(chat.id.uuidString)';
            UPDATE shot SET folderID = '\(chat.id.uuidString)' WHERE id = 'user-shot';
            INSERT INTO deletedBuiltIn (category) VALUES ('chat');
            """)
        }

        let loaded = try XCTUnwrap(db.loadLibrary())
        XCTAssertEqual(loaded.folders.filter { $0.name == "對話" }, [Folder(id: chat.id, name: "對話")])
        XCTAssertEqual(loaded.shot("user-shot")?.folderID, chat.id)
        XCTAssertFalse(loaded.deletedBuiltIns.contains { $0.rawValue == "chat" })
    }

    func testRefinementMarkRoundTrips() throws {
        let (db, library) = try savedFixture()
        var refined = library
        refined.applyClassification("pending-shot", verdict: nil, features: [], version: 3)
        refined.applyRefinement("pending-shot", verdict: nil)
        try db.store.save(refined, changes: LibraryChanges(upsertedShotIDs: ["pending-shot"]))

        XCTAssertEqual(try db.loadLibrary()?.shot("pending-shot")?.autoPlacement?.isRefined, true)
    }

    func testDatabaseFromBeforeRefinementGainsTheColumn() throws {
        let queue = try DatabaseQueue()
        _ = SQLiteLibraryDatabase(opening: { queue })
        let library = try fixtureLibrary()
        try SQLiteLibraryDatabase(opening: { queue }).save(library, changes: .everything(in: library))
        try queue.write { db in
            try db.execute(sql: """
            ALTER TABLE shot DROP COLUMN isRefined;
            DELETE FROM grdb_migrations WHERE identifier = 'v3-shot-is-refined';
            """)
        }

        let reopened = SQLiteLibraryDatabase(opening: { queue })
        guard case let .loaded(loaded) = try reopened.load() else { return XCTFail("expected rows") }
        XCTAssertEqual(loaded, library)
        XCTAssertTrue(loaded.shots.compactMap(\.autoPlacement).allSatisfy { !$0.isRefined })
    }

    func testDatabaseThatCannotOpenThrowsInsteadOfSaving() {
        struct Locked: Error {}
        let store = SQLiteLibraryDatabase(opening: { throw Locked() })

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(Library(), changes: LibraryChanges()))
    }
}
