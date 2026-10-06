import Foundation

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
}
