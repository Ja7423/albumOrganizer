import Photos
import SwiftUI
import UIKit

/// A Photos asset drawn into whatever frame the caller gives it.
struct AssetImage: View {
    let id: String
    /// Requested size in points; scaled to pixels for the request.
    var targetSize: CGSize
    var contentMode: ContentMode = .fill
    var alignment: Alignment = .center

    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?
    /// The asset `image` belongs to; it lags behind `id` until the new asset's first image arrives.
    @State private var imageID: String?

    init(id: String, targetSize: CGSize, contentMode: ContentMode = .fill, alignment: Alignment = .center) {
        self.id = id
        self.targetSize = targetSize
        self.contentMode = contentMode
        self.alignment = alignment
        // Start from whatever was last loaded for this asset (e.g. the grid thumbnail), so a freshly
        // pushed detail page shows the screenshot during the push instead of an empty box.
        let cached = PhotoLibraryService.shared.cachedImage(for: id)
        _image = State(initialValue: cached)
        _imageID = State(initialValue: cached == nil ? nil : id)
    }

    var body: some View {
        Rectangle()
            .fill(Palette.neutral200)
            .overlay(alignment: alignment) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            }
            .clipped()
            // `.clipped()` only clips drawing; without this the aspect-fill overflow stays hit-testable
            // and steals taps from neighbouring grid cells.
            .contentShape(Rectangle())
            .task(id: "\(id)@\(Int(targetSize.width))x\(Int(targetSize.height))") {
                guard targetSize.width > 0, targetSize.height > 0 else { return }
                let pixels = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
                for await loaded in PhotoLibraryService.shared.images(for: id, targetSize: pixels, contentMode: contentMode == .fill ? .aspectFill : .aspectFit) {
                    // The fast degraded delivery can be smaller than the cached image already shown; don't step down to it.
                    if imageID == id, let image, loaded.pixelArea < image.pixelArea { continue }
                    image = loaded
                    imageID = id
                }
            }
            .accessibilityHidden(true)
    }
}

extension UIImage {
    /// Width × height in pixels.
    var pixelArea: CGFloat {
        size.width * scale * size.height * scale
    }
}
