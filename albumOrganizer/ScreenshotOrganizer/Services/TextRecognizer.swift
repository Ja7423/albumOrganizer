import ImageIO
import Vision
import ScreenshotKit

/// On-device text recognition with Vision. Nothing is uploaded.
nonisolated enum TextRecognizer {
    static let languages = ["zh-Hant", "en-US"]

    /// Recognized lines, top to bottom, with the status bar removed. Throws if Vision fails.
    static func recognize(_ data: Data, orientation: CGImagePropertyOrientation) async throws -> [TextBlock] {
        try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = TextRecognizer.languages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            try handler.perform([request])

            let blocks = (request.results ?? []).compactMap { observation -> TextBlock? in
                guard let text = observation.topCandidates(1).first?.string,
                      !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                // Vision boxes are normalized with a bottom-left origin.
                let b = observation.boundingBox
                return TextBlock(id: 0, text: text, box: NormalizedRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
            }
            .sorted { lhs, rhs in
                abs(lhs.box.y - rhs.box.y) < 0.006 ? lhs.box.x < rhs.box.x : lhs.box.y < rhs.box.y
            }
            return TextBlockFilter.droppingStatusBar(blocks)
        }.value
    }
}
