import GRDB
import ScreenshotKit

/// Turns a `Library` into rows and back. Callers provide the transaction.
enum LibraryRows {
    /// `nil` when nothing has been stored yet.
    static func read(from db: Database) throws -> Library? {
        let shots = try ShotRecord.fetchAll(db)
        let folders = try FolderRecord.order(Column("position")).fetchAll(db)
        let tags = try TagRecord.order(Column("position")).fetchAll(db)
        let hidden = try HiddenShotRecord.fetchAll(db)
        let deletedBuiltIns = try DeletedBuiltInRecord.fetchAll(db)
        guard !(shots.isEmpty && folders.isEmpty && tags.isEmpty && hidden.isEmpty && deletedBuiltIns.isEmpty) else { return nil }

        let recognitions = try Dictionary(uniqueKeysWithValues: RecognitionRecord.fetchAll(db).map { ($0.shotID, $0) })
        return Library(
            shots: shots.map { $0.shot(recognition: recognitions[$0.id]) },
            folders: folders.compactMap(\.folder),
            tags: tags.map(\.name),
            hiddenShotIDs: Set(hidden.map(\.id)),
            deletedBuiltIns: Set(deletedBuiltIns.compactMap { BuiltInCategory(rawValue: $0.category) })
        )
    }

    static func writeAll(_ library: Library, to db: Database) throws {
        let everything = LibraryChanges(
            upsertedShotIDs: library.shots.map(\.id),
            hasFolderChanges: true,
            hasTagChanges: true,
            hasHiddenChanges: true,
            hasDeletedBuiltInChanges: true
        )
        try write(library, changes: everything, to: db)
    }

    /// Writes only what `changes` names. Folders are upserted before screenshots that may point at
    /// them, and stale folders are removed only after no screenshot does.
    ///
    /// Folders are also upserted with any screenshot, even without folder changes: a loaded or empty
    /// `Library` adds its built-in folders in memory only, so a diff against it never names them.
    static func write(_ library: Library, changes: LibraryChanges, to db: Database) throws {
        if changes.hasFolderChanges || !changes.upsertedShotIDs.isEmpty { try upsertFolders(library.folders, db) }
        try ShotRecord.deleteAll(db, keys: changes.deletedShotIDs)
        try upsertShots(changes.upsertedShotIDs, of: library, db)
        if changes.hasFolderChanges { try deleteFolders(notIn: library.folders, db) }
        if changes.hasTagChanges { try replaceTags(library.tags, db) }
        if changes.hasHiddenChanges { try replace(HiddenShotRecord.self, with: library.hiddenShotIDs.map(HiddenShotRecord.init), db) }
        if changes.hasDeletedBuiltInChanges {
            try replace(DeletedBuiltInRecord.self, with: library.deletedBuiltIns.map { DeletedBuiltInRecord(category: $0.rawValue) }, db)
        }
    }

    private static func upsertFolders(_ folders: [Folder], _ db: Database) throws {
        for (position, folder) in folders.enumerated() {
            try FolderRecord(folder, position: position).upsert(db)
        }
    }

    private static func deleteFolders(notIn folders: [Folder], _ db: Database) throws {
        let kept = folders.map(\.id.uuidString)
        try FolderRecord.filter(!kept.contains(Column("id"))).deleteAll(db)
    }

    /// Upsert, not replace: replacing deletes the row first, which would cascade to its recognition.
    private static func upsertShots(_ ids: [String], of library: Library, _ db: Database) throws {
        guard !ids.isEmpty else { return }
        let shots = Dictionary(uniqueKeysWithValues: library.shots.map { ($0.id, $0) })
        for id in ids {
            guard let shot = shots[id] else { continue }
            try ShotRecord(shot).upsert(db)
            try RecognitionRecord(shot).upsert(db)
        }
    }

    private static func replaceTags(_ tags: [String], _ db: Database) throws {
        try replace(TagRecord.self, with: tags.enumerated().map { TagRecord(name: $1, position: $0) }, db)
    }

    private static func replace<Record: PersistableRecord>(_: Record.Type, with records: [Record], _ db: Database) throws {
        try Record.deleteAll(db)
        for record in records {
            try record.insert(db)
        }
    }
}
