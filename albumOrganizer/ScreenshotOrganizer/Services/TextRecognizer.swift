import ImageIO
import ScreenshotKit
import Vision

/// What one recognition pass finds on a screenshot.
nonisolated struct RecognitionOutput {
    var blocks: [TextBlock]
    var barcodes: [String]
}

nonisolated protocol ScreenRecognizing: Sendable {
    /// Recognized lines, top to bottom, with the status bar removed, plus barcode payloads. Throws if Vision fails.
    func recognize(_ data: Data, orientation: CGImagePropertyOrientation) async throws -> RecognitionOutput
}

/// On-device text and barcode recognition with Vision. Nothing is uploaded.
nonisolated struct VisionScreenRecognizer: ScreenRecognizing {
    static let languages = ["zh-Hant", "en-US"]

    func recognize(_ data: Data, orientation: CGImagePropertyOrientation) async throws -> RecognitionOutput {
        try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.recognitionLanguages = Self.languages
            textRequest.usesLanguageCorrection = true
            let barcodeRequest = VNDetectBarcodesRequest()

            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            try handler.perform([textRequest])
            // Barcodes are a bonus signal: a failure here must not cost the recognized text.
            try? handler.perform([barcodeRequest])

            let blocks = (textRequest.results ?? []).compactMap { observation -> TextBlock? in
                guard let text = observation.topCandidates(1).first?.string,
                      !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                // Vision boxes are normalized with a bottom-left origin.
                let b = observation.boundingBox
                return TextBlock(id: 0, text: text, box: NormalizedRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
            }
            .sorted { lhs, rhs in
                abs(lhs.box.y - rhs.box.y) < 0.006 ? lhs.box.x < rhs.box.x : lhs.box.y < rhs.box.y
            }
            let barcodes = (barcodeRequest.results ?? []).map { $0.payloadStringValue ?? "" }
            return RecognitionOutput(blocks: TextBlockFilter.droppingStatusBar(blocks), barcodes: barcodes)
        }.value
    }
}
