import Foundation

/// A category the app ships with. The raw value is the stable key; the folder name is display-only,
/// so renaming a folder never changes what lands in it.
public enum BuiltInCategory: String, Codable, CaseIterable, Sendable {
    case receipt
    case ticket
    case chat
    case social
    case article
    case code
    case place
    case recipe
    case coupon
    case credential
    case schedule
    case note
    case stock

    public var defaultName: String {
        switch self {
        case .receipt: return "收據"
        case .ticket: return "票券"
        case .chat: return "對話"
        case .social: return "社群貼文"
        case .article: return "文章"
        case .code: return "程式碼"
        case .place: return "地點"
        case .recipe: return "食譜"
        case .coupon: return "優惠"
        case .credential: return "帳號資訊"
        case .schedule: return "行程"
        case .note: return "筆記"
        case .stock: return "股票"
        }
    }

    /// Plain-language description for classifiers that need one (the LLM prompt).
    public var hint: String {
        switch self {
        case .receipt: return "發票、訂單明細、付款完成畫面"
        case .ticket: return "登機證、車票、電影票、入場 QR code"
        case .chat: return "LINE、iMessage、Messenger 等聊天畫面"
        case .social: return "Instagram、Threads、Facebook、X 的貼文"
        case .article: return "新聞、部落格文章、書摘"
        case .code: return "程式碼、終端機畫面、錯誤訊息"
        case .place: return "地圖、店家資訊、地址"
        case .recipe: return "食譜與料理步驟"
        case .coupon: return "優惠碼、折價券"
        case .credential: return "密碼、Wi-Fi 資訊、驗證碼"
        case .schedule: return "會議邀請、訂位確認、活動時間"
        case .note: return "待辦、購物清單、隨手筆記"
        case .stock: return "股價、K 線、自選股、下單與庫存損益等證券 App 畫面"
        }
    }
}

/// What a classifier may answer. Custom folders become targets once a learning layer exists.
public enum ClassificationTarget: Hashable, Sendable {
    case builtIn(BuiltInCategory)
    case folder(UUID)
}
