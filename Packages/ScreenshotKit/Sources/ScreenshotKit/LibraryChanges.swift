import Foundation

/// What differs between two versions of a `Library`, so a store can write only what changed.
public struct LibraryChanges: Equatable, Sendable {
    /// Screenshots that are new or differ in any field, in the newer library's order.
    public var upsertedShotIDs: [String]
    public var deletedShotIDs: [String]
    public var hasFolderChanges: Bool
    public var hasTagChanges: Bool
    public var hasHiddenChanges: Bool
    public var hasDeletedBuiltInChanges: Bool

    public init(
        upsertedShotIDs: [String] = [],
        deletedShotIDs: [String] = [],
        hasFolderChanges: Bool = false,
        hasTagChanges: Bool = false,
        hasHiddenChanges: Bool = false,
        hasDeletedBuiltInChanges: Bool = false
    ) {
        self.upsertedShotIDs = upsertedShotIDs
        self.deletedShotIDs = deletedShotIDs
        self.hasFolderChanges = hasFolderChanges
        self.hasTagChanges = hasTagChanges
        self.hasHiddenChanges = hasHiddenChanges
        self.hasDeletedBuiltInChanges = hasDeletedBuiltInChanges
    }

    public var isEmpty: Bool {
        self == LibraryChanges()
    }
}

public extension Library {
    func changes(since old: Library) -> LibraryChanges {
        let (upserted, deleted) = shotChanges(since: old)
        return LibraryChanges(
            upsertedShotIDs: upserted,
            deletedShotIDs: deleted,
            hasFolderChanges: folders != old.folders,
            hasTagChanges: tags != old.tags,
            hasHiddenChanges: hiddenShotIDs != old.hiddenShotIDs,
            hasDeletedBuiltInChanges: deletedBuiltIns != old.deletedBuiltIns
        )
    }

    private func shotChanges(since old: Library) -> (upserted: [String], deleted: [String]) {
        let oldShots = Dictionary(uniqueKeysWithValues: old.shots.map { ($0.id, $0) })
        let upserted = shots.filter { oldShots[$0.id] != $0 }.map(\.id)
        let current = Set(shots.map(\.id))
        let deleted = old.shots.map(\.id).filter { !current.contains($0) }
        return (upserted, deleted)
    }
}
