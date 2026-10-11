import Foundation
import GRDB
@testable import LibraryPersistence
import ScreenshotKit
import XCTest

extension XCTestCase {
    /// `library-v0.json`, written by the app before `schemaVersion` existed.
    func fixtureURL() throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "library-v0", withExtension: "json"))
    }

    func fixtureLibrary() throws -> Library {
        try LibraryCodec.decode(Data(contentsOf: fixtureURL()))
    }

    /// An empty directory removed after the test.
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func fileNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }
}

/// An in-memory database plus direct access to it, for checking rows.
struct InMemoryLibrary {
    let queue: DatabaseQueue
    let store: SQLiteLibraryDatabase

    init() throws {
        let queue = try DatabaseQueue()
        self.queue = queue
        store = SQLiteLibraryDatabase(opening: { queue })
    }

    func loadLibrary() throws -> Library? {
        guard case let .loaded(library) = try store.load() else { return nil }
        return library
    }

    func count(_ table: String) throws -> Int {
        try queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
    }
}

extension LibraryChanges {
    /// Every row of `library`, for writing it from scratch.
    static func everything(in library: Library) -> LibraryChanges {
        LibraryChanges(
            upsertedShotIDs: library.shots.map(\.id),
            hasFolderChanges: true,
            hasTagChanges: true,
            hasHiddenChanges: true,
            hasDeletedBuiltInChanges: true
        )
    }
}
