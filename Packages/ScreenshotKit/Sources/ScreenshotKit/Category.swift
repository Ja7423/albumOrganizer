import Foundation

/// A category the app ships with. The raw value is the stable key; the folder name is display-only,
/// so renaming a folder never changes what lands in it.
public enum BuiltInCategory: String, Codable, CaseIterable, Sendable {
    case receipt
    case ticket
    case social
    case article
    case code
    case place
    case recipe
    case shopping
    case credential
    case schedule
    case note
    case stock
    case info

    public var defaultName: String {
        switch self {
        case .receipt: return "收據"
        case .ticket: return "票券"
        case .social: return "社群"
        case .article: return "文章"
        case .code: return "程式碼"
        case .place: return "地點"
        case .recipe: return "食譜"
        case .shopping: return "購物"
        case .credential: return "帳號資訊"
        case .schedule: return "行程"
        case .note: return "筆記"
        case .stock: return "股票"
        case .info: return "資訊"
        }
    }

    /// Plain-language description for classifiers that need one (the LLM prompt).
    public var hint: String {
        switch self {
        case .receipt: return "發票、訂單明細、付款完成畫面"
        case .ticket: return "登機證、車票、電影票、入場 QR code，畫面上有班次、座位或入場資訊"
        case .social: return "社群 App 動態裡的貼文與留言：有發文者名稱、「追蹤」、發文多久前（例如「4小時」「26分鐘」），以及按讚、留言、分享、回覆；也包含 LINE、WeChat、Messenger 等通訊 App 的聊天列表與對話"
        case .article: return "用瀏覽器或 App 內瀏覽器開啟的網頁：頂端常有網址或網域（例如 www.xxx.com），內容是新聞、部落格、小說或故事連載、書摘、廣告或介紹頁；社群上發的長篇文章（整個畫面是一大段分析、心得或故事）也算"
        case .code: return "程式碼、終端機畫面、錯誤訊息"
        case .place: return "地圖、店家資訊、地址、飯店與旅遊行程介紹"
        case .recipe: return "食譜與料理步驟"
        case .shopping: return "商品頁、選購配備與規格、售價或分期付款、購物車、優惠券與折扣碼"
        case .credential: return "帳號與密碼、Wi-Fi 資訊、驗證碼、驗證器的恢復碼、帳戶餘額"
        case .schedule: return "會議邀請、訂位確認、活動時間"
        case .note: return "待辦、購物清單、隨手筆記"
        case .stock: return "股價、K 線、自選股、下單與庫存損益（已實現、未實現）等證券 App 畫面；討論股市的文章或貼文不算"
        case .info: return "系統與裝置資訊（電池、儲存空間、描述檔、軟體更新）、服務的通知與查詢結果、保單或方案說明"
        }
    }
}

/// What a classifier may answer. Custom folders become targets once a learning layer exists.
public enum ClassificationTarget: Hashable, Sendable {
    case builtIn(BuiltInCategory)
    case folder(UUID)
}
