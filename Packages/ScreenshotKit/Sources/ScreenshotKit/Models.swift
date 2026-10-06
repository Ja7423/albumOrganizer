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

    public var maxY: Double { y + height }
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
    /// A screenshot lives in at most one folder; `nil` means 未分類.
    public var folderID: UUID?
    public var tags: [String]
    /// Tags proposed from the recognized text, waiting for the user to confirm.
    public var suggestions: [String]
    public var blocks: [TextBlock]
    public var recognition: RecognitionState

    public init(
        id: String,
        createdAt: Date,
        pixelWidth: Int,
        pixelHeight: Int,
        folderID: UUID? = nil,
        tags: [String] = [],
        suggestions: [String] = [],
        blocks: [TextBlock] = [],
        recognition: RecognitionState = .pending
    ) {
        self.id = id
        self.createdAt = createdAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.folderID = folderID
        self.tags = tags
        self.suggestions = suggestions
        self.blocks = blocks
        self.recognition = recognition
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
        if text.unicodeScalars.contains(where: { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }) { parts.append("英文") }
        return parts.joined(separator: " / ")
    }

    static func isCJK(_ s: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
    }

    static func looksLikeClock(_ s: String) -> Bool {
        s.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
    }
}

public struct Folder: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
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
