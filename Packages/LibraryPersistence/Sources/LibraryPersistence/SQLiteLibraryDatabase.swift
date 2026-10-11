import Foundation
import GRDB
import ScreenshotKit

/// The `Library` in SQLite. Saves write only the rows `LibraryChanges` names, each save in one transaction.
public final class SQLiteLibraryDatabase: LibraryPersisting {
    /// Opening errors are kept and thrown from `load()`, so a database that cannot be opened
    /// (e.g. the device is still locked) turns saving off for the session instead of crashing.
    private let database: Result<any DatabaseWriter, any Error>

    /// Opens or creates the database and migrates it. A `library.json` at `legacyJSONURL` is imported
    /// once, then renamed to `library.imported.json`.
    public convenience init(databaseURL: URL, legacyJSONURL: URL?) {
        self.init(opening: { try DatabasePool(path: databaseURL.path) }, legacyJSONURL: legacyJSONURL)
    }

    init(opening open: () throws -> any DatabaseWriter, legacyJSONURL: URL? = nil) {
        database = Result {
            let writer = try open()
            try Self.migrate(writer, legacyJSONURL: legacyJSONURL)
            return writer
        }
    }

    public func load() throws -> LibraryLoadResult {
        let library = try database.get().read { db in try LibraryRows.read(from: db) }
        return library.map(LibraryLoadResult.loaded) ?? .empty
    }

    public func save(_ library: Library, changes: LibraryChanges) throws {
        try database.get().write { db in try LibraryRows.write(library, changes: changes, to: db) }
    }

    private static func migrate(_ writer: any DatabaseWriter, legacyJSONURL: URL?) throws {
        let migrator = LibraryMigrator.migrator(legacyJSON: legacyJSONURL.map { JSONLibraryFile(fileURL: $0) })
        let importedBefore = try writer.read { db in
            try migrator.appliedIdentifiers(db).contains(LibraryMigrator.importLegacyJSONIdentifier)
        }
        try migrator.migrate(writer)
        if !importedBefore, let legacyJSONURL {
            retire(legacyJSONURL)
        }
    }

    /// Keeps the imported file next to the database instead of deleting it.
    private static func retire(_ legacyJSONURL: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: legacyJSONURL.path) else { return }
        let imported = legacyJSONURL.deletingPathExtension().appendingPathExtension("imported.json")
        guard !manager.fileExists(atPath: imported.path) else { return }
        try? manager.moveItem(at: legacyJSONURL, to: imported)
    }
}
