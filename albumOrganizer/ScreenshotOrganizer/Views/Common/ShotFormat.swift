import Foundation
import ScreenshotKit

enum ShotFormat {
    private static let locale = Locale(identifier: "zh_Hant_TW")

    private static let short: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    private static let full: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "y年M月d日 HH:mm"
        return f
    }()

    /// "10月5日 18:42", with the year when it isn't this year.
    static func shortDate(_ date: Date) -> String {
        Calendar.current.isDate(date, equalTo: .now, toGranularity: .year) ? short.string(from: date) : full.string(from: date)
    }

    /// "2026年10月5日 18:42"
    static func fullDate(_ date: Date) -> String {
        full.string(from: date)
    }

    /// How the screenshot got into its folder, e.g. "自動分類 · 規則".
    static func placement(_ placement: Placement) -> String {
        switch placement {
        case .pending: return "處理中…"
        case .user: return "手動放入"
        case let .auto(auto):
            guard let source = auto.source else { return "自動分類 · 無法判斷" }
            return "自動分類 · " + sourceName(source)
        }
    }

    private static func sourceName(_ source: ClassifierSource) -> String {
        switch source {
        case .rule: return "規則"
        case .knn: return "相似截圖"
        case .llm: return "Apple Intelligence"
        }
    }
}
