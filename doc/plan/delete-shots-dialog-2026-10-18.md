# Feature Plan：刪除截圖對話框

| 項目 | 內容 |
|------|------|
| 規劃日期 | 2026-10-18 |
| 規劃方式 | grilling（2 輪） |
| 目前分支 | `main`（base `main`） |
| 狀態 | 已確認 |
| 設計稿 | https://claude.ai/artifact/9L2X17ePxVGsWK3jLkaSnM（選取截圖 → 點垃圾桶） |

## 需求摘要

批次列與詳細頁的垃圾桶改成先跳「刪除截圖」對話框，讓使用者選擇「連同相簿一起刪除」（刪除「照片」原檔，移到「最近刪除」）或「只從 App 移除」（現有的 `hide`），並可勾選「記住這個選擇」。記住的選擇在新的「設定」sheet 裡可以改回「每次詢問」或直接改成另一種。

### 範圍

- **In scope**：批次列與詳細頁的刪除流程、`DeleteShotsDialog`、刪除偏好的保存與設定入口、刪除 Photos 原檔、相關 spec / README 更新、ScreenshotKit 單元測試。
- **Out of scope**：資料夾與標籤的刪除（維持立即刪除）、復原（交給「照片」的「最近刪除」）、繞過 iOS 系統確認 alert（無法做到）。

## 決策紀錄

| # | 決策 | 選擇 | 理由 / 被放棄的選項 |
|---|------|------|------|
| D1 | iOS 系統確認 | 接受「App 對話框 → 系統 alert」兩層確認 | `PHAssetChangeRequest.deleteAssets` 一定會跳系統 alert，無法關閉；放棄「只做 App 移除」 |
| D2 | 系統 alert 取消 / 失敗 | 什麼都不移除；批次保留選取模式與選取、詳細頁留在原張；這次的「記住」不寫入 | 取消後不應改做另一個破壞性動作；放棄「改成只從 App 移除」 |
| D3 | 記住選擇的保存 | `UserDefaults`（key `deletionPreference`），批次與詳細頁共用 | 使用者指定 |
| D4 | 修改入口 | 原本的 `.settings` sheet 改名「設定」，分「iCloud 備份」與「刪除截圖」兩區；刪除區為三選一列表（每次詢問 / 連同相簿一起刪除 / 只從 App 移除） | 使用者指定；放棄「另開 sheet」與「只有重設按鈕」 |
| D5 | 設定入口圖示 | 資料夾 tab 右上角 `icloud.and.arrow.up` → `gearshape`，accessibilityLabel「設定」 | 不增加按鈕數 |
| D6 | 詳細頁 | header 右邊「分享」旁加 `trash` icon 按鈕，共用同一個對話框 | 使用者指定 |
| D7 | 詳細頁刪除後 | 沿用 `ShotDetailScreen` 既有的 `replaceMissingDetail`（下一張 → 上一張 → 關閉） | 重用既有行為 |
| D8 | 對話框實作 | `UIState.Dialog.deleteShots(SheetContext)` + `DeleteShotsDialog`，樣式比照 `NameDialog`，zIndex 45 | 符合設計稿與既有 dialog 模式；放棄系統 `.confirmationDialog` |
| D9 | 文案 | 照設計稿；詳細頁標題「刪除這張截圖」、toast「已刪除這張（含相簿原檔）」「已從 App 移除這張（相簿原檔保留）」；有勾記住時加「・已記住此選擇」 | 使用者確認 |
| D10 | 失敗與取消的 toast | 取消：「已取消，原檔未刪除」；其他錯誤：「無法刪除原檔，請稍後再試」 | 預設值（可推翻）：真正的錯誤不該被說成使用者取消 |
| D11 | 刪除原檔後的 Library 更新 | 成功後立即 `syncWithPhotos()`，由 `Library.sync` 把消失的截圖拿掉；不寫進 `hiddenShotIDs` | 預設值：資產已不存在，記成「隱藏」沒有意義；Photos change observer 之後再同步一次也是冪等的 |
| D12 | 偏好與文案放哪 | 純值型別 `DeletionMethod` / `DeletionPreference` 與文案組字放在 ScreenshotKit（`ShotDeletion.swift`）；保存放 App target 的 `DeletionSettings` | 預設值：App target 沒有測試 target，純邏輯放 package 才能 `swift test`（比照 `RecentSearches`） |
| D13 | `UIState.Dialog` 結構 | 拆成 `.name(NameDialogKind)` 與 `.deleteShots(SheetContext)` | 實作時決定：避免 `NameDialog` 的 switch 處理不屬於它的 case；`AppShell` 依 case 分派 |

