import Foundation

/// Turns signals into the feature tags the app adds on its own.
public enum FeatureDetector {
    public static func detect(_ signals: ScreenshotSignals) -> Set<FeatureTag> {
        var tags: Set<FeatureTag> = []
        if signals.links > 0 { tags.insert(.link) }
        if signals.barcodes > 0 { tags.insert(.qrCode) }
        if signals.phones > 0 { tags.insert(.phone) }
        if signals.dates > 0 { tags.insert(.date) }
        if signals.addresses > 0 { tags.insert(.address) }
        return tags
    }
}
