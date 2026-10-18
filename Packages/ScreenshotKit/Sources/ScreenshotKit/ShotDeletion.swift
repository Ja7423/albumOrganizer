import Foundation

/// What deleting screenshots does to them.
public enum DeletionMethod: String, CaseIterable, Sendable {
    /// Deletes the originals from Photos too; they go to Recently Deleted.
    case deleteFromPhotos
    /// Removes them from the app only; the originals stay in the album.
    case removeFromApp
}

/// Whether the delete dialog asks each time or a remembered method applies.
public enum DeletionPreference: Equatable, Sendable {
    case ask
    case always(DeletionMethod)

    /// Reads a value written by `storedValue`; a missing or unknown value asks.
    public init(storedValue: String?) {
        self = storedValue.flatMap(DeletionMethod.init(rawValue:)).map(Self.always) ?? .ask
    }

    /// `nil` when asking, so clearing the stored value restores the default.
    public var storedValue: String? {
        method?.rawValue
    }

    public var method: DeletionMethod? {
        guard case let .always(method) = self else { return nil }
        return method
    }
}

/// The screenshots a delete acts on: the batch selection, or the one open in the detail page.
public enum DeletionSubject: Equatable, Sendable {
    case selection(count: Int)
    case current
}

/// User-facing text for the delete dialog and its toasts.
public enum DeletionCopy {
    public static let cancelled = "已取消，原檔未刪除"
    public static let failed = "無法刪除原檔，請稍後再試"
    private static let rememberedSuffix = "・已記住此選擇"

    public static func title(for subject: DeletionSubject) -> String {
        "刪除\(amount(subject))截圖"
    }

    public static func summary(_ method: DeletionMethod, subject: DeletionSubject, isRemembered: Bool) -> String {
        let base: String
        switch method {
        case .deleteFromPhotos: base = "已刪除\(amount(subject))（含相簿原檔）"
        case .removeFromApp: base = "已從 App 移除\(amount(subject))（相簿原檔保留）"
        }
        return isRemembered ? base + rememberedSuffix : base
    }

    /// Label for a method, as on the dialog's buttons and the settings list.
    public static func label(_ method: DeletionMethod) -> String {
        switch method {
        case .deleteFromPhotos: return "連同相簿一起刪除"
        case .removeFromApp: return "只從 App 移除"
        }
    }

    private static func amount(_ subject: DeletionSubject) -> String {
        switch subject {
        case let .selection(count): return " \(count) 張"
        case .current: return "這張"
        }
    }
}
