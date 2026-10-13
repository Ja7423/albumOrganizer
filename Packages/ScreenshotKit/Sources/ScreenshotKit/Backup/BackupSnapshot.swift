import Foundation

/// How a backed-up screenshot is found again, on this device or on another one.
public struct BackupShotKey: Codable, Hashable, Sendable {
    /// `PHAsset.localIdentifier` on the device that made the backup.
    public var localID: String
    /// `PHCloudIdentifier.stringValue`; `nil` when iCloud Photos was off.
    public var cloudID: String?
    public var createdAt: Date
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(localID: String, cloudID: String?, createdAt: Date, pixelWidth: Int, pixelHeight: Int) {
        self.localID = localID
        self.cloudID = cloudID
        self.createdAt = createdAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// Capture time to the second plus pixel size: the fallback when no cloud identifier resolves.
    var captureKey: CaptureKey {
        CaptureKey(createdAt: createdAt, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }
}

struct CaptureKey: Hashable {
    var second: Int
    var pixelWidth: Int
    var pixelHeight: Int

    init(createdAt: Date, pixelWidth: Int, pixelHeight: Int) {
        second = Int(createdAt.timeIntervalSinceReferenceDate.rounded())
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// What the user decided about one screenshot. No recognized text: that is recomputed on the device.
public struct BackupShot: Codable, Hashable, Sendable {
    public var key: BackupShotKey
    public var folderID: UUID?
    public var placement: Placement
    public var tags: [String]
    public var featureTags: Set<FeatureTag>
    public var dismissedFeatureTags: Set<FeatureTag>

    public init(
        key: BackupShotKey,
        folderID: UUID?,
        placement: Placement,
        tags: [String] = [],
        featureTags: Set<FeatureTag> = [],
        dismissedFeatureTags: Set<FeatureTag> = []
    ) {
        self.key = key
        self.folderID = folderID
        self.placement = placement
        self.tags = tags
        self.featureTags = featureTags
        self.dismissedFeatureTags = dismissedFeatureTags
    }

    private enum CodingKeys: String, CodingKey {
        case key, folderID, placement, tags, featureTags, dismissedFeatureTags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            key: c.decode(BackupShotKey.self, forKey: .key),
            folderID: c.decodeIfPresent(UUID.self, forKey: .folderID),
            placement: c.decodeIfPresent(Placement.self, forKey: .placement) ?? .pending,
            tags: c.decodeIfPresent([String].self, forKey: .tags) ?? [],
            featureTags: c.decodeKnownValues(FeatureTag.self, forKey: .featureTags),
            dismissedFeatureTags: c.decodeKnownValues(FeatureTag.self, forKey: .dismissedFeatureTags)
        )
    }
}

/// Everything a backup holds: the user's organization of the library, without anything the device can recompute.
public struct BackupSnapshot: Codable, Hashable, Sendable {
    public var createdAt: Date
    public var folders: [Folder]
    public var tags: [String]
    public var deletedBuiltIns: Set<BuiltInCategory>
    public var shots: [BackupShot]
    public var hiddenShots: [BackupShotKey]

    public init(
        createdAt: Date,
        folders: [Folder] = [],
        tags: [String] = [],
        deletedBuiltIns: Set<BuiltInCategory> = [],
        shots: [BackupShot] = [],
        hiddenShots: [BackupShotKey] = []
    ) {
        self.createdAt = createdAt
        self.folders = folders
        self.tags = tags
        self.deletedBuiltIns = deletedBuiltIns
        self.shots = shots
        self.hiddenShots = hiddenShots
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, createdAt, folders, tags, deletedBuiltIns, shots, hiddenShots
    }

    /// Use `BackupCodec` rather than decoding directly: it also refuses snapshots from a newer schema.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            createdAt: c.decode(Date.self, forKey: .createdAt),
            folders: c.decodeIfPresent([Folder].self, forKey: .folders) ?? [],
            tags: c.decodeIfPresent([String].self, forKey: .tags) ?? [],
            deletedBuiltIns: c.decodeKnownValues(BuiltInCategory.self, forKey: .deletedBuiltIns),
            shots: c.decodeIfPresent([BackupShot].self, forKey: .shots) ?? [],
            hiddenShots: c.decodeIfPresent([BackupShotKey].self, forKey: .hiddenShots) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(BackupCodec.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(folders, forKey: .folders)
        try c.encode(tags, forKey: .tags)
        try c.encode(deletedBuiltIns, forKey: .deletedBuiltIns)
        try c.encode(shots, forKey: .shots)
        try c.encode(hiddenShots, forKey: .hiddenShots)
    }

    /// Nothing left to find on this device.
    public var hasNoScreenshots: Bool {
        shots.isEmpty && hiddenShots.isEmpty
    }
}
