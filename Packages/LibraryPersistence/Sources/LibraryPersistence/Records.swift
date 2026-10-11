import Foundation
import GRDB
import ScreenshotKit

// One record per table. Conversions to and from the domain types are pure; values this version
// does not know are dropped or reset the same way `LibraryCodec` does for JSON.

struct FolderRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "folder"

    var id: String
    var name: String
    var builtIn: String?
    var position: Int

    init(_ folder: Folder, position: Int) {
        id = folder.id.uuidString
        name = folder.name
        builtIn = folder.builtIn?.rawValue
        self.position = position
    }

    /// `nil` when the stored id is not a UUID.
    var folder: Folder? {
        UUID(uuidString: id).map { Folder(id: $0, name: name, builtIn: builtIn.flatMap(BuiltInCategory.init(rawValue:))) }
    }
}

struct TagRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tag"

    var name: String
    var position: Int
}

struct HiddenShotRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "hiddenShot"

    var id: String
}

struct DeletedBuiltInRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "deletedBuiltIn"

    var category: String
}

/// What the user decided about a screenshot. Never thrown away to be recomputed.
struct ShotRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "shot"

    enum PlacementKind: String, Codable {
        case pending, auto, user
    }

    var id: String
    /// Seconds since 2001-01-01, like the JSON file. GRDB's default `Date` text keeps only milliseconds.
    var createdAt: Double
    var pixelWidth: Int
    var pixelHeight: Int
    var folderID: String?
    var placement: String
    var autoSource: String?
    var classifierVersion: Int?
    // Stored as JSON text by GRDB.
    var tags: [String]
    var featureTags: [String]
    var dismissedFeatureTags: [String]

    init(_ shot: Shot) {
        id = shot.id
        createdAt = shot.createdAt.timeIntervalSinceReferenceDate
        pixelWidth = shot.pixelWidth
        pixelHeight = shot.pixelHeight
        folderID = shot.folderID?.uuidString
        switch shot.placement {
        case .pending:
            placement = PlacementKind.pending.rawValue
        case let .auto(auto):
            placement = PlacementKind.auto.rawValue
            autoSource = auto.source?.rawValue
            classifierVersion = auto.classifierVersion
        case .user:
            placement = PlacementKind.user.rawValue
        }
        tags = shot.tags
        featureTags = shot.featureTags.map(\.rawValue).sorted()
        dismissedFeatureTags = shot.dismissedFeatureTags.map(\.rawValue).sorted()
    }

    /// Anything unrecognized sends the screenshot back through classification.
    var decodedPlacement: Placement {
        switch PlacementKind(rawValue: placement) {
        case .user:
            return .user
        case .auto:
            guard let classifierVersion else { return .pending }
            guard let autoSource else { return .auto(AutoPlacement(source: nil, classifierVersion: classifierVersion)) }
            guard let source = ClassifierSource(rawValue: autoSource) else { return .pending }
            return .auto(AutoPlacement(source: source, classifierVersion: classifierVersion))
        case .pending, nil:
            return .pending
        }
    }

    func shot(recognition: RecognitionRecord?) -> Shot {
        Shot(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: createdAt),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            folderID: folderID.flatMap(UUID.init(uuidString:)),
            placement: decodedPlacement,
            tags: tags,
            featureTags: Set(featureTags.compactMap(FeatureTag.init(rawValue:))),
            dismissedFeatureTags: Set(dismissedFeatureTags.compactMap(FeatureTag.init(rawValue:))),
            blocks: recognition?.blocks ?? [],
            barcodes: recognition?.barcodes ?? [],
            recognition: recognition.flatMap { RecognitionState(rawValue: $0.state) } ?? .pending,
            recognitionAttempts: recognition?.attempts ?? 0
        )
    }
}

/// What text recognition found. Derived data: safe to delete, the screenshot is then recognized again.
struct RecognitionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "recognition"

    var shotID: String
    var state: String
    var attempts: Int
    // Stored as JSON text by GRDB.
    var blocks: [TextBlock]
    var barcodes: [String]

    init(_ shot: Shot) {
        shotID = shot.id
        state = shot.recognition.rawValue
        attempts = shot.recognitionAttempts
        blocks = shot.blocks
        barcodes = shot.barcodes
    }
}
