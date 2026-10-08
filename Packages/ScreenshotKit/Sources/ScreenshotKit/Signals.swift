import Foundation

/// Cheap structural facts about a screenshot, computed from its recognized text, layout and barcodes.
/// Both the rule classifier and the feature tags read these.
public struct ScreenshotSignals: Hashable, Sendable {
    public var links: Int
    public var phones: Int
    public var dates: Int
    public var addresses: Int
    public var barcodes: Int
    /// Lines hug the left and right edges in turn, like chat bubbles.
    public var hasAlternatingBubbles: Bool
    /// Share of non-space characters that are code punctuation.
    public var symbolDensity: Double

    public init(
        links: Int = 0,
        phones: Int = 0,
        dates: Int = 0,
        addresses: Int = 0,
        barcodes: Int = 0,
        hasAlternatingBubbles: Bool = false,
        symbolDensity: Double = 0
    ) {
        self.links = links
        self.phones = phones
        self.dates = dates
        self.addresses = addresses
        self.barcodes = barcodes
        self.hasAlternatingBubbles = hasAlternatingBubbles
        self.symbolDensity = symbolDensity
    }
}

public enum SignalExtractor {
    static let linkPatterns = [#"https?://\S+"#, #"\b[\w-]+\.(com|tw|org|io|net|dev|app)(/\S*)?\b"#]
    static let addressPatterns = [#"[市縣].{0,6}[區鄉鎮市].{0,14}[路街道巷].{0,12}\d+\s*號"#]
    static let phonePatterns = [#"\b09\d{2}-?\d{3}-?\d{3}\b"#, #"\(?\b0\d{1,2}\)?[\s-]?\d{3,4}-?\d{4}\b"#, #"\+886[\s-]?\d{1,2}[\s-]?\d{3,4}[\s-]?\d{3,4}"#]
    static let datePatterns = [#"\d{4}\s*[/.-]\s*\d{1,2}\s*[/.-]\s*\d{1,2}"#, #"\d{1,2}\s*月\s*\d{1,2}\s*[日號]"#]
    static let codeSymbols = Set("{}()[];=<>")

    public static func extract(blocks: [TextBlock], barcodes: [String]) -> ScreenshotSignals {
        let text = blocks.map(\.text).joined(separator: "\n")
        let detected = detectorMatches(in: text)
        return ScreenshotSignals(
            links: max(detected.count(of: .link), matchCount(linkPatterns, in: text)),
            // NSDataDetector reads any 8-digit number as a phone and 「今天」 as a date; only explicit formats count.
            phones: matchCount(phonePatterns, in: text),
            dates: matchCount(datePatterns, in: text),
            addresses: max(detected.count(of: .address), matchCount(addressPatterns, in: text)),
            barcodes: barcodes.count,
            hasAlternatingBubbles: hasAlternatingBubbles(blocks),
            symbolDensity: symbolDensity(text)
        )
    }

    static func matchCount(_ patterns: [String], in text: String) -> Int {
        patterns.reduce(0) { total, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return total }
            return total + regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        }
    }

    static func detectorMatches(in text: String) -> [NSTextCheckingResult] {
        let types: NSTextCheckingResult.CheckingType = [.link, .address]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Chat screens put incoming lines on the left and outgoing ones on the right.
    static func hasAlternatingBubbles(_ blocks: [TextBlock]) -> Bool {
        let sides = blocks.compactMap(bubbleSide)
        let switches = zip(sides, sides.dropFirst()).filter { $0 != $1 }.count
        let left = sides.filter { $0 == .left }.count
        return left >= 2 && sides.count - left >= 2 && switches >= 3
    }

    private enum BubbleSide { case left, right }

    private static func bubbleSide(_ block: TextBlock) -> BubbleSide? {
        let maxX = block.box.x + block.box.width
        if block.box.x < 0.25, maxX < 0.7 { return .left }
        if block.box.x > 0.3, maxX > 0.8 { return .right }
        return nil
    }

    static func symbolDensity(_ text: String) -> Double {
        let visible = text.filter { !$0.isWhitespace }
        guard !visible.isEmpty else { return 0 }
        return Double(visible.filter { codeSymbols.contains($0) }.count) / Double(visible.count)
    }
}

private extension Array where Element == NSTextCheckingResult {
    func count(of type: NSTextCheckingResult.CheckingType) -> Int {
        filter { $0.resultType == type }.count
    }
}
