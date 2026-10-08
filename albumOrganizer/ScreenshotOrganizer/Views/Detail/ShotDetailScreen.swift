import CoreTransferable
import ScreenshotKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShotDetailScreen: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var selecting = false
    @State private var selected: Set<Int> = []
    @State private var expanded = false
    @State private var dragOffset: CGFloat = 0

    /// Width of the leading strip that starts the swipe-back instead of paging.
    private let edgeWidth: CGFloat = 24

    var body: some View {
        Group {
            if let session = ui.detail, let shot = store.library.shot(session.currentID) {
                VStack(spacing: 0) {
                    header(shot)
                    pager(session.visibleShots(in: store.library))
                        .overlay(alignment: .bottomLeading) {
                            recognitionButton(shot).padding(12)
                        }
                    if selecting {
                        selectionPanel(shot)
                    } else {
                        infoBar(shot)
                    }
                }
            } else {
                // Deleted from Photos while open.
                Palette.bg.ignoresSafeArea().onAppear { ui.replaceMissingDetail(in: store.library) }
            }
        }
        .background(Rectangle().fill(Palette.bg).shadowLG().ignoresSafeArea())
        .offset(x: dragOffset)
        .task(id: ui.detailID) {
            if let id = ui.detailID { store.prioritize(id) }
        }
        .onChange(of: ui.detailID) {
            selecting = false
            selected = []
        }
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

    // MARK: - Pager

    private func pager(_ shots: [Shot]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(shots) { shot in
                    ShotPage(shot: shot, selecting: selecting, selected: selected) { id in
                        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: pageID)
        .scrollIndicators(.hidden)
        .scrollDisabled(selecting)
        .background(Palette.surface)
        .clipped()
        .overlay(alignment: .leading) { edgeSwipeStrip }
    }

    private var pageID: Binding<String?> {
        Binding(
            get: { ui.detailID },
            set: { id in
                if let id { ui.showDetailPage(id) }
            }
        )
    }

    // MARK: - Recognition

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

    /// Sits over the pager's leading edge so a drag from there goes back instead of paging.
    private var edgeSwipeStrip: some View {
        Color.clear
            .frame(width: edgeWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(edgeSwipe)
    }

    private var edgeSwipe: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                dragOffset = max(0, value.translation.width)
            }
            .onEnded { value in
                if value.translation.width > 110 || value.predictedEndTranslation.width > 240 {
                    ui.closeDetail()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                }
            }
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
