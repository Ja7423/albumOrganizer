import SwiftUI
import ScreenshotKit

struct SheetHost: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui
    @State private var lastSheet: UIState.Sheet = .move
    @State private var contentHeight: CGFloat = 320

    private struct SheetHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 320
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Palette.neutral900.opacity(0.45)
                    .ignoresSafeArea()
                    .opacity(ui.sheet == nil ? 0 : 1)
                    .allowsHitTesting(ui.sheet != nil)
                    .onTapGesture { ui.dismissSheet() }

                if ui.sheet != nil {
                    VStack(spacing: 0) {
                        Rectangle().fill(Palette.text).frame(height: 1)
                        ScrollView {
                            content
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                                .padding(.bottom, 40)
                                .background(GeometryReader { inner in
                                    Color.clear.preference(key: SheetHeightKey.self, value: inner.size.height)
                                })
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(height: min(contentHeight, geo.size.height * 0.72))
                    }
                    .background(Rectangle().fill(Palette.bg).shadowLG().ignoresSafeArea(edges: .bottom))
                    .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onChange(of: ui.sheet) { _, sheet in if let sheet { lastSheet = sheet } }
        .onPreferenceChange(SheetHeightKey.self) { contentHeight = $0 }
    }

    @ViewBuilder private var content: some View {
        let sheet = ui.sheet ?? lastSheet
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(sheet == .move ? "移到資料夾" : "標籤").font(Typeface.head(22))
                    Text(subtitle(sheet)).font(Typeface.body(12)).foregroundStyle(Palette.neutral700)
                }
                Spacer()
                Button("完成") { ui.dismissSheet() }.buttonStyle(.ghost)
            }
            .padding(.top, 14)
            .padding(.bottom, 10)
            Hairline()

            switch sheet {
            case .move: MoveSheetContent()
            case .tags: TagSheetContent()
            }
        }
    }

    private func subtitle(_ sheet: UIState.Sheet) -> String {
        if ui.sheetContext == .batch { return "套用到 \(ui.selection.count) 張截圖" }
        return sheet == .move ? "一張截圖只會在一個資料夾" : "可以加上多個標籤"
    }
}

private struct MoveSheetContent: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        let lib = store.library
        // In the detail context, mark the folder the screenshot is in now.
        let detailShot: Shot? = ui.sheetContext == .detail ? ui.sheetTargets.first.flatMap { lib.shot($0) } : nil

        VStack(spacing: 0) {
            row(name: Library.unsortedName, icon: "tray", count: lib.count(in: .unsorted), isCurrent: detailShot != nil && detailShot?.folderID == nil) { move(to: nil) }
            ForEach(lib.folders) { folder in
                row(name: folder.name, icon: "folder", count: lib.count(in: .folder(folder.id)), isCurrent: detailShot?.folderID == folder.id) { move(to: folder.id) }
            }
            Button { ui.dialog = .newFolder(moveAfter: true) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 17))
                    Text("新增資料夾").font(Typeface.body(16))
                    Spacer()
                }
                .foregroundStyle(Palette.accent700)
                .padding(.vertical, 13)
            }
            .buttonStyle(.pressable)
        }
    }

    private func row(name: String, icon: String, count: Int, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 17)).frame(width: 20)
                    Text(name).font(Typeface.body(16))
                    Spacer()
                    Text("\(count)").font(Typeface.body(13)).foregroundStyle(Palette.neutral700).monospacedDigit()
                    if isCurrent {
                        Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.accent)
                    }
                }
                .padding(.vertical, 13)
                Hairline()
            }
        }
        .buttonStyle(.pressable)
    }

    private func move(to folderID: UUID?) {
        let ids = ui.sheetTargets
        let batch = ui.sheetContext == .batch
        store.mutate { $0.move(ids, to: folderID) }
        ui.dismissSheet()
        if batch { ui.endSelecting() }
        ui.showToast((batch ? "\(ids.count) 張已" : "已") + "移到「\(store.library.folderName(folderID))」")
    }
}

