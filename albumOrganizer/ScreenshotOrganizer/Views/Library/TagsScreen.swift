import SwiftUI
import ScreenshotKit

struct TagsScreen: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui
    @State private var editing = false

    var body: some View {
        let lib = store.library
        let features = lib.presentFeatureTags
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(kicker: "\(features.count + lib.tags.count) 個標籤", title: "標籤") {
                    HStack(spacing: 4) {
                        Button(editing ? "完成" : "編輯") { editing.toggle() }
                            .buttonStyle(.ghost)
                            .disabled(lib.tags.isEmpty && !editing)
                        Button { ui.dialog = .newTag } label: {
                            Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                            Text("新增")
                        }
                        .buttonStyle(.primary)
                    }
                }

                if !features.isEmpty {
                    AutoLabel().padding(.top, 16)
                    ForEach(features, id: \.self) { feature in
                        TagRow(title: feature.displayName, icon: "sparkles", count: lib.count(in: .feature(feature)),
                               route: .feature(feature), onDelete: nil)
                    }
                }

                if !lib.tags.isEmpty {
                    Text("我的標籤")
                        .font(Typeface.body(12))
                        .tracking(0.72)
                        .foregroundStyle(Palette.neutral700)
                        .padding(.top, features.isEmpty ? 0 : 24)
                }
                ForEach(lib.tags, id: \.self) { tag in
                    TagRow(title: tag, icon: "number", count: lib.count(in: .tag(tag)), route: .tag(tag),
                           onDelete: editing ? { delete(tag) } : nil)
                }

                if lib.tags.isEmpty && features.isEmpty {
                    Text("還沒有標籤。按「新增」建立，或等文字辨識完成後，含連結、電話、地址等的截圖會自動加上標籤。")
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

    private func delete(_ tag: String) {
        store.mutate { $0.deleteTag(tag) }
        if ui.chip == .tag(tag) { ui.chip = .all }
        ui.showToast("已刪除 #\(tag)")
    }
}

private struct TagRow: View {
    let title: String
    let icon: String
    let count: Int
    let route: UIState.Route
    /// Set while editing a deletable tag; the row then shows a delete button instead of navigating.
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let onDelete {
                    label
                    Button(action: onDelete) {
                        Image(systemName: "trash").font(.system(size: 17))
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("刪除標籤")
                } else {
                    NavigationLink(value: route) {
                        HStack(spacing: 12) {
                            label
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Palette.neutral500)
                        }
                        .foregroundStyle(Palette.text)
                    }
                    .buttonStyle(.pressable)
                }
            }
            Hairline()
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.accent800)
                .frame(width: 28, height: 28)
                .background(Palette.accent100)
            Text(title).font(Typeface.body(17)).lineLimit(1)
            Spacer(minLength: 0)
            Text("\(count)").font(Typeface.body(14)).foregroundStyle(Palette.neutral700).monospacedDigit()
        }
        .padding(.vertical, 14)
    }
}
