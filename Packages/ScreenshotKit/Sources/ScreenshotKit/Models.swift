import Foundation

/// A rectangle in unit coordinates (0…1) with a top-left origin, relative to the screenshot.
public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxY: Double {
        y + height
    }
}

/// One recognized line of text and where it sits on the screenshot.
public struct TextBlock: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var text: String
    public var box: NormalizedRect

    public init(id: Int, text: String, box: NormalizedRect) {
        self.id = id
        self.text = text
        self.box = box
    }
}

public enum RecognitionState: String, Codable, Sendable {
    case pending
    case done
    case failed
}

/// A screenshot from the Photos library, plus everything the app layers on top of it.
/// The photo itself is never modified; `id` is the `PHAsset.localIdentifier`.
public struct Shot: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var createdAt: Date
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// A screenshot lives in at most one folder; `nil` means 未分類 (or 處理中 while `placement` is pending).
    public var folderID: UUID?
    public var placement: Placement
    /// Tags the user added.
    public var tags: [String]
    /// Tags the app added from what it detected, minus the ones the user removed.
    public var featureTags: Set<FeatureTag>
    /// Feature tags the user removed; never added back.
    public var dismissedFeatureTags: Set<FeatureTag>
    public var blocks: [TextBlock]
    /// Payloads of QR codes and barcodes found on the screenshot.
    public var barcodes: [String]
    public var recognition: RecognitionState
    public var recognitionAttempts: Int

    public init(
        id: String,
        createdAt: Date,
        pixelWidth: Int,
        pixelHeight: Int,
        folderID: UUID? = nil,
        placement: Placement = .pending,
        tags: [String] = [],
        featureTags: Set<FeatureTag> = [],
        dismissedFeatureTags: Set<FeatureTag> = [],
        blocks: [TextBlock] = [],
        barcodes: [String] = [],
        recognition: RecognitionState = .pending,
        recognitionAttempts: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.folderID = folderID
        self.placement = placement
        self.tags = tags
        self.featureTags = featureTags
        self.dismissedFeatureTags = dismissedFeatureTags
        self.blocks = blocks
        self.barcodes = barcodes
        self.recognition = recognition
        self.recognitionAttempts = recognitionAttempts
    }

    /// Failed recognitions are retried up to this many times before the screenshot is treated as textless.
    public static let maxRecognitionAttempts = 3

    /// Shown under 處理中 until a classifier pass places it.
    public var isProcessing: Bool {
        placement == .pending
    }

    /// The app looked at it and found no folder, or the user put it in 未分類.
    public var isUnsorted: Bool {
        folderID == nil && !isProcessing
    }

    public var needsRecognition: Bool {
        switch recognition {
        case .pending: return true
        case .failed: return recognitionAttempts < Shot.maxRecognitionAttempts
        case .done: return false
        }
    }

    /// Set when the app placed it, `nil` for user placements and pending ones.
    public var autoPlacement: AutoPlacement? {
        if case let .auto(auto) = placement { return auto }
        return nil
    }

    public static let fallbackTitle = "螢幕截圖"

    /// The first substantial line of text, used as the screenshot's heading.
    public var title: String {
        let line = blocks.lazy
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.count >= 2 && !Shot.looksLikeClock($0) }
        guard let line else { return Shot.fallbackTitle }
        return line.count > 24 ? String(line.prefix(24)) + "…" : line
    }

    public var allText: String {
        blocks.map(\.text).joined(separator: "\n")
    }

    public var aspectRatio: Double {
        guard pixelWidth > 0, pixelHeight > 0 else { return 300.0 / 650.0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    /// e.g. "繁體中文 / 英文"; empty when nothing was recognized.
    public var languageSummary: String {
        let text = allText
        var parts: [String] = []
        if text.unicodeScalars.contains(where: Shot.isCJK) { parts.append("繁體中文") }
        if text.unicodeScalars.contains(where: { ("a" ... "z").contains($0) || ("A" ... "Z").contains($0) }) { parts.append("英文") }
        return parts.joined(separator: " / ")
    }

    static func isCJK(_ s: Unicode.Scalar) -> Bool {
        (0x4E00 ... 0x9FFF).contains(s.value) || (0x3400 ... 0x4DBF).contains(s.value)
    }

    static func looksLikeClock(_ s: String) -> Bool {
        s.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
    }
}

extension Shot {
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, pixelWidth, pixelHeight, folderID, placement, tags, featureTags, dismissedFeatureTags
        case blocks, barcodes, recognition, recognitionAttempts
    }

    /// Only the Photos identity is required. Everything else falls back to its default, so a file
    /// written before a field existed still loads; the screenshot is then processed again if needed.
    /// Enum values this version does not know are dropped or reset the same way.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            createdAt: c.decode(Date.self, forKey: .createdAt),
            pixelWidth: c.decode(Int.self, forKey: .pixelWidth),
            pixelHeight: c.decode(Int.self, forKey: .pixelHeight),
            folderID: c.decodeIfPresent(UUID.self, forKey: .folderID),
            // An unknown case or classifier source sends the screenshot back through classification.
            placement: (try? c.decodeIfPresent(Placement.self, forKey: .placement)) ?? .pending,
            tags: c.decodeIfPresent([String].self, forKey: .tags) ?? [],
            featureTags: c.decodeKnownValues(FeatureTag.self, forKey: .featureTags),
            dismissedFeatureTags: c.decodeKnownValues(FeatureTag.self, forKey: .dismissedFeatureTags),
            blocks: c.decodeIfPresent([TextBlock].self, forKey: .blocks) ?? [],
            barcodes: c.decodeIfPresent([String].self, forKey: .barcodes) ?? [],
            recognition: c.decodeKnownValue(RecognitionState.self, forKey: .recognition) ?? .pending,
            recognitionAttempts: c.decodeIfPresent(Int.self, forKey: .recognitionAttempts) ?? 0
        )
    }
}

public struct Folder: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    /// Set for folders the app created for a built-in category.
    public let builtIn: BuiltInCategory?

    public init(id: UUID = UUID(), name: String, builtIn: BuiltInCategory? = nil) {
        self.id = id
        self.name = name
        self.builtIn = builtIn
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, builtIn
    }

    /// A built-in category this version does not know turns the folder into an ordinary one,
    /// keeping its name and screenshots.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(UUID.self, forKey: .id),
            name: c.decode(String.self, forKey: .name),
            builtIn: c.decodeKnownValue(BuiltInCategory.self, forKey: .builtIn)
        )
    }
}

/// What the Photos library reports for one screenshot asset.
public struct AssetInfo: Hashable, Sendable {
    public var id: String
    public var createdAt: Date
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(id: String, createdAt: Date, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.createdAt = createdAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public enum TextBlockFilter {
    /// Vision reads the status bar (clock, carrier, battery) on every screenshot.
    /// Lines that sit entirely inside the top strip are noise for copying and search.
    public static let statusBarHeight = 0.055

    public static func droppingStatusBar(_ blocks: [TextBlock]) -> [TextBlock] {
        blocks
            .filter { $0.box.maxY > statusBarHeight }
            .enumerated()
            .map { TextBlock(id: $0.offset, text: $0.element.text, box: $0.element.box) }
    }
}