private struct TagSheetContent: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui
    @State private var newTag = ""
    @FocusState private var focused: Bool

    var body: some View {
        let lib = store.library
        let targets = ui.sheetTargets.compactMap { lib.shot($0) }
        let detailShot = ui.sheetContext == .detail ? targets.first : nil
        let features = FeatureTag.allCases.filter { detailShot?.featureTags.contains($0) == true }

        VStack(alignment: .leading, spacing: 0) {
            if let detailShot, !features.isEmpty {
                AutoLabel(text: "自動偵測 · 點一下移除").padding(.top, 14)
                FlowLayout {
                    ForEach(features, id: \.self) { feature in
                        Button {
                            store.mutate { $0.dismissFeatureTag(feature, from: detailShot.id) }
                            ui.showToast("已移除「\(feature.displayName)」")
                        } label: {
                            TagChip(text: feature.displayName, style: .outline, size: .large, leadingIcon: "xmark")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }

            Text("所有標籤").font(Typeface.body(12)).foregroundStyle(Palette.neutral700).padding(.top, 16)
            FlowLayout {
                ForEach(lib.tags, id: \.self) { tag in
                    let on = !targets.isEmpty && targets.allSatisfy { $0.tags.contains(tag) }
                    Button {
                        store.mutate { $0.toggleTag(tag, on: targets.map(\.id)) }
                    } label: {
                        TagChip(text: tag, style: on ? .accent : .neutral, size: .large, leadingIcon: on ? "checkmark" : nil)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)

            HStack(spacing: 8) {
                TextField("建立新標籤", text: $newTag)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(create)
                    .classicalInput(minHeight: 42, fontSize: 16, focused: focused)
                Button("新增", action: create)
                    .buttonStyle(.secondary)
                    .disabled(Library.normalizedTag(newTag).isEmpty)
            }
            .padding(.top, 16)
        }
    }

    private func create() {
        let name = Library.normalizedTag(newTag)
        guard !name.isEmpty else { return }
        store.mutate { $0.addTag(name, to: ui.sheetTargets) }
        newTag = ""
        ui.showToast("已建立並加上 #\(name)")
    }
}

// MARK: - Name dialog

/// `.dialog` for 新增資料夾 / 重新命名資料夾 / 新增標籤.
struct NameDialog: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui
    let kind: UIState.Dialog
    @State private var name = ""
    @FocusState private var focused: Bool

    private var isTag: Bool { kind == .newTag }

    private var title: String {
        switch kind {
        case .newTag: return "新增標籤"
        case .newFolder: return "新增資料夾"
        case .renameFolder: return "重新命名資料夾"
        }
    }

    private var confirmLabel: String {
        if case .renameFolder = kind { return "儲存" }
        return "建立"
    }

    var body: some View {
        ZStack {
            Palette.neutral900.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { ui.dialog = nil }

            VStack(alignment: .leading, spacing: Space.s3) {
                Text(title).font(Typeface.head(20))
                VStack(alignment: .leading, spacing: 5) {
                    Text("名稱").font(Typeface.body(12)).foregroundStyle(Palette.text.opacity(0.7))
                    TextField(isTag ? "例如：發票" : "例如：家用、報稅", text: $name)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(confirm)
                        .classicalInput(minHeight: 42, fontSize: 16, focused: focused)
                }
                HStack(spacing: Space.s2) {
                    Spacer()
                    Button("取消") { ui.dialog = nil }.buttonStyle(.secondary)
                    Button(confirmLabel, action: confirm)
                        .buttonStyle(.primary)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, Space.s2)
            }
            .padding(Space.s4)
            .frame(maxWidth: 440)
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.surface).shadowLG())
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Palette.divider, lineWidth: 1))
            .padding(Space.s4)
        }
        .onAppear {
            if case .renameFolder(let id) = kind { name = store.library.folderName(id) }
            focused = true
        }
    }

    private func confirm() {
        switch kind {
        case .newTag:
            var created: String?
            store.mutate { created = $0.createTag(name) }
            guard let created else { return }
            ui.dialog = nil
            ui.showToast("已建立 #\(created)")
        case .renameFolder(let id):
            var renamed = false
            store.mutate { renamed = $0.renameFolder(id, to: name) }
            guard renamed else {
                ui.showToast("已經有同名的資料夾")
                return
            }
            ui.dialog = nil
            ui.showToast("已重新命名為「\(store.library.folderName(id))」")
        case .newFolder(let moveAfter):
            var folder: Folder?
            store.mutate { folder = $0.createFolder(named: name) }
            guard let folder else { return }
            ui.dialog = nil
            if moveAfter {
                let ids = ui.sheetTargets
                let batch = ui.sheetContext == .batch
                store.mutate { $0.move(ids, to: folder.id) }
                ui.dismissSheet()
                if batch { ui.endSelecting() }
                ui.showToast((batch ? "\(ids.count) 張已" : "已") + "移到「\(folder.name)」")
            } else {
                ui.showToast("已建立資料夾「\(folder.name)」")
            }
        }
    }
}

extension View {
    /// `.input`: hairline-bordered field, accent border on focus.
    func classicalInput(minHeight: CGFloat = 36, fontSize: CGFloat = 14, focused: Bool = false, leadingInset: CGFloat = 10) -> some View {
        self
            .font(Typeface.body(fontSize))
            .tint(Palette.accent)
            .padding(.leading, leadingInset)
            .padding(.trailing, 10)
            .frame(minHeight: minHeight)
            .background(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(focused ? Palette.accent : Palette.divider, lineWidth: 1))
    }
}