## 現況分析

- **最相似的既有功能**：
  - 對話框：`Views/Shell/Sheets.swift` 的 `NameDialog`（遮罩、卡片、`ClassicalButtonStyle`）與 `UIState.Dialog`
  - 批次 / 詳細兩種 context：`UIState.SheetContext` 與 `sheetTargets`（移到資料夾、標籤 sheet 都用）
  - 保存在 `UserDefaults` 的小偏好：`RecentSearches`（ScreenshotKit 純值型別）+ `SearchScreen` 讀寫；`BackupService` 以建構子注入 `UserDefaults`
- **可重用**：
  - `Library.hide(_:)`（只從 App 移除）
  - `LibraryStore.syncWithPhotos()`、`UIState.replaceMissingDetail(in:)`
  - `MoveSheetContent.row(...)` 的列樣式 → 抽成共用的 `SheetRow`，移到資料夾 sheet 與刪除偏好列表共用
  - `ClassicalButtonStyle(kind:fullWidth:)`、`IconButtonStyle`、`Hairline`、`Kicker`
- **需新增的資料來源**：`PhotoLibraryService.deleteAssets(_:)`（`PHPhotoLibrary.performChanges` + `PHAssetChangeRequest.deleteAssets`）；權限已是 `.readWrite`
- **會被影響的既有程式碼**：`AppShell.swift`（`BatchBar`、dialog host）、`ShotDetailScreen.swift`（header）、`Sheets.swift`（settings 標題、row 抽出）、`FoldersScreen.swift`（入口圖示）、`UIState.swift`、`LibraryStore.swift`、`ScreenshotOrganizerApp.swift`（注入 `DeletionSettings`）

## 架構設計

```
BatchBar / ShotDetailScreen.header ──▶ ShotDeletion.request(context)
                                          │ preference = .always(method) → perform
                                          │ preference = .ask            → ui.dialog = .deleteShots(context)
DeleteShotsDialog ───────────────────▶ ShotDeletion.perform(method, context, remember)
                                          ├─ LibraryStore.delete(ids, method) ─┬─ .removeFromApp    → Library.hide
                                          │                                    └─ .deleteFromPhotos → PhotoLibraryService.deleteAssets → syncWithPhotos
                                          ├─ DeletionSettings.preference（記住時）
                                          └─ UIState（結束選取、toast）
DeletePreferenceSection（設定 sheet）──▶ DeletionSettings.preference
ScreenshotKit：DeletionMethod / DeletionPreference / DeletionCopy（純值、純函式）
```

- **ScreenshotKit**：只有值與文案組字，不碰 Photos / UserDefaults。
- **PhotoLibraryService**：唯一呼叫 Photos 寫入 API 的地方，丟出錯誤，不決定 UI。
- **LibraryStore.delete**：把「刪除方式」轉成 Library 變更或 Photos 刪除，回傳 `DeletionOutcome`，不碰 UI。
- **DeletionSettings**：`@Observable`，只負責讀寫偏好（注入 `UserDefaults`）。
- **ShotDeletion**：View 層的流程協調（問 / 不問、結果 → toast、結束選取），由 view 從 environment 組出來，不持有狀態。
- **DeleteShotsDialog / DeletePreferenceSection**：純呈現。

### 替代方案

| 方案 | 優點 | 缺點 | 結論 |
|------|------|------|------|
| 偏好放在 `UIState` | 少一個型別 | `UIState` 是暫時性 UI 狀態，混進持久化偏好違反單一職責 | 不採用 |
| 流程寫在 `LibraryStore` | 少一個型別 | Store 要依賴 `UIState` 與 toast 文案，跨層 | 不採用 |

## 檔案變更清單

