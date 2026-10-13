import Foundation

public extension Library {
    /// The library as a backup. Screenshots still in 處理中 have nothing to keep yet and are left out;
    /// `pending` is carried over so screenshots not yet found on this device survive the next backup.
    /// - Parameters:
    ///   - cloudIDsByLocalID: what `PHPhotoLibrary` resolved for the library's screenshots.
    ///   - hiddenAssets: Photos' details for `hiddenShotIDs`; hidden photos no longer in Photos are dropped.
    func backupSnapshot(
        createdAt: Date,
        cloudIDsByLocalID: [String: String],
        hiddenAssets: [AssetInfo],
        pending: BackupSnapshot? = nil
    ) -> BackupSnapshot {
        let shots = shots.filter { !$0.isProcessing }.map { shot in
            BackupShot(
                key: BackupShotKey(
                    localID: shot.id,
                    cloudID: cloudIDsByLocalID[shot.id],
                    createdAt: shot.createdAt,
                    pixelWidth: shot.pixelWidth,
                    pixelHeight: shot.pixelHeight
                ),
                folderID: shot.folderID,
                placement: shot.placement,
                tags: shot.tags,
                featureTags: shot.featureTags,
                dismissedFeatureTags: shot.dismissedFeatureTags
            )
        }
        let hidden = hiddenAssets.filter { hiddenShotIDs.contains($0.id) }.map { asset in
            BackupShotKey(
                localID: asset.id,
                cloudID: cloudIDsByLocalID[asset.id],
                createdAt: asset.createdAt,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight
            )
        }
        return BackupSnapshot(
            createdAt: createdAt,
            folders: folders,
            tags: tags,
            deletedBuiltIns: deletedBuiltIns,
            shots: shots + (pending?.shots ?? []),
            hiddenShots: hidden + (pending?.hiddenShots ?? [])
        )
    }

    /// Lays a backup over this library. Run it after `sync(with:)`, so every matched screenshot is already here.
    ///
    /// - A screenshot the user placed on this device keeps its place; otherwise the backup's placement wins.
    /// - Folders match by id, then built-ins by category, then other folders by name. A built-in deleted on
    ///   this device stays deleted; a built-in the backup deleted is deleted here only if its folder is empty.
    /// - Tags and dismissed automatic tags are unioned.
    /// - Parameter mergingFolders: `false` when matching leftovers later: folders and deletions the user changed
    ///   since the restore are left alone, and a screenshot whose folder is gone keeps its place here.
    func restoring(_ restore: BackupRestore, mergingFolders: Bool) -> Library {
        var folders = folders
        let folderIDs = mappedFolderIDs(restore.folders, appendingTo: &folders, appendsMissing: mergingFolders)
        var shots = shots.filter { !restore.hiddenIDs.contains($0.id) }
        for index in shots.indices {
            guard let backup = restore.shots[shots[index].id] else { continue }
            shots[index] = Self.overlaid(shots[index], with: backup, folderIDs: folderIDs)
        }
        var tags = tags
        let backupTags = (mergingFolders ? restore.tags : []) + shots.flatMap(\.tags)
        for tag in backupTags where !tags.contains(tag) {
            tags.append(tag)
        }
        var deletedBuiltIns = deletedBuiltIns
        if mergingFolders {
            let emptied = Self.deletableBuiltIns(restore.deletedBuiltIns, folders: folders, shots: shots)
            folders.removeAll { $0.builtIn.map(emptied.contains) ?? false }
            deletedBuiltIns.formUnion(emptied)
        }
        return Library(
            shots: shots,
            folders: folders,
            tags: tags,
            hiddenShotIDs: hiddenShotIDs.union(restore.hiddenIDs),
            deletedBuiltIns: deletedBuiltIns
        )
    }

    /// Backup folder id → this library's folder id. Folders that match nothing are appended when `appendsMissing`.
    private func mappedFolderIDs(_ backupFolders: [Folder], appendingTo folders: inout [Folder], appendsMissing: Bool) -> [UUID: UUID] {
        var mapped: [UUID: UUID] = [:]
        for folder in backupFolders {
            if let local = folders.first(where: { $0.id == folder.id }) {
                mapped[folder.id] = local.id
            } else if let category = folder.builtIn {
                guard let local = folders.first(where: { $0.builtIn == category }) else { continue }
                mapped[folder.id] = local.id
            } else if let local = folders.first(where: { $0.builtIn == nil && $0.name == folder.name }) {
                mapped[folder.id] = local.id
            } else if appendsMissing {
                folders.append(folder)
                mapped[folder.id] = folder.id
            }
        }
        return mapped
    }

    /// A `nil` backup folder is 未分類; a folder that maps to nothing here (`.some(nil)`) leaves the screenshot as it is.
    private static func overlaid(_ shot: Shot, with backup: BackupShot, folderIDs: [UUID: UUID]) -> Shot {
        var shot = shot
        shot.dismissedFeatureTags.formUnion(backup.dismissedFeatureTags)
        for tag in backup.tags where !shot.tags.contains(tag) {
            shot.tags.append(tag)
        }
        let folderID = backup.folderID.map { folderIDs[$0] }
        let canPlace = shot.placement != .user && backup.placement != .pending && folderID != .some(nil)
        if canPlace {
            shot.folderID = folderID ?? nil
            shot.placement = backup.placement
            shot.featureTags = backup.featureTags
        }
        shot.featureTags.subtract(shot.dismissedFeatureTags)
        return shot
    }

    /// Built-ins the backup deleted whose folder here holds nothing, so deleting them loses nothing.
    private static func deletableBuiltIns(_ deleted: Set<BuiltInCategory>, folders: [Folder], shots: [Shot]) -> Set<BuiltInCategory> {
        let occupied = Set(shots.compactMap(\.folderID))
        return deleted.filter { category in
            guard let folder = folders.first(where: { $0.builtIn == category }) else { return true }
            return !occupied.contains(folder.id)
        }
    }
}
