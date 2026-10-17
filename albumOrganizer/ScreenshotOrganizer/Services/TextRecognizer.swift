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
    /// `.fast` is left out on purpose: it does not read Traditional Chinese.
    static let languages = ["zh-Hant", "en-US"]

    /// Only the OCR benchmark passes anything but `.standard`.
    var options: RecognitionOptions = .standard

    func recognize(_ data: Data, orientation: CGImagePropertyOrientation) async throws -> RecognitionOutput {
        try await Task.detached(priority: .utility) { [options] in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let image = Self.scaled(decoded, by: options.scale)
            else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.recognitionLanguages = Self.languages
            textRequest.usesLanguageCorrection = options.usesLanguageCorrection
            if let minimumTextHeight = options.minimumTextHeight {
                textRequest.minimumTextHeight = Float(minimumTextHeight)
            }
            if let region = options.regionOfInterest {
                // Vision's region has a bottom-left origin; ours has a top-left one.
                textRequest.regionOfInterest = CGRect(x: region.x, y: 1 - region.maxY, width: region.width, height: region.height)
            }

            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            try handler.perform([textRequest])
            var barcodes: [String] = []
            if options.detectsBarcodes {
                let barcodeRequest = VNDetectBarcodesRequest()
                // Barcodes are a bonus signal: a failure here must not cost the recognized text.
                try? handler.perform([barcodeRequest])
                barcodes = (barcodeRequest.results ?? []).map { $0.payloadStringValue ?? "" }
            }

            let region = options.regionOfInterest
            let blocks: [TextBlock] = (textRequest.results ?? []).compactMap { Self.block(from: $0, in: region) }
                .sorted { lhs, rhs in
                    abs(lhs.box.y - rhs.box.y) < 0.006 ? lhs.box.x < rhs.box.x : lhs.box.y < rhs.box.y
                }
            return RecognitionOutput(blocks: TextBlockFilter.droppingStatusBar(blocks), barcodes: barcodes)
        }.value
    }

    private static func block(from observation: VNRecognizedTextObservation, in region: ScreenshotKit.NormalizedRect?) -> TextBlock? {
        guard let text = observation.topCandidates(1).first?.string,
              !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        // Vision boxes are normalized with a bottom-left origin, relative to the region of interest.
        let b = observation.boundingBox
        let box = ScreenshotKit.NormalizedRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
        return TextBlock(id: 0, text: text, box: region.map { box.mapped(fromRegion: $0) } ?? box)
    }

    /// The image redrawn at `scale` of its pixel size; at 1 the decoded image itself.
    private static func scaled(_ image: CGImage, by scale: Double) -> CGImage? {
        guard scale < 1 else { return image }
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
