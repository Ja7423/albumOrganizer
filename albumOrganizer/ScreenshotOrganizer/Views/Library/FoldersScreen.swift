import SwiftUI
import ScreenshotKit

struct FoldersScreen: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        let lib = store.library
        ScrollView {
            VStack(spacing: 0) {
                ScreenHeader(kicker: "\(lib.folders.count) 個資料夾", title: "資料夾") {
                    Button { ui.dialog = .newFolder(moveAfter: false) } label: {
                        Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                        Text("新增")
                    }
                    .buttonStyle(.primary)
                }

                LimitedAccessBanner()

                let processing = lib.shots(in: .processing)
                if !processing.isEmpty {
                    FolderRow(name: "處理中", shots: processing, route: .processing, icon: "hourglass")
                }
                FolderRow(name: Library.unsortedName, shots: lib.shots(in: .unsorted), route: .unsorted, icon: "tray")
                ForEach(lib.folders) { folder in
                    let shots = lib.shots(in: .folder(folder.id))
                    FolderRow(name: folder.name, shots: shots, route: .folder(folder.id),
                              isDimmed: shots.isEmpty && folder.builtIn != nil)
                        .contextMenu {
                            Button {
                                ui.dialog = .renameFolder(folder.id)
                            } label: {
                                Label("重新命名", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                store.deleteFolder(folder.id)
                                ui.showToast("已刪除資料夾「\(folder.name)」，自動分類的截圖會重新分類")
                            } label: {
                                Label("刪除資料夾", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(Palette.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct FolderRow: View {
    let name: String
    let shots: [Shot]
    let route: UIState.Route
    var icon = "folder"
    /// Empty built-in folders stay listed so screenshots can be moved in, but recede.
    var isDimmed = false

    var body: some View {
        NavigationLink(value: route) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Group {
                        if let cover = shots.first {
                            AssetImage(id: cover.id, targetSize: CGSize(width: 52, height: 52), alignment: .top)
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: 21))
                                .foregroundStyle(Palette.neutral600)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Palette.neutral300)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipped()

                    VStack(alignment: .leading, spacing: 0) {
                        Text(name).font(Typeface.body(17, .semibold)).lineLimit(1)
                        Text("\(shots.count) 張").font(Typeface.body(13)).foregroundStyle(Palette.neutral700)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.neutral500)
                }
                .padding(.vertical, 12)
                Hairline()
            }
            .foregroundStyle(Palette.text)
            .opacity(isDimmed ? 0.5 : 1)
        }
        .buttonStyle(.pressable)
    }
}
