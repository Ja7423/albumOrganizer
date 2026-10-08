import ScreenshotKit
import SwiftUI

/// The 3-column screenshot grid: the 截圖 tab at the root, or a folder/tag pushed from the other tabs.
struct ShotGridScreen: View {
    /// `nil` for the root 所有截圖 grid, which filters with chips instead.
    let route: UIState.Route?

    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s1), count: 3)

    private var scope: Scope {
        switch route {
        case let .folder(id): return .folder(id)
        case .processing: return .processing
        case .unsorted: return .unsorted
        case let .tag(t): return .tag(t)
        case let .feature(f): return .feature(f)
        case nil: return ui.chip
        }
    }

    private var title: String {
        switch route {
        case let .folder(id): return store.library.folderName(id)
        case .processing: return "處理中"
        case .unsorted: return Library.unsortedName
        case let .tag(t): return "#" + t
        case let .feature(f): return f.displayName
        case nil: return "所有截圖"
        }
    }

    private var backLabel: String? {
        switch route {
        case .folder, .processing, .unsorted: return "資料夾"
        case .tag, .feature: return "標籤"
        case nil: return nil
        }
    }

    var body: some View {
        let shots = store.library.shots(in: scope)
        let ids = shots.map(\.id)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let backLabel {
                    Button {
                        ui.endSelecting()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .medium))
                        Text(backLabel)
                    }
                    .buttonStyle(.ghost)
                    .padding(.leading, -6)
                }

                ScreenHeader(kicker: ui.selecting ? "已選 \(ui.selection.count) 張" : "\(shots.count) 張", title: title, topPadding: 6) {
                    if ui.selecting {
                        HStack(spacing: 4) {
                            Button("全選") {
                                ui.selection = ui.selection.isSuperset(of: ids) ? [] : Set(ids)
                            }
                            .buttonStyle(.ghost)
                            Button("完成") { ui.endSelecting() }.buttonStyle(.secondary)
                        }
                    } else {
                        Button("選取") { ui.selecting = true; ui.selection = [] }
                            .buttonStyle(.secondary)
                            .disabled(shots.isEmpty)
                    }
                }

                if route == nil {
                    LimitedAccessBanner()
                    chips
                }

                LazyVGrid(columns: columns, spacing: Space.s1) {
                    ForEach(shots) { shot in
                        cell(shot, pagingThrough: ids)
                    }
                }
                .padding(.top, 8)

                if shots.isEmpty {
                    Text(emptyMessage)
                        .font(Typeface.body(14))
                        .foregroundStyle(Palette.neutral700)
                        .padding(.vertical, 48)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(Palette.bg)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var emptyMessage: String {
        if store.library.shots.isEmpty {
            return store.processingCount > 0 ? "正在整理截圖…" : "相簿裡還沒有螢幕截圖。截圖後會自動出現在這裡。"
        }
        return "這裡還沒有截圖。到「截圖」選取後，用「移到資料夾」或「標籤」整理進來。"
    }

    private struct ChipDef: Identifiable {
        let scope: Scope
        let label: String
        var id: String {
            label
        }
    }

    private var chips: some View {
        let defs = [ChipDef(scope: .all, label: "全部"), ChipDef(scope: .unsorted, label: "未分類")]
            + store.library.presentFeatureTags.map { ChipDef(scope: .feature($0), label: $0.displayName) }
            + store.library.tags.map { ChipDef(scope: .tag($0), label: "#" + $0) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(defs) { chip in
                    Button {
                        ui.chip = chip.scope
                        ui.endSelecting()
                    } label: {
                        TagChip(text: chip.label, style: ui.chip == chip.scope ? .accent : .neutral, size: .regular, horizontalPadding: 12)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, -16)
    }

    private func cell(_ shot: Shot, pagingThrough ids: [String]) -> some View {
        let selected = ui.selection.contains(shot.id)
        return Button {
            if ui.selecting { ui.toggleSelection(shot.id) } else { ui.openDetail(shot.id, in: ids) }
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { AssetImage(id: shot.id, targetSize: CGSize(width: 124, height: 124), alignment: .top) }
                .clipped()
                .contentShape(Rectangle())
                .overlay {
                    if ui.selecting {
                        Rectangle()
                            .fill(selected ? Palette.accent.opacity(0.14) : .clear)
                            .overlay(Rectangle().strokeBorder(selected ? Palette.accent : .clear, lineWidth: 3))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if ui.selecting {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(selected ? Palette.bg : .clear)
                            .frame(width: 22, height: 22)
                            .background(selected ? Palette.accent : Palette.neutral900.opacity(0.25))
                            .overlay(Rectangle().strokeBorder(selected ? Palette.accent : Palette.bg, lineWidth: 1.5))
                            .padding(5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shot.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
