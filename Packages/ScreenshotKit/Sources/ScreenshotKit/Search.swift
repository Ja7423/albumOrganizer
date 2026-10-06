import Foundation

/// One search result: the matching line split around the match so the UI can highlight it.
public struct SearchHit: Hashable, Identifiable, Sendable {
    public var id: String { shotID }
    public var shotID: String
    public var prefix: String
    public var match: String
    public var suffix: String
}

extension Library {
    /// Finds screenshots whose recognized text, tags (including feature tags) or title contain `query`.
    /// Text matches carry the highlighted line; tag/title matches show the first line.
    public func search(_ query: String) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .widthInsensitive]

        return shots.compactMap { (shot: Shot) -> SearchHit? in
            for block in shot.blocks {
                guard let r = block.text.range(of: q, options: options) else { continue }
                var prefix = String(block.text[..<r.lowerBound])
                if prefix.count > 12 { prefix = "…" + prefix.suffix(12) }
                return SearchHit(shotID: shot.id, prefix: prefix, match: String(block.text[r]), suffix: String(block.text[r.upperBound...]))
            }
            let meta = shot.tags + shot.featureTags.map(\.displayName) + [shot.title]
            guard meta.contains(where: { $0.range(of: q, options: options) != nil }) else { return nil }
            return SearchHit(shotID: shot.id, prefix: shot.blocks.first?.text ?? "", match: "", suffix: "")
        }
    }
}
