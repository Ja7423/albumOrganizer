import Foundation

/// Keyword, pattern and signal rules per built-in category. Runs in milliseconds and errs on the side
/// of no answer: a category must score clearly ahead of the runner-up.
public struct RuleClassifier: ScreenshotClassifier {
    public struct Configuration: Sendable {
        /// How far the best score must lead the second best; closer calls return `nil`.
        public var minMargin: Double

        public init(minMargin: Double = 0.2) {
            self.minMargin = minMargin
        }
    }

    public struct Rule: Sendable {
        public var category: BuiltInCategory
        /// Case- and width-insensitive substrings.
        public var keywords: [String]
        /// Distinct keyword hits that earn the full keyword score.
        public var hitsForFullScore: Int
        /// Regexes that are enough on their own.
        public var patterns: [String]
        /// Extra score from layout and detector signals.
        public var signalScore: @Sendable (ScreenshotSignals) -> Double

        public init(
            _ category: BuiltInCategory,
            keywords: [String] = [],
            hitsForFullScore: Int = 2,
            patterns: [String] = [],
            signalScore: @escaping @Sendable (ScreenshotSignals) -> Double = { _ in 0 }
        ) {
            self.category = category
            self.keywords = keywords
            self.hitsForFullScore = hitsForFullScore
            self.patterns = patterns
            self.signalScore = signalScore
        }
    }

    static let fullKeywordScore = 0.8
    static let patternScore = 0.9

    public var configuration: Configuration
    public var rules: [Rule]

    public init(configuration: Configuration = .init(), rules: [Rule] = RuleClassifier.defaultRules) {
        self.configuration = configuration
        self.rules = rules
    }

    public func classify(_ input: ClassifierInput) async throws -> ClassifierVerdict? {
        let ranked = scores(for: input).sorted { $0.value > $1.value }
        guard let best = ranked.first, best.value > 0 else { return nil }
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        guard best.value - runnerUp >= configuration.minMargin else { return nil }
        return ClassifierVerdict(target: .builtIn(best.key), confidence: best.value, source: .rule)
    }

    /// Score per category, excluding the input's excluded targets. Exposed for tests and tuning.
    public func scores(for input: ClassifierInput) -> [BuiltInCategory: Double] {
        var result: [BuiltInCategory: Double] = [:]
        for rule in rules where !input.excluded.contains(.builtIn(rule.category)) {
            result[rule.category] = Self.score(rule, text: input.text, signals: input.signals)
        }
        return result
    }

    static func score(_ rule: Rule, text: String, signals: ScreenshotSignals) -> Double {
        let textScore = max(patternScore(rule, text: text), keywordScore(rule, text: text))
        return min(1, textScore + rule.signalScore(signals))
    }

    private static func patternScore(_ rule: Rule, text: String) -> Double {
        let matched = rule.patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
        return matched ? patternScore : 0
    }

    private static func keywordScore(_ rule: Rule, text: String) -> Double {
        guard !rule.keywords.isEmpty, rule.hitsForFullScore > 0 else { return 0 }
        let hits = rule.keywords.filter { text.range(of: $0, options: [.caseInsensitive, .widthInsensitive]) != nil }.count
        return fullKeywordScore * Double(min(hits, rule.hitsForFullScore)) / Double(rule.hitsForFullScore)
    }
}

extension RuleClassifier {
    public static let defaultRules: [Rule] = [
        Rule(.receipt,
             keywords: ["發票", "收據", "合計", "總計", "小計", "訂單明細", "訂單編號", "付款金額", "付款成功", "交易明細",
                        "實付", "統一編號", "receipt", "invoice", "subtotal", "total"],
             patterns: ["電子發票證明聯"]),
        Rule(.ticket,
             keywords: ["登機證", "登機門", "航班", "車次", "車票", "訂位代號", "座位", "入場券", "艙等", "月台", "影廳",
                        "boarding pass", "flight", "gate", "seat"],
             signalScore: { $0.barcodes > 0 ? 0.3 : 0 }),
        Rule(.chat,
             keywords: ["已讀", "傳送訊息", "輸入訊息", "iMessage", "訊息", "已傳送", "Aa"],
             signalScore: { $0.hasAlternatingBubbles ? 0.6 : 0 }),
        Rule(.social,
             keywords: ["讚", "留言", "分享", "追蹤", "轉發", "則留言", "個讚", "查看翻譯", "likes", "comments", "follow", "repost"],
             hitsForFullScore: 3),
        Rule(.article,
             keywords: ["分鐘閱讀", "閱讀時間", "作者", "記者", "報導", "延伸閱讀", "訂閱", "書摘", "kindle", "劃線", "發布於", "更新於"],
             patterns: [#"第\s*\d+\s*[章頁]"#]),
        Rule(.code,
             keywords: ["func ", "let ", "var ", "import ", "class ", "struct ", "enum ", "interface ", "def ", "return", "=>",
                        "console.log", "print(",
                        "async", "await", "</", "const ", "public ", "private ", "#include", "Traceback", "error:"],
             hitsForFullScore: 3,
             signalScore: { $0.symbolDensity >= 0.08 ? 0.4 : 0 }),
        Rule(.place,
             keywords: ["地址", "營業中", "營業時間", "公里", "路線", "開始導航", "則評論", "地圖", "address", "directions"],
             signalScore: { $0.addresses > 0 ? 0.5 : 0 }),
        Rule(.recipe,
             keywords: ["食譜", "人份", "材料", "汆燙", "小火", "中火", "調味", "步驟", "分鐘", "少許", "大匙", "小匙", "公克", "備料"],
             hitsForFullScore: 3),
        Rule(.coupon,
             keywords: ["優惠碼", "折扣碼", "折價券", "優惠券", "兌換碼", "coupon", "promo code", "discount code"],
             patterns: [#"(?s)(優惠|折扣|折價|code).{0,20}\b(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*\d)[A-Z0-9]{4,12}\b"#]),
        Rule(.credential,
             keywords: ["密碼", "password", "passcode", "驗證碼", "wi-fi", "wifi", "帳號", "網路名稱", "SSID"],
             patterns: [#"驗證碼[:：\s]*\d{4,8}"#]),
        Rule(.schedule,
             keywords: ["會議", "meeting", "會議室", "議程", "zoom.us", "meet.google", "teams.microsoft", "邀請", "行事曆",
                        "訂位確認", "預約", "報到", "活動時間"],
             signalScore: { $0.dates > 0 ? 0.3 : 0 }),
        Rule(.note,
             keywords: ["待辦", "to-do", "todo", "記得", "別忘", "deadline", "購物清單", "採買", "要買", "備忘錄", "筆記"])
    ]
}
