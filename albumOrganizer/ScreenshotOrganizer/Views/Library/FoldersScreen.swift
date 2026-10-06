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

                FolderRow(name: Library.unsortedName, shots: lib.shots(in: .unsorted), route: .unsorted)
                ForEach(lib.folders) { folder in
                    FolderRow(name: folder.name, shots: lib.shots(in: .folder(folder.id)), route: .folder(folder.id))
                        .contextMenu {
                            Button(role: .destructive) {
                                store.mutate { $0.deleteFolder(folder.id) }
                                ui.showToast("已刪除資料夾「\(folder.name)」，截圖移到未分類")
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

    var body: some View {
        NavigationLink(value: route) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Group {
                        if let cover = shots.first {
                            AssetImage(id: cover.id, targetSize: CGSize(width: 52, height: 52), alignment: .top)
                        } else {
                            Image(systemName: "folder")
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
        }
        .buttonStyle(.pressable)
    }
}
