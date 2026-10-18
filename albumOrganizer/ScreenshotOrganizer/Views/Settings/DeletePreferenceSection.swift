import ScreenshotKit
import SwiftUI

/// 設定 › 刪除截圖: what the trash button does, the same choice the delete dialog can remember.
struct DeletePreferenceSection: View {
    @Environment(DeletionSettings.self) private var settings

    private let choices: [(DeletionPreference, String, String)] = [
        (.ask, "每次詢問", "questionmark.circle"),
        (.always(.deleteFromPhotos), DeletionCopy.label(.deleteFromPhotos), "trash"),
        (.always(.removeFromApp), DeletionCopy.label(.removeFromApp), "rectangle.portrait.slash"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("點垃圾桶時要做什麼。選「連同相簿一起刪除」時，「照片」仍會請你再確認一次。")
                .font(Typeface.body(12))
                .foregroundStyle(Palette.neutral700)
                .lineSpacing(2)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(choices, id: \.1) { choice in
                SheetRow(name: choice.1, icon: choice.2, isCurrent: settings.preference == choice.0) {
                    settings.preference = choice.0
                }
            }
        }
    }
}
