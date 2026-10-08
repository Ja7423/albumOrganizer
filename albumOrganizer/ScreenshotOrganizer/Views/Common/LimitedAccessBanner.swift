import SwiftUI
import UIKit

/// Shown when the user granted access to selected photos only: the app still works on what it can see.
struct LimitedAccessBanner: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        if store.isLimitedAccess {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("只整理你選取的截圖").font(Typeface.head(17))
                Text("目前只能讀取部分照片。選取更多截圖，或在「設定」改成「完整取用」，就能整理所有截圖。")
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.neutral700)
                HStack(spacing: 8) {
                    Button("選取更多截圖", action: pickMore).buttonStyle(.primary)
                    Button("前往設定") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.divider, lineWidth: 1))
            .padding(.top, 12)
        }
    }

    private func pickMore() {
        guard let controller = Self.topViewController() else { return }
        store.presentLimitedLibraryPicker(from: controller)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
