import SwiftUI
import Photos
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
                    image = loaded
                }
            }
            .accessibilityHidden(true)
    }
}
