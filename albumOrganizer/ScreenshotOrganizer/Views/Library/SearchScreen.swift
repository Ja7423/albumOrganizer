import ScreenshotKit
import SwiftUI

struct SearchScreen: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui
    @State private var query = ""
    @FocusState private var focused: Bool

    private let examples = ["密碼", "訂單編號", "地址", "發票"]

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("搜尋")
                    .font(Typeface.head(34))
                    .padding(.top, 42)
                    .padding(.bottom, 12)

                field

                if q.isEmpty {
                    Kicker("試試搜尋").padding(.top, 24)
                    FlowLayout {
                        ForEach(examples, id: \.self) { example in
                            Button { query = example } label: {
                                TagChip(text: example, style: .neutral, size: .regular, horizontalPadding: 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                    Text("每張截圖匯入時都會辨識文字，所以可以直接搜尋圖片裡的密碼、地址、訂單編號。")
                        .font(Typeface.body(14))
                        .foregroundStyle(Palette.neutral700)
                        .padding(.top, 24)
                } else {
                    let hits = store.library.search(q)
                    VStack(alignment: .leading, spacing: 0) {
                        Kicker("找到 \(hits.count) 張").padding(.bottom, 8)
                        Hairline()
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                    ForEach(hits) { hit in
                        if let shot = store.library.shot(hit.shotID) {
                            ResultRow(shot: shot, hit: hit, meta: meta(for: shot)) {
                                focused = false
                                ui.openDetail(shot.id)
                            }
                        }
                    }
                    if hits.isEmpty {
                        Text("沒有截圖包含「\(q)」。")
                            .font(Typeface.body(14))
                            .foregroundStyle(Palette.neutral700)
                            .padding(.vertical, 32)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.bg)
    }

    private var field: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17))
                .foregroundStyle(Palette.neutral600)
                .padding(.leading, 12)
            TextField("圖中文字或標籤", text: $query)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(Typeface.body(16))
                .padding(.leading, 8)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(IconButtonStyle())
                .padding(.trailing, 5)
                .accessibilityLabel("清除")
            }
        }
        .frame(minHeight: 46)
        .tint(Palette.accent)
        .background(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(focused ? Palette.accent : Palette.divider, lineWidth: 1))
    }

    private func meta(for shot: Shot) -> String {
        ([ShotFormat.shortDate(shot.createdAt)] + shot.tags.map { "#" + $0 }).joined(separator: " · ")
    }
}

private struct ResultRow: View {
    let shot: Shot
    let hit: SearchHit
    let meta: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    AssetImage(id: shot.id, targetSize: CGSize(width: 52, height: 72), alignment: .top)
                        .frame(width: 52, height: 72)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(shot.title).font(Typeface.body(15, .semibold)).lineLimit(1)
                        Text(meta).font(Typeface.body(12)).foregroundStyle(Palette.neutral700).lineLimit(1)
                        Text(snippet)
                            .font(Typeface.body(14))
                            .lineSpacing(2)
                            .lineLimit(3)
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                Hairline()
            }
            .foregroundStyle(Palette.text)
            .multilineTextAlignment(.leading)
        }
        .buttonStyle(.pressable)
    }

    private var snippet: AttributedString {
        var match = AttributedString(hit.match)
        match.backgroundColor = Palette.accent200
        match.foregroundColor = Palette.accent900
        return AttributedString(hit.prefix) + match + AttributedString(hit.suffix)
    }
}
