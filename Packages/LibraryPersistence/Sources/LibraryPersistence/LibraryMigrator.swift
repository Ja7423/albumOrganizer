import Foundation
import GRDB
import os
import ScreenshotKit

/// Every schema change, in order. Each migration runs in its own transaction: if one fails, the
/// database stays as it was and the migration is tried again on the next launch.
/// Never edit a migration that has shipped; add a new one.
enum LibraryMigrator {
    static let importLegacyJSONIdentifier = "v2-import-legacy-json"

    /// `legacyJSON` is the `library.json` the app used before SQLite; imported once if present.
    static func migrator(legacyJSON: JSONLibraryFile?) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-schema", migrate: createSchema)
        migrator.registerMigration(importLegacyJSONIdentifier) { db in
            try importLegacyJSON(legacyJSON, into: db)
        }
        return migrator
    }

    private static func createSchema(_ db: Database) throws {
        // User data: what the user decided. Must survive every migration.
        try db.create(table: "folder") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()
            t.column("builtIn", .text)
            t.column("position", .integer).notNull()
        }
        try db.create(table: "tag") { t in
            t.primaryKey("name", .text)
            t.column("position", .integer).notNull()
        }
        try db.create(table: "shot") { t in
            t.primaryKey("id", .text)
            t.column("createdAt", .double).notNull()
            t.column("pixelWidth", .integer).notNull()
            t.column("pixelHeight", .integer).notNull()
            t.column("folderID", .text).references("folder", onDelete: .setNull)
            t.column("placement", .text).notNull()
            t.column("autoSource", .text)
            t.column("classifierVersion", .integer)
            t.column("tags", .text).notNull()
            t.column("featureTags", .text).notNull()
            t.column("dismissedFeatureTags", .text).notNull()
        }
        try db.create(table: "hiddenShot") { t in
            t.primaryKey("id", .text)
        }
        try db.create(table: "deletedBuiltIn") { t in
            t.primaryKey("category", .text)
        }

        // Derived data: can be deleted and recomputed.
        try db.create(table: "recognition") { t in
            t.primaryKey("shotID", .text).references("shot", onDelete: .cascade)
            t.column("state", .text).notNull()
            t.column("attempts", .integer).notNull()
            t.column("blocks", .text).notNull()
            t.column("barcodes", .text).notNull()
        }
    }

    private static func importLegacyJSON(_ file: JSONLibraryFile?, into db: Database) throws {
        // Throws when the file exists but cannot be read yet; the migration then runs again next launch.
        switch try file?.load() {
        case let .loaded(library):
            try LibraryRows.writeAll(library, to: db)
        case let .unreadable(backupURL, reason):
            Logger.persistence.error("library.json unreadable, moved aside to \(backupURL.lastPathComponent, privacy: .public) instead of importing: \(reason, privacy: .public)")
        case .empty, nil:
            break
        }
    }
}