| 動作 | 檔案 | 層 | 職責 |
|------|------|----|------|
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/ShotDeletion.swift` | Domain | `DeletionMethod`、`DeletionPreference`（含儲存值轉換）、`DeletionCopy`（標題 / toast 純函式） |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/ShotDeletionTests.swift` | Test | 偏好儲存值往返、文案 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Services/PhotoLibraryService.swift` | Service | `deleteAssets(_:)`；更新「唯讀」註解 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Store/LibraryStore.swift` | Store | `DeletionOutcome`、`delete(_:method:) async` |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Store/DeletionSettings.swift` | Store | `@Observable` 偏好保存 |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Store/ShotDeletion.swift` | Store（UI 流程） | `request` / `perform` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Store/UIState.swift` | Store | `Dialog` 拆成 `.name(NameDialogKind)` / `.deleteShots(SheetContext)`、`targets(for:)`（`sheetTargets` 改用它） |
| 修改 | `Views/Library/TagsScreen.swift`、`Views/Library/FoldersScreen.swift`、`Views/Shell/Sheets.swift` | View | 命名對話框改用 `.name(…)` 開啟 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Settings/BackupSection.swift` | View | 放進「設定」sheet 的第一區；原副標「備份只存在你自己的 iCloud」併入說明文字 |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Views/Shell/DeleteShotsDialog.swift` | View | 對話框 |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Views/Settings/DeletePreferenceSection.swift` | View | 設定 sheet 的刪除區 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Shell/AppShell.swift` | View | `BatchBar` 垃圾桶走 `ShotDeletion`；dialog host 分派 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Shell/Sheets.swift` | View | settings 標題「設定」、兩區內容；抽出 `SheetRow` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Detail/ShotDetailScreen.swift` | View | header 垃圾桶 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Library/FoldersScreen.swift` | View | 入口改 `gearshape`「設定」 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/App/ScreenshotOrganizerApp.swift` | App | 注入 `DeletionSettings` |
| 修改 | `doc/README.md`、`doc/spec/tab-screenshots.md`、`doc/spec/shared-detail-and-sheets.md`、`doc/spec/tab-folders.md`、`doc/spec/tab-search.md`（若提到） | Doc | 與行為一致 |

## 介面草案

```swift
// ScreenshotKit/ShotDeletion.swift
public enum DeletionMethod: String, CaseIterable, Sendable {
    case deleteFromPhotos
    case removeFromApp
}

public enum DeletionPreference: Equatable, Sendable {
    case ask
    case always(DeletionMethod)

    public init(storedValue: String?)      // nil / 未知值 → .ask
    public var storedValue: String?        // .ask → nil
    public var method: DeletionMethod?
}

/// 批次（N 張）或詳細頁目前這張。
public enum DeletionSubject: Equatable, Sendable {
    case selection(count: Int)
    case current
}

public enum DeletionCopy {
    public static func title(for subject: DeletionSubject) -> String
    public static func summary(_ method: DeletionMethod, subject: DeletionSubject, isRemembered: Bool) -> String
    public static let cancelled: String
    public static let failed: String
}

// PhotoLibraryService
func deleteAssets(_ ids: [String]) async throws

// LibraryStore
enum DeletionOutcome: Equatable { case deleted, cancelled, failed }
func delete(_ ids: [String], method: DeletionMethod) async -> DeletionOutcome

// DeletionSettings
@MainActor @Observable final class DeletionSettings {
    init(defaults: UserDefaults = .standard)
    var preference: DeletionPreference   // didSet 寫回 UserDefaults
}

// ShotDeletion
@MainActor struct ShotDeletion {
    let store: LibraryStore; let ui: UIState; let settings: DeletionSettings
    func request(for context: UIState.SheetContext)
    func perform(_ method: DeletionMethod, for context: UIState.SheetContext, remembering: Bool) async
}

