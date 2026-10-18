import ScreenshotKit
import SwiftUI

/// `.dialog` for 刪除截圖: delete the originals too, or remove from the app only, optionally remembered.
struct DeleteShotsDialog: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(DeletionSettings.self) private var settings
    let context: UIState.SheetContext
    @State private var isRemembering = false

    private var subject: DeletionSubject {
        context == .batch ? .selection(count: ui.selection.count) : .current
    }

    var body: some View {
        ZStack {
            Palette.neutral900.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { ui.dialog = nil }

            VStack(alignment: .leading, spacing: 14) {
                Text(DeletionCopy.title(for: subject)).font(Typeface.head(20))
                Text("要連同「照片」相簿中的原檔一起刪除嗎？刪除的原檔會移到「最近刪除」，30 天內可復原。")
                    .font(Typeface.body(14))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                rememberToggle
                actions
            }
            .padding(Space.s4)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Palette.surface).shadowLG())
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Palette.divider, lineWidth: 1))
            .padding(Space.s4)
        }
    }

    private var rememberToggle: some View {
        Button { isRemembering.toggle() } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isRemembering ? Palette.accent100 : .clear)
                    .strokeBorder(isRemembering ? Palette.accent : Palette.neutral500, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                    .overlay {
                        if isRemembering {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.accent800)
                        }
                    }
                Text("記住這個選擇，以後不再詢問").font(Typeface.body(14))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isRemembering ? .isSelected : [])
    }

    private var actions: some View {
        VStack(spacing: Space.s2) {
            Button { delete(.deleteFromPhotos) } label: {
                Group {
                    Image(systemName: "trash").font(.system(size: 15))
                    Text(DeletionCopy.label(.deleteFromPhotos))
                }
                .foregroundStyle(Palette.accent800)
            }
            .buttonStyle(ClassicalButtonStyle(kind: .primary, fullWidth: true))

            Button(DeletionCopy.label(.removeFromApp)) { delete(.removeFromApp) }
                .buttonStyle(ClassicalButtonStyle(kind: .secondary, fullWidth: true))

            Button("取消") { ui.dialog = nil }
                .buttonStyle(ClassicalButtonStyle(kind: .ghost, fullWidth: true))
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Hairline() }
    }

    /// Closes the dialog first so the Photos confirmation alert is the only thing on screen.
    private func delete(_ method: DeletionMethod) {
        let deletion = ShotDeletion(store: store, ui: ui, settings: settings)
        let remembering = isRemembering
        ui.dialog = nil
        Task { await deletion.perform(method, for: context, remembering: remembering) }
    }
}
