import ScreenshotKit
import SwiftUI

/// One page of the detail pager: the screenshot fitted to the page, with tappable text blocks while selecting.
struct ShotPage: View {
    let shot: Shot
    let selecting: Bool
    let selected: Set<Int>
    let onToggleBlock: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let fit = fittedSize(in: CGSize(width: geo.size.width - 40, height: geo.size.height - 40), aspect: shot.aspectRatio)
            AssetImage(id: shot.id, targetSize: fit, contentMode: .fit)
                .frame(width: fit.width, height: fit.height)
                .overlay(alignment: .topLeading) {
                    if selecting {
                        TextBlockOverlay(blocks: shot.blocks, selected: selected, size: fit, toggle: onToggleBlock)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func fittedSize(in box: CGSize, aspect: Double) -> CGSize {
        guard box.width > 0, box.height > 0 else { return .zero }
        let a = CGFloat(aspect)
        return box.width / box.height > a
            ? CGSize(width: box.height * a, height: box.height)
            : CGSize(width: box.width, height: box.width / a)
    }
}

/// Tappable outlines over each recognized line.
private struct TextBlockOverlay: View {
    let blocks: [TextBlock]
    let selected: Set<Int>
    let size: CGSize
    let toggle: (Int) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(blocks) { block in
                let on = selected.contains(block.id)
                let rect = CGRect(
                    x: block.box.x * size.width - 3,
                    y: block.box.y * size.height - 2,
                    width: block.box.width * size.width + 6,
                    height: block.box.height * size.height + 4
                )
                Rectangle()
                    .fill(Palette.accent.opacity(on ? 0.30 : 0.08))
                    .overlay(Rectangle().strokeBorder(Palette.accent, lineWidth: 1.5))
                    .frame(width: rect.width, height: rect.height)
                    .contentShape(Rectangle().inset(by: -4))
                    .onTapGesture { toggle(block.id) }
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityElement()
                    .accessibilityLabel(block.text)
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}