// UIState
enum Dialog { …; case deleteShots(SheetContext) }
func targets(for context: SheetContext) -> [String]
```

## 規則檢核（pre-review）

| 規則 | 設計對策 | 殘留風險 |
|------|----------|----------|
| 1. 框架慣例 | 對話框比照 `NameDialog` 並由 `AppShell` 以 `ui.dialog` 顯示；偏好比照 `RecentSearches`（純值在 ScreenshotKit）+ `BackupService`（注入 `UserDefaults`）；新檔案放進既有的 Store / Views/Shell / Views/Settings 目錄；顏色字型用 `Palette` / `Typeface` | 專案沒有 l10n，字串維持直接寫中文（與既有一致） |
| 2. 架構可擴充性 | 新增刪除方式只需在 `DeletionMethod` 加 case 並補 `DeletionCopy` 與 `LibraryStore.delete` 的分支；新入口（例如搜尋結果）只要呼叫 `ShotDeletion.request(for:)` | 無 |
| 3. 副作用 / Pure Function | 文案、偏好儲存值轉換是純函式；Photos I/O 只在 `PhotoLibraryService.deleteAssets`；`UserDefaults` 寫入只在 `DeletionSettings` | 無 |
| 4. 重複程式碼 | 抽出 `SheetRow` 給移到資料夾與刪除偏好共用；`sheetTargets` 改用 `targets(for:)`；批次與詳細頁共用同一個 `ShotDeletion` 與對話框 | 無 |
| 5. 命名 | `DeletionMethod.deleteFromPhotos / removeFromApp` 對應按鈕語意；`request`（可能問）vs `perform`（直接做）；`DeletionOutcome.deleted/cancelled/failed` | 無 |
| 6. 巢狀與複雜度 | `perform` 以 `switch outcome` + guard 拆開；toast 組字交給 `DeletionCopy`；對話框按鈕列抽成子 view | 無 |
| 7. SOLID | S：偏好 / 流程 / 呈現 / Photos I/O 各一型別；D：`DeletionSettings` 注入 `UserDefaults`、`LibraryStore` 既有注入 `PhotoLibraryService`；I：`ShotDeletion` 只暴露兩個方法 | 無 |

## 實作步驟

1. **ScreenshotKit 值型別與文案** — 動到：`ShotDeletion.swift`、`ShotDeletionTests.swift`；驗證：`swift test --package-path Packages/ScreenshotKit --filter ShotDeletionTests`
2. **Photos 刪除與 Store** — 動到：`PhotoLibraryService.swift`、`LibraryStore.swift`、`DeletionSettings.swift`；驗證：`xcodebuild build`
3. **UI 狀態與流程** — 動到：`UIState.swift`、`ShotDeletion.swift`（App）、`ScreenshotOrganizerApp.swift`
4. **對話框與入口** — 動到：`DeleteShotsDialog.swift`、`AppShell.swift`、`ShotDetailScreen.swift`
5. **設定 sheet** — 動到：`Sheets.swift`、`DeletePreferenceSection.swift`、`FoldersScreen.swift`
6. **文件** — README 與 spec
7. **驗證** — swiftformat、`xcodebuild build`、模擬器手動走過：批次 / 詳細頁 × 兩種方式 × 記住 / 不記住、系統 alert 取消、設定切換

## 測試計畫

- Unit（ScreenshotKit）：
  - `DeletionPreference(storedValue:)` 與 `storedValue` 往返；nil 與未知值 → `.ask`
  - `DeletionCopy.title`：批次 N 張 / 目前這張
  - `DeletionCopy.summary`：兩種方式 × 兩種 subject × 是否記住
- 手動（模擬器）：上面第 7 步的組合；有限存取（limited）時刪除可見的截圖

## 風險與未決問題

- ⚠️ 系統 alert 每次都會出現，就算記住了「連同相簿一起刪除」也一樣（D1，iOS 限制）。
- ⚠️ `PHPhotosError.userCancelled` 是判斷「取消」的依據；其他錯誤一律當作失敗。
- ⚠️ README 原本寫「相簿原檔永遠不會被移動或修改」，改成「只有在使用者選擇『連同相簿一起刪除』時才會刪除原檔」。

## 修訂紀錄

| 版本 | 日期 | 變更 |
|------|------|------|
| v1 | 2026-10-18 | 初版 |
| v2 | 2026-10-18 | 實作完成：補 D13（`Dialog` 拆分）與檔案清單；同步更新 README、storage.md 與四份 spec |
