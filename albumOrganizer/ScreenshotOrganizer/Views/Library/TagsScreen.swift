import SwiftUI
import ScreenshotKit

struct TagsScreen: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui
    @State private var editing = false

    var body: some View {
        let lib = store.library
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(kicker: "\(lib.tags.count) 個標籤", title: "標籤") {
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

                let suggested = lib.count(in: .suggested)
                if suggested > 0 {
                    SuggestionCard(count: suggested, names: lib.suggestedTagNames)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }

                ForEach(lib.tags, id: \.self) { tag in
                    TagRow(tag: tag, count: lib.count(in: .tag(tag)), editing: editing) {
                        store.mutate { $0.deleteTag(tag) }
                        if ui.chip == .tag(tag) { ui.chip = .all }
                        ui.showToast("已刪除 #\(tag)")
                    }
                }

                if lib.tags.isEmpty && suggested == 0 {
                    Text("還沒有標籤。按「新增」建立，或等文字辨識完成後套用自動建議。")
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
}

/// `.card` announcing pending auto-suggestions.
private struct SuggestionCard: View {
    let count: Int
    let names: [String]
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 11))
                Text("自動建議")
            }
            .font(Typeface.body(10))
            .tracking(1)
            .foregroundStyle(Palette.accent)

            Text("\(count) 張截圖有建議標籤").font(Typeface.head(17))
            Text("依截圖中的文字判斷，確認後才會套用。")
                .font(Typeface.body(13))
                .opacity(0.8)

            FlowLayout {
                ForEach(names, id: \.self) { TagChip(text: $0, style: .outline, size: .small) }
            }

            HStack(spacing: 8) {
                Button("全部套用") {
                    var n = 0
                    store.mutate { n = $0.applyAllSuggestions() }
                    ui.showToast("已套用到 \(n) 張截圖")
                }
                .buttonStyle(.primary)
                Button("逐張確認") {
                    ui.selectTab(.all)
                    ui.chip = .suggested
                }
                .buttonStyle(.secondary)
            }
            .padding(.top, 6)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.divider, lineWidth: 1))
    }
}

private struct TagRow: View {
    let tag: String
    let count: Int
    let editing: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if editing {
                    label
                    Button(action: onDelete) {
                        Image(systemName: "trash").font(.system(size: 17))
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("刪除標籤")
                } else {
                    NavigationLink(value: UIState.Route.tag(tag)) {
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
            Image(systemName: "number")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.accent800)
                .frame(width: 28, height: 28)
                .background(Palette.accent100)
            Text(tag).font(Typeface.body(17)).lineLimit(1)
            Spacer(minLength: 0)
            Text("\(count)").font(Typeface.body(14)).foregroundStyle(Palette.neutral700).monospacedDigit()
        }
        .padding(.vertical, 14)
    }
}
