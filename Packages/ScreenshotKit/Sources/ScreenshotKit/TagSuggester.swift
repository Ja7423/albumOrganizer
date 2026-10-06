import Foundation

/// Proposes tags from a screenshot's recognized text. Runs entirely on device;
/// suggestions are only applied after the user confirms them.
public enum TagSuggester {
    public struct Rule: Sendable {
        public var tag: String
        /// Case-insensitive substrings.
        public var keywords: [String]
        /// How many distinct keywords must appear.
        public var minHits: Int
        /// Any one match is enough on its own.
        public var patterns: [String]

        public init(tag: String, keywords: [String] = [], minHits: Int = 1, patterns: [String] = []) {
            self.tag = tag
            self.keywords = keywords
            self.minHits = minHits
            self.patterns = patterns
        }

        func matches(_ text: String) -> Bool {
            if patterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) { return true }
            guard !keywords.isEmpty else { return false }
            let hits = keywords.filter { text.range(of: $0, options: [.caseInsensitive, .widthInsensitive]) != nil }.count
            return hits >= minHits
        }
    }

    public static let maxSuggestions = 3

    public static let rules: [Rule] = [
        Rule(tag: "收據", keywords: ["發票", "收據", "合計", "總計", "小計", "訂單明細", "訂單編號", "付款金額", "receipt", "invoice", "subtotal", "total"]),
        Rule(tag: "票券", keywords: ["登機證", "登機門", "航班", "車次", "車票", "訂位代號", "座位", "入場券", "boarding pass", "flight", "gate", "seat"]),
        Rule(tag: "地址", keywords: ["地址", "address"], patterns: [#"[市縣].{0,6}[區鄉鎮市].{0,14}[路街道巷].{0,12}\d+\s*號"#]),
        Rule(tag: "程式碼", keywords: ["func ", "let ", "var ", "import ", "class ", "def ", "return", "=>", "{", "}", "console.log", "print(", "async", "await", "</"], minHits: 3),
        Rule(tag: "優惠碼", keywords: ["優惠碼", "折扣碼", "折價券", "優惠券", "coupon", "promo code", "discount code"],
             patterns: [#"(?s)(優惠|折扣|折價|code).{0,20}\b(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*\d)[A-Z0-9]{4,12}\b"#]),
        Rule(tag: "密碼", keywords: ["密碼", "password", "passcode", "驗證碼", "wi-fi", "wifi"]),
        Rule(tag: "會議", keywords: ["會議", "meeting", "會議室", "議程", "zoom.us", "meet.google", "teams.microsoft", "demo"]),
        Rule(tag: "待辦", keywords: ["待辦", "to-do", "todo", "記得", "別忘", "deadline", "前交出", "提醒"]),
        Rule(tag: "購物清單", keywords: ["購物清單", "採買", "要買", "順便買", "幫我買"]),
        Rule(tag: "美食", keywords: ["餐廳", "菜單", "美食", "營業中", "營業時間", "訂位", "外帶"]),
        Rule(tag: "食譜", keywords: ["食譜", "人份", "材料", "汆燙", "小火", "調味", "步驟", "分鐘"], minHits: 3),
        Rule(tag: "書摘", keywords: ["書摘", "kindle", "劃線"], patterns: [#"第\s*\d+\s*[章頁]"#]),
        Rule(tag: "連結", patterns: [#"https?://\S+"#, #"\b[\w-]+\.(com|tw|org|io|net|dev|app)(/\S*)?\b"#])
    ]

    public static func suggest(for text: String, excluding existing: [String] = []) -> [String] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return rules
            .filter { !existing.contains($0.tag) && $0.matches(text) }
            .prefix(maxSuggestions)
            .map(\.tag)
    }
}
