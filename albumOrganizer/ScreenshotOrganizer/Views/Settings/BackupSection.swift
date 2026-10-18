import SwiftUI

/// iCloud backup status and actions, in the 設定 sheet.
struct BackupSection: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        let backup = store.backup
        VStack(alignment: .leading, spacing: 0) {
            Text(statusLine(backup))
                .font(Typeface.body(15))
                .padding(.top, 8)
            if let error = backup.lastError {
                Text(error)
                    .font(Typeface.body(13))
                    .foregroundStyle(Palette.accent700)
                    .padding(.top, 4)
            }
            Text("備份只存在你自己的 iCloud，包含資料夾、標籤與分類，不含截圖本身與辨識出的文字。換手機時建議開啟「iCloud 照片」，截圖才能準確對回原本的分類。")
                .font(Typeface.body(12))
                .foregroundStyle(Palette.neutral700)
                .lineSpacing(2)
                .padding(.top, 8)

            if let found = backup.undecided {
                undecidedActions(found)
            } else if backup.account == .available || backup.account == nil {
                actions(backup)
            }
        }
        .task { if backup.account == nil { _ = await backup.checkForBackup() } }
    }

    private func statusLine(_ backup: BackupService) -> String {
        switch backup.activity {
        case .checking: return "正在檢查 iCloud…"
        case .backingUp: return "正在備份…"
        case .restoring: return "正在還原…"
        case .idle: break
        }
        switch backup.account {
        case .noAccount?: return "未登入 iCloud，無法備份"
        case .restricted?: return "iCloud 受到限制，無法備份"
        case .unknown?: return "目前無法連線到 iCloud"
        case .available?, nil: break
        }
        guard let last = backup.lastBackupAt else { return "尚未備份" }
        return "上次備份：\(last.formatted(date: .abbreviated, time: .shortened))"
    }

    private func actions(_ backup: BackupService) -> some View {
        HStack(spacing: 10) {
            Button("立即備份") { store.backUp() }
                .buttonStyle(.primary)
            Button("從備份還原") { restore() }
                .buttonStyle(.secondary)
        }
        .disabled(backup.activity != .idle || !backup.canUpload)
        .padding(.top, 16)
    }

    /// A backup exists that this device never restored or skipped; uploads wait until the user picks.
    private func undecidedActions(_ found: BackupService.Found) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iCloud 裡有一份 \(found.createdAt.formatted(date: .abbreviated, time: .shortened)) 的備份（\(found.shotCount) 張）。還原或略過之前，不會自動備份。")
                .font(Typeface.body(13))
            HStack(spacing: 10) {
                Button("還原") { restore() }
                    .buttonStyle(.primary)
                Button("略過，改用這台的資料") { store.skipBackupRestore() }
                    .buttonStyle(.secondary)
            }
        }
        .disabled(store.backup.activity != .idle)
        .padding(.top, 16)
    }

    private func restore() {
        Task {
            await store.restoreFromBackup()
            if store.backup.lastError == nil { ui.showToast("已從 iCloud 備份還原") }
        }
    }
}
