import Foundation

/// What a backup says about screenshots found on this device, keyed by their current `localIdentifier`.
public struct BackupRestore: Equatable, Sendable {
    public var folders: [Folder]
    public var tags: [String]
    public var deletedBuiltIns: Set<BuiltInCategory>
    public var shots: [String: BackupShot]
    public var hiddenIDs: Set<String>

    public init(
        folders: [Folder] = [],
        tags: [String] = [],
        deletedBuiltIns: Set<BuiltInCategory> = [],
        shots: [String: BackupShot] = [:],
        hiddenIDs: Set<String> = []
    ) {
        self.folders = folders
        self.tags = tags
        self.deletedBuiltIns = deletedBuiltIns
        self.shots = shots
        self.hiddenIDs = hiddenIDs
    }

    public var isEmpty: Bool {
        shots.isEmpty && hiddenIDs.isEmpty
    }
}

/// Finds backed-up screenshots among the assets on this device.
public enum BackupMatcher {
    public struct Result: Equatable, Sendable {
        public var restore: BackupRestore
        /// The same snapshot with only the screenshots not found yet, to try again as Photos fills in.
        public var leftover: BackupSnapshot
    }

    /// Cloud identifier first; otherwise capture time and pixel size, used only when exactly one backed-up
    /// screenshot and exactly one asset share them. A wrong folder is worse than classifying again.
    /// - Parameter localIDsByCloudID: what `PHPhotoLibrary` resolved on this device.
    public static func match(
        _ snapshot: BackupSnapshot,
        assets: [AssetInfo],
        localIDsByCloudID: [String: String]
    ) -> Result {
        let keys = snapshot.shots.map(\.key) + snapshot.hiddenShots
        let byCloud = matchByCloudID(keys, assets: assets, localIDsByCloudID: localIDsByCloudID)
        let claimed = Set(byCloud.values)
        let byCapture = matchByCaptureKey(
            keys.filter { byCloud[$0] == nil },
            assets: assets.filter { !claimed.contains($0.id) }
        )
        let localID = byCloud.merging(byCapture) { cloud, _ in cloud }

        var restore = BackupRestore(folders: snapshot.folders, tags: snapshot.tags, deletedBuiltIns: snapshot.deletedBuiltIns)
        var leftover = snapshot
        leftover.shots = []
        leftover.hiddenShots = []
        for shot in snapshot.shots {
            if let id = localID[shot.key] { restore.shots[id] = shot } else { leftover.shots.append(shot) }
        }
        for key in snapshot.hiddenShots {
            if let id = localID[key] { restore.hiddenIDs.insert(id) } else { leftover.hiddenShots.append(key) }
        }
        return Result(restore: restore, leftover: leftover)
    }

    private static func matchByCloudID(
        _ keys: [BackupShotKey],
        assets: [AssetInfo],
        localIDsByCloudID: [String: String]
    ) -> [BackupShotKey: String] {
        let present = Set(assets.map(\.id))
        var matched: [BackupShotKey: String] = [:]
        var claimed: Set<String> = []
        for key in keys {
            guard let cloudID = key.cloudID, let id = localIDsByCloudID[cloudID],
                  present.contains(id), !claimed.contains(id) else { continue }
            matched[key] = id
            claimed.insert(id)
        }
        return matched
    }

    private static func matchByCaptureKey(_ keys: [BackupShotKey], assets: [AssetInfo]) -> [BackupShotKey: String] {
        let assetsByCapture = Dictionary(grouping: assets) {
            CaptureKey(createdAt: $0.createdAt, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight)
        }
        let keysByCapture = Dictionary(grouping: keys, by: \.captureKey)
        var matched: [BackupShotKey: String] = [:]
        for (capture, group) in keysByCapture {
            guard group.count == 1, let candidates = assetsByCapture[capture], candidates.count == 1 else { continue }
            matched[group[0]] = candidates[0].id
        }
        return matched
    }
}
