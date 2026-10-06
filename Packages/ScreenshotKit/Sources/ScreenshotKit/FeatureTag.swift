import Foundation

/// A tag the app adds on its own from what it detects on the screenshot.
public enum FeatureTag: String, Codable, CaseIterable, Sendable {
    case link
    case qrCode
    case phone
    case date
    case address

    public var displayName: String {
        switch self {
        case .link: return "含連結"
        case .qrCode: return "QR code"
        case .phone: return "含電話"
        case .date: return "含日期"
        case .address: return "含地址"
        }
    }
}
