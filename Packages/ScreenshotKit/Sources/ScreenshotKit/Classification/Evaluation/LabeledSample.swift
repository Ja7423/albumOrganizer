import Foundation

/// One screenshot with its right answer, as in `labeled-ocr.json` or a set exported from the app's database.
public struct LabeledSample: Codable, Hashable, Sendable {
    /// Where the sample came from, e.g. the `PHAsset.localIdentifier`. Only for reading reports.
    public var id: String?
    /// `nil` means the right answer is 未分類.
    public var expected: BuiltInCategory?
    public var text: String
    /// `"chat"` lays synthetic lines out as alternating bubbles. Ignored when `blocks` is set.
    public var layout: String?
    /// Number of barcodes on screen.
    public var barcodes: Int?
    /// Recognized blocks with their real positions. Synthetic samples leave this out.
    public var blocks: [TextBlock]?

    public init(
        id: String? = nil,
        expected: BuiltInCategory?,
        text: String,
        layout: String? = nil,
        barcodes: Int? = nil,
        blocks: [TextBlock]? = nil
    ) {
        self.id = id
        self.expected = expected
        self.text = text
        self.layout = layout
        self.barcodes = barcodes
        self.blocks = blocks
    }

    /// What a classifier layer sees for this sample, with no category excluded.
    public var classifierInput: ClassifierInput {
        classifierInput(excluding: [])
    }

    /// What a classifier layer sees for this sample in a library where `excluded` were deleted.
    public func classifierInput(excluding excluded: Set<ClassificationTarget>) -> ClassifierInput {
        let payloads = Array(repeating: "payload", count: barcodes ?? 0)
        let signals = SignalExtractor.extract(blocks: blocks ?? syntheticBlocks, barcodes: payloads)
        return ClassifierInput(text: text, signals: signals, excluded: excluded)
    }

    /// One block per line, top to bottom; chat lines alternate between the left and right edges.
    private var syntheticBlocks: [TextBlock] {
        let isChat = layout == "chat"
        return text.split(separator: "\n").enumerated().map { index, line in
            let isRight = isChat && !index.isMultiple(of: 2)
            let box = NormalizedRect(x: isRight ? 0.5 : 0.05, y: 0.1 + Double(index) * 0.05, width: isChat ? 0.42 : 0.9, height: 0.02)
            return TextBlock(id: index, text: String(line), box: box)
        }
    }
}
