import Foundation

/// The knobs of one text recognition pass. `.standard` is what the app uses; the others exist so the
/// OCR benchmark can measure what each knob costs in speed and in quality before any of them is adopted.
public struct RecognitionOptions: Hashable, Sendable {
    /// The image is drawn at this fraction of its pixel size before recognition; 1 leaves it as is.
    public var scale: Double
    public var usesLanguageCorrection: Bool
    /// Relative to the image height; `nil` keeps Vision's own default.
    public var minimumTextHeight: Double?
    /// Only this part of the screenshot is read (top-left origin); `nil` reads all of it.
    public var regionOfInterest: NormalizedRect?
    public var detectsBarcodes: Bool

    public init(
        scale: Double = 1,
        usesLanguageCorrection: Bool = true,
        minimumTextHeight: Double? = nil,
        regionOfInterest: NormalizedRect? = nil,
        detectsBarcodes: Bool = true
    ) {
        self.scale = scale
        self.usesLanguageCorrection = usesLanguageCorrection
        self.minimumTextHeight = minimumTextHeight
        self.regionOfInterest = regionOfInterest
        self.detectsBarcodes = detectsBarcodes
    }

    public static let standard = RecognitionOptions()

    /// Everything but the status bar and the home indicator strip.
    public static let contentRegion: NormalizedRect = {
        let top = TextBlockFilter.statusBarHeight
        let bottom = 0.035
        return NormalizedRect(x: 0, y: top, width: 1, height: 1 - top - bottom)
    }()

    /// A short, stable name for log lines, e.g. `scale=0.50 lc=off minH=default roi=content bc=on`.
    public var label: String {
        let minHeight = minimumTextHeight.map { String(format: "%.3f", $0) } ?? "default"
        let region = regionOfInterest.map { $0 == Self.contentRegion ? "content" : String(format: "%.3f,%.3f,%.3f,%.3f", $0.x, $0.y, $0.width, $0.height) } ?? "full"
        return String(format: "scale=%.2f", scale)
            + " lc=\(usesLanguageCorrection ? "on" : "off")"
            + " minH=\(minHeight)"
            + " roi=\(region)"
            + " bc=\(detectsBarcodes ? "on" : "off")"
    }
}

public extension RecognitionOptions {
    /// Every combination of the given values, in a fixed order with the first value of each knob first.
    static func grid(
        scales: [Double] = [1],
        languageCorrection: [Bool] = [true],
        minimumTextHeights: [Double?] = [nil],
        regionsOfInterest: [NormalizedRect?] = [nil],
        barcodes: [Bool] = [true]
    ) -> [RecognitionOptions] {
        scales.flatMap { scale in
            languageCorrection.flatMap { correction in
                minimumTextHeights.flatMap { minHeight in
                    regionsOfInterest.flatMap { region in
                        barcodes.map { detects in
                            RecognitionOptions(
                                scale: scale,
                                usesLanguageCorrection: correction,
                                minimumTextHeight: minHeight,
                                regionOfInterest: region,
                                detectsBarcodes: detects
                            )
                        }
                    }
                }
            }
        }
    }

    /// What the benchmark runs: `.standard` first (the baseline), then each knob changed on its own,
    /// then the combinations most likely to reach the speed target. Duplicates are dropped.
    static let benchmarkVariants: [RecognitionOptions] = {
        let base = RecognitionOptions.standard
        var singles: [RecognitionOptions] = []
        for scale in [0.75, 0.5] { singles.append(base.with { $0.scale = scale }) }
        singles.append(base.with { $0.usesLanguageCorrection = false })
        for height in [0.01, 0.02] { singles.append(base.with { $0.minimumTextHeight = height }) }
        singles.append(base.with { $0.regionOfInterest = contentRegion })
        singles.append(base.with { $0.detectsBarcodes = false })
        let combinations = grid(
            scales: [0.75, 0.5],
            languageCorrection: [false],
            minimumTextHeights: [nil, 0.01],
            regionsOfInterest: [contentRegion],
            barcodes: [true]
        )
        return ([base] + singles + combinations).uniqued()
    }()

    func with(_ change: (inout RecognitionOptions) -> Void) -> RecognitionOptions {
        var copy = self
        change(&copy)
        return copy
    }
}

public extension NormalizedRect {
    /// A box Vision reported inside `region` (both top-left origin), mapped back to the whole image.
    func mapped(fromRegion region: NormalizedRect) -> NormalizedRect {
        NormalizedRect(
            x: region.x + x * region.width,
            y: region.y + y * region.height,
            width: width * region.width,
            height: height * region.height
        )
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
