import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import UIKit
import ScreenshotKit

/// Detail page, layout B (圖片優先): the screenshot fills the page; turning on selection lets you tap
/// recognized text right on the image. Folder, tags and info sit in a bottom bar that expands.
struct ShotDetailScreen: View {
    let shotID: String

    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var selecting = false
    @State private var selected: Set<Int> = []
    @State private var expanded = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        Group {
            if let shot = store.library.shot(shotID) {
                VStack(spacing: 0) {
                    header(shot)
                    imageArea(shot)
                    if selecting {
                        selectionPanel(shot)
                    } else {
                        infoBar(shot)
                    }
                }
            } else {
                // Deleted from Photos while open.
                Palette.bg.ignoresSafeArea().onAppear { ui.closeDetail() }
            }
        }
        .background(Rectangle().fill(Palette.bg).shadowLG().ignoresSafeArea())
        .offset(x: dragOffset)
        .simultaneousGesture(edgeSwipe)
        .task { store.prioritize(shotID) }
    }

    // MARK: - Header

    private func header(_ shot: Shot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { ui.closeDetail() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium))
                    Text("返回")
                }
                .buttonStyle(.ghost)

                VStack(alignment: .leading, spacing: 0) {
                    Text(shot.title).font(Typeface.body(15, .semibold)).lineLimit(1)
                    Text(ShotFormat.shortDate(shot.createdAt)).font(Typeface.body(11)).foregroundStyle(Palette.neutral700)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ShareLink(item: ShotImage(id: shot.id), preview: SharePreview(shot.title)) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 17))
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("分享")
            }
            .padding(.top, 4)
            .padding(.leading, 2)
            .padding(.trailing, 8)
            .padding(.bottom, 8)
            Hairline()
        }
    }

    // MARK: - Image

    private func imageArea(_ shot: Shot) -> some View {
        GeometryReader { geo in
            let fit = fittedSize(in: CGSize(width: geo.size.width - 40, height: geo.size.height - 40), aspect: shot.aspectRatio)
            AssetImage(id: shot.id, targetSize: fit, contentMode: .fit)
                .frame(width: fit.width, height: fit.height)
                .overlay(alignment: .topLeading) {
                    if selecting {
                        TextBlockOverlay(blocks: shot.blocks, selected: selected, size: fit) { id in
                            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.easeInOut(duration: 0.2), value: fit)
        }
        .background(Palette.surface)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            recognitionButton(shot).padding(12)
        }
    }

    private func fittedSize(in box: CGSize, aspect: Double) -> CGSize {
        guard box.width > 0, box.height > 0 else { return .zero }
        let a = CGFloat(aspect)
        return box.width / box.height > a
            ? CGSize(width: box.height * a, height: box.height)
            : CGSize(width: box.width, height: box.width / a)
    }

    @ViewBuilder
    private func recognitionButton(_ shot: Shot) -> some View {
        let ready = shot.recognition == .done && !shot.blocks.isEmpty
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                if selecting { selected = [] }
                selecting.toggle()
                expanded = false
            }
        } label: {
            if shot.recognition == .pending {
                ProgressView().controlSize(.small).tint(Palette.text)
                Text("辨識文字中…")
            } else {
                Image(systemName: "text.viewfinder").font(.system(size: 15))
                Text(selecting ? "結束選取" : recognitionLabel(shot))
            }
        }
        .buttonStyle(ClassicalButtonStyle(kind: selecting ? .primary : .secondary))
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.bg).shadowMD())
        .disabled(!ready)
    }

    private func recognitionLabel(_ shot: Shot) -> String {
        switch shot.recognition {
        case .failed: return "無法辨識文字"
        case .done where shot.blocks.isEmpty: return "沒有辨識到文字"
        default: return "選取圖中文字"
        }
    }

    // MARK: - Selection panel

    private func selectionPanel(_ shot: Shot) -> some View {
        let count = shot.blocks.filter { selected.contains($0.id) }.count
        let all = !shot.blocks.isEmpty && count == shot.blocks.count
        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("已選 \(count) 段").font(Typeface.body(15, .semibold))
                Spacer()
                Text("點圖上的區塊加入選取").font(Typeface.body(12)).foregroundStyle(Palette.neutral700)
            }
            HStack(spacing: 8) {
                Button(all ? "清除選取" : "全選") {
                    selected = all ? [] : Set(shot.blocks.map(\.id))
                }
                .buttonStyle(ClassicalButtonStyle(kind: .secondary, fullWidth: true, alignment: .leading))

                Button {
                    let text = shot.blocks.filter { selected.contains($0.id) }.map(\.text).joined(separator: "\n")
                    ui.copy(text, toast: "已複製 \(count) 段文字")
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 15))
                    Text("複製已選")
                }
                .buttonStyle(ClassicalButtonStyle(kind: .primary, fullWidth: true, alignment: .leading))
                .disabled(count == 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(Palette.bg)
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: - Info bar

    private func infoBar(_ shot: Shot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { ui.present(.move, for: .detail) } label: {
                    Image(systemName: shot.autoPlacement?.source == nil ? "folder" : "sparkles").font(.system(size: 14))
                    Text(shot.isProcessing ? "處理中" : store.library.folderName(shot.folderID))
                }
                .accessibilityLabel("資料夾：\(store.library.folderName(shot.folderID))，\(ShotFormat.placement(shot.placement))")
                .buttonStyle(.secondary)
                .fixedSize()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(FeatureTag.allCases.filter(shot.featureTags.contains), id: \.self) {
                            TagChip(text: $0.displayName, style: .outline)
                        }
                        ForEach(shot.tags, id: \.self) { TagChip(text: "#" + $0, style: .accent) }
                        Button { ui.present(.tags, for: .detail) } label: {
                            TagChip(style: .neutral, leadingIcon: "plus")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("編輯標籤")
                    }
                }

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up").font(.system(size: 17, weight: .medium))
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel(expanded ? "收起" : "更多")
            }

            if expanded {
                VStack(spacing: 0) {
                    MetaRow(key: "分類方式", value: ShotFormat.placement(shot.placement))
                    MetaRow(key: "截圖時間", value: ShotFormat.fullDate(shot.createdAt))
                    MetaRow(key: "尺寸", value: "\(shot.pixelWidth) × \(shot.pixelHeight)")
                    MetaRow(key: "文字辨識", value: recognitionSummary(shot))
                }
                .padding(.top, 10)

                Button {
                    ui.copy(shot.allText, toast: "已複製全部文字（\(shot.blocks.count) 段）")
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 15))
                    Text("複製全部文字")
                }
                .buttonStyle(ClassicalButtonStyle(kind: .primary, fullWidth: true))
                .disabled(shot.blocks.isEmpty)
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(Palette.bg)
        .overlay(alignment: .top) { Hairline() }
    }

    private func recognitionSummary(_ shot: Shot) -> String {
        switch shot.recognition {
        case .pending: return "辨識中…"
        case .failed: return shot.needsRecognition ? "辨識失敗，稍後重試" : "無法辨識"
        case .done:
            guard !shot.blocks.isEmpty else { return "沒有文字" }
            let languages = shot.languageSummary
            return languages.isEmpty ? "\(shot.blocks.count) 段" : "\(shot.blocks.count) 段 · \(languages)"
        }
    }

    // MARK: - Edge swipe back

    private var edgeSwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard value.startLocation.x < 24 else { return }
                dragOffset = max(0, value.translation.width)
            }
            .onEnded { value in
                guard value.startLocation.x < 24 else { return }
                if value.translation.width > 110 || value.predictedEndTranslation.width > 240 {
                    ui.closeDetail()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                }
            }
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

/// Shares the original screenshot at full resolution.
struct ShotImage: Transferable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            guard let image = await PhotoLibraryService.shared.imageData(for: item.id) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            if isPNG(image.0) { return image.0 }
            guard let png = UIImage(data: image.0)?.pngData() else { throw CocoaError(.fileReadCorruptFile) }
            return png
        }
    }

    private static func isPNG(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47])
    }
}
