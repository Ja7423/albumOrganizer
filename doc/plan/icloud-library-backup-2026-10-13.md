# Feature Plan：iCloud 備份與還原 Library

| 項目 | 內容 |
|------|------|
| 規劃日期 | 2026-10-13 |
| 規劃方式 | grilling（3 輪，Q1–Q14） |
| 目前分支 | `main`（`221ec15`）；實作時另開 `feature/icloud-backup` |
| 狀態 | 已實作（`feature/icloud-backup`），待實機驗證 |

## 需求摘要

把使用者的整理結果（資料夾、標籤、手動與自動分類）備份到使用者自己的 iCloud。重裝 App 或換新 iPhone 後可以還原，不必重新分類。備份之後才出現的新截圖照常走分類流程。

成功的樣子：
- 同一台裝置刪掉 App 再重裝，onboarding 問「要還原嗎」，按下還原後所有資料夾、標籤、分類都回來，不會重新分類（分類器版本升級的情況除外，見 D13）。
- 換新 iPhone 時，iCloud 照片陸續下載進來，每下載一張就把它原本的分類套回去，不會被當成新截圖。
- 備份後才拍的截圖會進「處理中」，被正常分類。
- 任何時候都不會發生「空的 library 把雲端的好備份蓋掉」。

### 範圍

- **In scope**
  - CloudKit 私有資料庫的快照上傳與下載，雲端保留 2 份
  - 備份格式 `BackupSnapshot`：只放使用者決定和分類結果，不含 OCR
  - 跨裝置對應：`PHCloudIdentifier` 優先，對不上時用「拍攝時間＋像素尺寸」做唯一比對
  - `pendingRestore`：暫存對不上的資料，每次 Photos 有變動就重新比對，30 天後清除
  - onboarding 的還原詢問步驟
  - 設定頁的「備份」區塊：狀態、上次備份時間、立即備份、從備份還原（merge）
  - App 進背景時自動備份；還原決定做出來之前禁止上傳
- **Out of scope**
  - 多裝置即時同步（逐筆 CKRecord，見替代方案 A）
  - 備份 OCR 文字、barcode、learned model、最近搜尋
  - 非 iCloud 的後端（自建伺服器、Google Drive）
  - 讓使用者挑選要還原哪一份快照（第一版固定用最新的那份，最新的讀不到才退回舊的）

## 決策紀錄

| # | 決策 | 選擇 | 理由 / 被放棄的選項 |
|---|------|------|------|
| D1 | 還原情境 | 同一台裝置重裝＋換新 iPhone | 換手機是最需要還原的時候。被放棄：只支援同一台裝置（Q1） |
| D2 | 遠端位置 | CloudKit 私有資料庫 | 不需要帳號系統、免費、資料在使用者自己的 iCloud，entitlement 也已經開了。被放棄：iCloud Drive 檔案、自建後端（Q2） |
| D3 | 粒度 | 整份快照，用一個 `CKAsset` 上傳 | 需求是還原，不是同步，快照最簡單、沒有逐筆衝突。被放棄：逐筆同步（Q3） |
| D4 | 備份內容 | 使用者決定＋auto placement＋feature tags；不含 OCR、learned model、最近搜尋 | 體積小、不帶敏感文字，OCR 在本機重跑不影響分類（Q4、Q14） |
| D5 | 備份時機 | 進背景時自動＋手動「立即備份」，並顯示上次備份時間 | Q5 |
| D6 | 還原觸發 | onboarding 拿到權限後、`startImport()` 之前，偵測到備份就先詢問 | 使用者可能想從頭開始；restore 必須早於 import（Q6） |
| D7 | 新截圖與已刪除截圖 | 還原之後跑 `sync(with:)`：新的設成 pending 並立刻分類，不等 learned model；Photos 已經沒有的就丟掉 | 沿用現有行為（Q7） |
| D8 | 對不上的資料 | 放進 `pendingRestore`，Photos 有變動就重新比對，30 天後清除 | 換手機時 iCloud 照片還沒下載完是常態（Q8） |
| D9 | 覆蓋保護 | 還原決定前禁止上傳；`pendingRestore` 要寫進下一次快照；雲端保留 2 份 | Q9 |
| D10 | 事後還原 | 設定頁提供「從備份還原」並 merge。優先順序：本機 user > 備份 user > 備份 auto > 本機 auto 或 pending；資料夾、標籤取聯集 | 第一版就做（Q10） |
| D11 | iCloud 不可用 | onboarding 靜默略過，設定頁顯示狀態 | Q11 |
| D12 | fallback 比對 | 只有唯一符合時才套用，多張符合就當成新截圖 | 分錯資料夾比重新分類糟糕（Q12） |
| D13 | 分類器版本升級 | 還原回來的 auto placement 照 `requeueOutdated` 規則重新分類 | 跟沒重裝時升級 App 的行為一致（Q13） |
| D14 | 快照的 record 命名 | 固定兩個 record name：`snapshot-0`、`snapshot-1`，輪流覆寫，用 `CKFetchRecordsOperation` 依 ID 取回 | 不需要在 CloudKit Dashboard 建 queryable index，也不用做 query。**預設值（可推翻）** |
| D15 | `pendingRestore` 存在哪裡 | 獨立的 `Application Support/pending-restore.json`，不放進 `Library` 和 SQLite | 這是暫時性、會過期的資料，不該擴大 `Library` 和 SQLite 的 schema；用完就整個刪掉。**預設值（可推翻）** |
| D16 | 設定頁入口 | 既有 `SheetHost` 新增 `.settings` sheet，內容是 `BackupSection`；從「資料夾」tab 標題列右上角的齒輪按鈕開啟 | App 目前沒有設定頁，沿用既有 sheet 機制比新開一套一致。**預設值（可推翻）** |
| D17 | 既有使用者 | 已經完成 onboarding 的使用者（升級 App 而不是重裝）直接視為「已做出還原決定」，可以馬上備份 | 他們本機就有資料，沒有覆蓋的風險。**預設值** |
| D19 | 上傳閘門遇到失敗 | 檢查逾時、網路失敗、還原失敗都**不**打開上傳；設定頁顯示「還有一份備份尚未處理」讓使用者選擇 | 只有確定不會蓋掉備份時才上傳（實作時新增） |
| D20 | 資料夾對應 | id → 內建分類 → 同名的自訂資料夾 → 新增 | 兩台裝置各自建了同名資料夾時，視為同一個（實作時新增） |
| D18 | 雲端快照讀不到 | 最新那份解碼失敗（壞檔或 `newerSchema`）就改用另一份；兩份都不行時當成「沒有備份」，並在設定頁顯示原因 | 保留 2 份就是為了這個情況。**預設值** |

## 現況分析

- **最相似的既有功能**
  - `LearnedModelUpdater`（[LearnedModelUpdater.swift](../../albumOrganizer/ScreenshotOrganizer/Services/LearnedModelUpdater.swift)）：App 層的 `@MainActor` service，I/O 在背景執行，結果透過 callback 交回 store。新的 `BackupService` 比照它的結構。
  - `LibraryPersisting` 與 `SQLiteLibraryDatabase`：用協定隔開 I/O，`LibraryStore` 由 init 注入。`BackupRemote` 比照這個做法。
  - `LibraryCodec`（[LibraryCodec.swift](../../Packages/ScreenshotKit/Sources/ScreenshotKit/LibraryCodec.swift)）：`schemaVersion`、`newerSchema` 拒讀、`decodeKnownValue(s)` 容錯解碼。`BackupCodec` 照抄這個模式。
- **可重用**
  - `Folder`、`Placement`、`AutoPlacement`、`FeatureTag`、`BuiltInCategory` 本身都是 `Codable`，直接放進快照。
  - `KeyedDecodingContainer.decodeKnownValues` 和 `decodeKnownValue`，用來容錯解碼 feature tags 和內建分類。
  - `AssetInfo`（[Models.swift:228](../../Packages/ScreenshotKit/Sources/ScreenshotKit/Models.swift:228)）：比對用的 `createdAt`、`pixelWidth`、`pixelHeight` 已經在裡面。
  - `Library.sync(with:)`（[Library.swift:143](../../Packages/ScreenshotKit/Sources/ScreenshotKit/Library.swift:143)）：還原後的新增與刪除完全交給它處理。
  - `Library.requeueOutdated(version:)`（[Library+Classification.swift:70](../../Packages/ScreenshotKit/Sources/ScreenshotKit/Library+Classification.swift:70)）：還原後重新呼叫一次（D13）。
  - `LibraryStore.mutate`、`saveNow`、`learning.update(for:)`、`processor.start()`：還原套用後照原本的流程存檔、重新訓練、分類。
- **需新增的資料來源**
  - CloudKit 私有資料庫，record type `LibrarySnapshot`，欄位：`payload`（CKAsset）、`createdAt`、`schemaVersion`、`shotCount`。
  - `PHPhotoLibrary.cloudIdentifierMappings(forLocalIdentifiers:)` 和 `localIdentifierMappings(for:)`。
- **會被影響的既有程式碼**
  - [albumOrganizer.entitlements](../../albumOrganizer/albumOrganizer.entitlements)：`icloud-container-identifiers` 目前是空陣列，要填入 `iCloud.<bundle id>`。
  - [LibraryStore.swift](../../albumOrganizer/ScreenshotOrganizer/Store/LibraryStore.swift)：`Phase` 新增 `.restoreOffer`；`requestAccess()` 分流；`syncWithPhotos()` 之後觸發 pending 比對；新增 `applyRestore`。
  - [ScreenshotOrganizerApp.swift](../../albumOrganizer/ScreenshotOrganizer/App/ScreenshotOrganizerApp.swift)：`.background` 時除了 `saveNow()`，也呼叫 `backup.backUpIfNeeded()`。
  - [PhotoLibraryService.swift](../../albumOrganizer/ScreenshotOrganizer/Services/PhotoLibraryService.swift)：新增 cloud ID 的互相換算，以及依 local ID 取 `AssetInfo`（給隱藏的截圖用）。
  - [OnboardingView.swift](../../albumOrganizer/ScreenshotOrganizer/Views/Onboarding/OnboardingView.swift)：新增 `RestoreOfferStep`。
  - [FoldersScreen.swift](../../albumOrganizer/ScreenshotOrganizer/Views/Library/FoldersScreen.swift)：標題列加齒輪按鈕。
  - `doc/README.md`、`doc/storage.md`：補一節說明備份。

## 架構設計

```
Views
  OnboardingView.RestoreOfferStep ─┐
  SettingsSheet (BackupSection) ───┼─▶ LibraryStore ──────────────┐
                                   └─▶ BackupService (@Observable) │ applyRestore / backupSource
                                         ├─ BackupRemote (協定)     │
                                         │    └─ CloudKitBackupRemote（CKContainer 私有資料庫）
                                         ├─ PendingRestoreStore（pending-restore.json）
                                         └─ PhotoLibraryService（cloud ID ↔ local ID）

ScreenshotKit（純值型別，可 swift test）
  Backup/BackupSnapshot   ─ 快照模型（BackupShot / BackupShotKey）
  Backup/BackupCodec      ─ schemaVersion、newerSchema 拒讀
  Backup/BackupMatcher    ─ 快照條目 ↔ AssetInfo 的對應（cloud ID → 時間＋尺寸唯一比對）
  Backup/Library+Backup   ─ Library.backupSnapshot(...) 與 Library.restoring(...)（merge 規則）
```

各層的職責：

- **ScreenshotKit/Backup**：負責所有規則，包括快照長什麼樣子、怎麼對應、怎麼 merge、何時過期。完全不碰 Photos 或 CloudKit，全部用 `swift test` 測。
- **BackupRemote / CloudKitBackupRemote**：只做「上傳 `Data`、取回最新的 `Data`、查帳號狀態」，不認識 `Library`。
- **PendingRestoreStore**：只負責讀寫 `pending-restore.json`。
- **BackupService**（App 層的 `@MainActor @Observable`）：編排流程。
  - 何時可以上傳（還原決定、D17）。
  - 打包：向 store 取 `Library`，向 Photos 取 cloud ID，再呼叫 `Library.backupSnapshot`。
  - 還原：下載、解碼、換算 ID、呼叫 matcher，再交給 store 套用。
  - pending 的重新比對。
  - 對 UI 暴露的狀態 `BackupStatus`。
- **LibraryStore**：只多一個入口 `applyRestore(_:)`。在 `mutate` 裡呼叫 `Library.restoring`，接著 `requeueOutdated`、`sync`、存檔、`learning.update`、`processor.start()`。它不認識 CloudKit。

### 還原流程（onboarding）

```
requestAccess() 成功
  └─ backup.checkForBackup()  （iCloud 不可用或逾時 3 秒 → .none）
       ├─ .none          → 記下「已做出還原決定」→ startImport()
       └─ .found(summary) → phase = .restoreOffer（顯示日期與張數）
            ├─ 「還原」   → backup.restore() → store.applyRestore(result) → startImport()
            └─ 「從頭開始」→ 記下「已做出還原決定」→ startImport()
```

`startImport()` 會跑 `sync(with:)`，這一步負責新增新截圖、移除 Photos 已經沒有的截圖（D7）。`applyRestore` 必須在它之前完成。

### pending 的重新比對

`LibraryStore.syncWithPhotos()` 和 `refresh()` 套用 assets 之後，如果 `pendingRestore` 不是空的，就呼叫 `backup.matchPending(assets:)`：
1. 先清掉超過 30 天的條目（`now` 由注入的 clock 提供）。
2. 用 `BackupMatcher` 比對新進來的 assets。
3. 對上的條目交給 `store.applyRestore`。跟 onboarding 走同一條路，只是 `pending` 為空。
4. 把剩下的寫回 `PendingRestoreStore`，清空時就刪檔。

### 替代方案

| 方案 | 優點 | 缺點 | 結論 |
|------|------|------|------|
| A. 每張截圖一筆 CKRecord，增量同步 | 可以多裝置同步，上傳量小 | 衝突處理、刪除墓碑、record zone 變更追蹤，複雜度高好幾倍 | 不採用；需求是還原（D3） |
| B. `pendingRestore` 放進 `Library` 和 SQLite | 跟主資料一起存檔，原子性好 | `Library` 的 Codable、SQLite migration、`LibraryChanges` 都要改，只是為了一份會過期的暫存資料 | 不採用（D15） |

## 檔案變更清單

| 動作 | 檔案 | 層 | 職責 |
|------|------|----|------|
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Backup/BackupSnapshot.swift` | Domain | 快照模型 `BackupSnapshot`、`BackupShot`、`BackupShotKey` |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Backup/BackupCodec.swift` | Domain | 編碼與解碼，處理 `schemaVersion` 和 `newerSchema` |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Backup/BackupMatcher.swift` | Domain | 快照條目和 `AssetInfo` 的對應（純函式） |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Backup/Library+Backup.swift` | Domain | `backupSnapshot(...)`、`restoring(...)`，以及 merge 規則 |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Backup/PendingRestore.swift` | Domain | `PendingRestore` 值型別：條目、`restoredAt`、`expiring(now:)` |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/BackupCodecTests.swift` | Test | |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/BackupMatcherTests.swift` | Test | |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/LibraryBackupTests.swift` | Test | 打包與 merge 規則 |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Services/BackupRemote.swift` | Service | `BackupRemote` 協定與 `CloudKitBackupRemote` |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Services/PendingRestoreStore.swift` | Service | 讀寫 `pending-restore.json` |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Services/BackupService.swift` | Service | 流程編排與 `BackupStatus` |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Views/Settings/SettingsSheet.swift` | View | 設定 sheet，第一版只有備份區塊 |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Views/Settings/BackupSection.swift` | View | 狀態、上次備份時間、立即備份、從備份還原 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Services/PhotoLibraryService.swift` | Service | `cloudIdentifiers(for:)`、`localIdentifiers(forCloud:)`、`assetInfos(for:)` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Store/LibraryStore.swift` | Store | `.restoreOffer` phase、`requestAccess` 分流、`applyRestore`、sync 後觸發 pending 比對 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/App/ScreenshotOrganizerApp.swift` | App | 建立 `BackupService` 並注入 environment；進背景時備份 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Onboarding/OnboardingView.swift` | View | `RestoreOfferStep` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Library/FoldersScreen.swift` | View | 齒輪按鈕開啟 `SettingsSheet` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Store/UIState.swift` | Store | `isSettingsPresented` |
| 修改 | `albumOrganizer/albumOrganizer.entitlements` | Config | 填入 iCloud container ID |
| 修改 | `doc/README.md`、`doc/storage.md` | Doc | 補一節說明備份與還原 |

## 介面草案

```swift
// ScreenshotKit/Backup/BackupSnapshot.swift

/// How a backed-up screenshot is found again, on this device or another one.
public struct BackupShotKey: Codable, Hashable, Sendable {
    /// `PHAsset.localIdentifier` on the device that made the backup.
    public var localID: String
    /// `PHCloudIdentifier.stringValue`; `nil` when iCloud Photos was off.
    public var cloudID: String?
    public var createdAt: Date
    public var pixelWidth: Int
    public var pixelHeight: Int
}

/// What the user decided about one screenshot. No recognized text: that is recomputed on the device.
public struct BackupShot: Codable, Hashable, Sendable {
    public var key: BackupShotKey
    public var folderID: UUID?
    public var placement: Placement
    public var tags: [String]
    public var featureTags: Set<FeatureTag>
    public var dismissedFeatureTags: Set<FeatureTag>
}

public struct BackupSnapshot: Codable, Hashable, Sendable {
    public var createdAt: Date
    public var folders: [Folder]
    public var tags: [String]
    public var deletedBuiltIns: Set<BuiltInCategory>
    public var shots: [BackupShot]
    public var hiddenShots: [BackupShotKey]
}

// ScreenshotKit/Backup/BackupCodec.swift
public enum BackupCodec {
    public static let currentSchemaVersion = 1
    public enum DecodeError: Error, Equatable { case unreadable(String), newerSchema(Int) }
    public static func decode(_ data: Data) throws -> BackupSnapshot
    public static func encode(_ snapshot: BackupSnapshot) throws -> Data
}

// ScreenshotKit/Backup/BackupMatcher.swift
public enum BackupMatcher {
    public struct Result: Equatable, Sendable {
        /// Current `localIdentifier` → what the backup says about it.
        public var matched: [String: BackupShot]
        public var matchedHidden: Set<String>
        public var unmatched: [BackupShot]
        public var unmatchedHidden: [BackupShotKey]
    }

    /// Cloud identifier first; otherwise capture time + pixel size, applied only when exactly one asset fits.
    /// - Parameter localIDsByCloudID: what `PHPhotoLibrary` resolved on this device.
    public static func match(
        shots: [BackupShot],
        hidden: [BackupShotKey],
        assets: [AssetInfo],
        localIDsByCloudID: [String: String]
    ) -> Result
}

// ScreenshotKit/Backup/Library+Backup.swift
public extension Library {
    /// Includes `pending`, so screenshots not yet found on this device survive the next backup.
    func backupSnapshot(
        createdAt: Date,
        cloudIDsByLocalID: [String: String],
        hiddenAssets: [AssetInfo],
        pending: PendingRestore?
    ) -> BackupSnapshot

    /// Merges a backup into this library. Placement precedence: local user > backup user >
    /// backup auto > local auto / pending. Folders are matched by id, tags are unioned.
    /// Shots not yet in the library are added; `sync(with:)` afterwards drops the ones Photos lacks.
    func restoring(
        folders: [Folder],
        tags: [String],
        deletedBuiltIns: Set<BuiltInCategory>,
        matched: [String: BackupShot],
        matchedHidden: Set<String>,
        assets: [AssetInfo]
    ) -> Library
}

// ScreenshotKit/Backup/PendingRestore.swift
public struct PendingRestore: Codable, Hashable, Sendable {
    public static let lifetime: TimeInterval = 30 * 24 * 60 * 60
    public var restoredAt: Date
    public var folders: [Folder]
    public var tags: [String]
    public var deletedBuiltIns: Set<BuiltInCategory>
    public var shots: [BackupShot]
    public var hiddenShots: [BackupShotKey]

    public var isEmpty: Bool { shots.isEmpty && hiddenShots.isEmpty }
    public func isExpired(now: Date) -> Bool
}
```

```swift
// Services/BackupRemote.swift
struct BackupPayload: Sendable {
    var data: Data
    var createdAt: Date
    var schemaVersion: Int
    var shotCount: Int
}

enum BackupAccountState: Equatable, Sendable { case available, noAccount, restricted, unknown }

protocol BackupRemote: Sendable {
    func accountState() async -> BackupAccountState
    /// Newest first; at most two.
    func fetchSnapshots() async throws -> [BackupPayload]
    /// Overwrites the older of the two slots.
    func upload(_ payload: BackupPayload) async throws
}

struct CloudKitBackupRemote: BackupRemote {
    init(container: CKContainer = .default())
}

// Services/PendingRestoreStore.swift
struct PendingRestoreStore: Sendable {
    init(fileURL: URL)
    func load() -> PendingRestore?
    func save(_ pending: PendingRestore?) throws   // nil deletes the file
}

// Services/BackupService.swift
@MainActor
@Observable
final class BackupService {
    enum Status: Equatable {
        case idle
        case unavailable(BackupAccountState)
        case backingUp
        case failed(String)
    }

    enum Availability: Equatable {
        case none
        case found(createdAt: Date, shotCount: Int)
    }

    private(set) var status: Status
    private(set) var lastBackupAt: Date?
    /// Off on a fresh install until the user answers the restore question.
    private(set) var canUpload: Bool

    init(
        remote: any BackupRemote,
        photos: PhotoLibraryService,
        pendingStore: PendingRestoreStore,
        now: @escaping @Sendable () -> Date = Date.init
    )

    func checkForBackup() async -> Availability
    /// Downloads, matches and hands the result to `store`; leftovers go to `pending-restore.json`.
    func restore(into store: LibraryStore) async throws
    func declineRestore()
    func backUpIfNeeded(from store: LibraryStore) async
    func matchPending(assets: [AssetInfo], into store: LibraryStore)
}

// Store/LibraryStore.swift（新增的部分）
extension LibraryStore {
    enum Phase { case welcome, permission, restoreOffer, importing, app }

    struct RestoreInput: Sendable {
        var folders: [Folder]
        var tags: [String]
        var deletedBuiltIns: Set<BuiltInCategory>
        var matched: [String: BackupShot]
        var matchedHidden: Set<String>
        var assets: [AssetInfo]
    }

    /// Merges, sends outdated automatic placements back to the queue, syncs with Photos, saves and retrains.
    func applyRestore(_ input: RestoreInput)
}
```

`BackupService` 依賴的是 `LibraryStore` 這個具體型別，沒有另外抽協定，因為它只會用到 `library`、`applyRestore` 兩個成員。測試時用 `LibraryStore` 搭配假的 `LibraryPersisting` 和 `PhotoLibraryService`，跟現有寫法一致。

## 規則檢核（pre-review）

| 規則 | 設計對策 | 殘留風險 |
|------|----------|----------|
| 1. 框架慣例 | 領域規則放在 ScreenshotKit 的 pure value type，用 `swift test` 測；I/O 用協定隔開，由 init 注入（比照 `LibraryPersisting`）；App 層 service 是 `@MainActor`，背景工作用 `Task.detached`（比照 `LearnedModelUpdater`）；UI 用 `@Observable`，透過 `.environment` 注入；字型和顏色用 `Typeface`、`Palette`，按鈕用 `ClassicalButtonStyle` | 專案沒有 l10n 機制，字串跟現有畫面一樣直接寫中文 |
| 2. 架構可擴充性 | 之後如果改用逐筆同步或換後端，只需要新增一個 `BackupRemote` 的實作，ScreenshotKit 和 UI 都不用改；快照格式有 `schemaVersion`，加欄位用 `decodeIfPresent` 給預設值；比對策略集中在 `BackupMatcher` 一個地方 | `BackupRemote` 目前只有 CloudKit 一個實作，但測試需要假的實作，所以這個協定有存在的必要 |
| 3. 副作用 / Pure Function | 打包、比對、merge、過期判斷都是 ScreenshotKit 裡的純函式，回傳新值、不修改輸入；`now` 由注入的 clock 提供；CloudKit、Photos、檔案 I/O 只出現在 `CloudKitBackupRemote`、`PhotoLibraryService`、`PendingRestoreStore` 三個地方 | 無 |
| 4. 重複程式碼 | 重用 `Folder`、`Placement`、`FeatureTag` 的 Codable 和 `decodeKnownValues`；`BackupCodec` 比照 `LibraryCodec`，但因為型別不同而分開（語意不同，未來會分歧）；還原後的新增與刪除交給既有的 `sync(with:)`；onboarding 還原和 pending 比對都走同一個 `applyRestore` | 無 |
| 5. 命名 | 模型用 `BackupSnapshot`、`BackupShot`、`BackupShotKey`、`PendingRestore`；查詢類方法 `backupSnapshot(...)`、`restoring(...)` 回傳新值、沒有副作用；有副作用的動作用動詞：`backUpIfNeeded`、`restore`、`matchPending`、`applyRestore`；bool 用 `canUpload`、`isEmpty`、`isExpired`；「還原」一律叫 restore，「備份」一律叫 backup | 無 |
| 6. 巢狀與複雜度 | merge 的 placement 優先順序抽成一個 `static func preferredPlacement(local:backup:)`，用 guard 依序判斷；`BackupMatcher` 拆成 `matchByCloudID` 和 `matchByCaptureKey` 兩步；onboarding 的分流用 `Availability` 的 switch，每個 case 只有一行 | 無 |
| 7. SOLID | **S**：Remote 只管傳輸、Store 只管檔案、Service 只管編排、Library 只管規則。**O**：換後端時只需新增實作。**L**：假的 `BackupRemote` 完全遵守協定語意（最多回傳 2 份、新的在前）。**I**：`BackupRemote` 只有 3 個方法。**D**：`BackupService` 的 remote、photos、pendingStore、clock 都由 init 注入 | 無 |

## 實作步驟

1. **快照模型與 codec**：新增 `BackupSnapshot`、`BackupCodec` 和測試。驗證：`cd Packages/ScreenshotKit && swift test --filter BackupCodecTests`。
2. **BackupMatcher**：先寫測試（TDD），涵蓋 cloud ID 命中、fallback 唯一命中、fallback 多張符合、完全找不到、隱藏截圖。驗證：`swift test --filter BackupMatcherTests`。
3. **`Library+Backup` 與 `PendingRestore`**：打包、merge 優先順序、資料夾和標籤聯集、過期判斷。驗證：`swift test --filter LibraryBackupTests`，再跑完整的 `swift test`。
4. **Photos 的 ID 換算**：在 `PhotoLibraryService` 新增 `cloudIdentifiers(for:)`、`localIdentifiers(forCloud:)`、`assetInfos(for:)`，分批呼叫（每批 500 個）。驗證：`xcodebuild build`。
5. **CloudKit 傳輸**：entitlement 填入 container；實作 `BackupRemote` 和 `CloudKitBackupRemote`，用兩個固定的 record name 輪流覆寫。驗證：在登入 iCloud 的實機上手動上傳、下載一次，並到 CloudKit Dashboard 確認 record。
6. **PendingRestoreStore 與 BackupService**：狀態、`canUpload` 閘門（D9、D17）、打包上傳、還原、pending 比對。驗證：`xcodebuild build`。
7. **LibraryStore 整合**：`.restoreOffer` phase、`requestAccess` 分流、`applyRestore`（`restoring` → `requeueOutdated` → `sync` → 存檔 → `learning.update` → `processor.start()`）、sync 之後呼叫 `matchPending`；App 進背景時觸發備份。驗證：模擬器跑一次全新安裝的 onboarding。
8. **UI**：`RestoreOfferStep`、`SettingsSheet` 加 `BackupSection`、齒輪入口。驗證：模擬器截圖檢查畫面。
9. **端對端手動測試**：見測試計畫的手動情境。
10. **文件**：更新 `doc/README.md`（架構圖、文件索引）和 `doc/storage.md`（新增「備份與還原」一節）。

## 測試計畫

- **BackupCodec**
  - 編碼後再解碼，結果和原本相同。
  - `schemaVersion` 比目前新時，丟出 `newerSchema`。
  - 遇到不認識的 `FeatureTag` 或 `BuiltInCategory` 時略過那個值，不讓整份解碼失敗。
- **BackupMatcher**
  - cloud ID 能換算時，用它對應。
  - cloud ID 換算不出來，但「時間＋尺寸」剛好只有一張符合時，用 fallback 對應。
  - 同一秒內有兩張同尺寸的截圖時，兩張都算對不上（D12）。
  - 同一個 asset 不會被兩筆備份條目重複對應。
  - 隱藏截圖的比對結果和一般截圖分開回傳。
- **`Library.restoring`**
  - placement 優先順序的四種組合：本機 user 對上備份 user、本機 user 對上備份 auto、本機 auto 對上備份 user、本機 pending 對上備份 auto。
  - 同一個 UUID 的資料夾不會重複；備份資料夾改過名時，保留本機的名稱。
  - 標籤取聯集，並保持順序。
  - 備份裡的 `folderID` 指向不存在的資料夾時，那張截圖放進未分類。
  - 隱藏的截圖被還原後，`sync` 不會把它加回來。
- **`Library.backupSnapshot`**
  - 快照不包含 OCR 文字。
  - `pending` 裡的條目會出現在快照中（D9）。
  - pending 狀態的截圖不放進快照，它們還沒有分類結果。
- **`PendingRestore.isExpired`**：剛好 30 天和 30 天又 1 秒，兩個邊界都要測。
- **手動情境（實機）**
  1. 同一台裝置刪掉 App 再重裝：選「還原」後分類都在，新拍的截圖進「處理中」。
  2. 同一台裝置刪掉 App 再重裝：選「從頭開始」後，雲端快照不會在選擇之前被覆蓋（到 Dashboard 確認時間戳）。
  3. 開「部分照片」權限後還原，再到系統設定加選更多照片：新加的照片會套回原本的分類。
  4. 登出 iCloud：onboarding 沒有詢問步驟，設定頁顯示「未登入 iCloud」。
  5. 已經用了一陣子，從設定頁「從備份還原」：手動分類的結果沒有被覆蓋。

## 風險與未決問題

- ⚠️ **沒開 iCloud 照片時無法跨裝置還原**：`PHCloudIdentifier` 換算不出來，只能靠「時間＋尺寸」比對，連拍的截圖會落到重新分類。這在設計範圍內（D12），但設定頁的說明文字要寫清楚。
- ⚠️ **快照大小**：每張截圖大約 300 bytes，1 萬張約 3 MB，用 CKAsset 沒有問題。但如果未來在快照裡加 OCR，就要重新評估。
- ⚠️ **進背景時的上傳時間**：`beginBackgroundTask` 大約只有 30 秒，大的快照在網路慢時可能傳不完。對策是上傳失敗不影響本機資料，下次進背景時重試，設定頁顯示「上次備份失敗」。如果實測常常失敗，再改用 `CKOperation` 的 `isLongLived` 或 `BGProcessingTask`。
- ⚠️ **CloudKit schema 要部署到 production**：record type `LibrarySnapshot` 在 Development 環境建立後，上架前要在 CloudKit Dashboard 部署到 Production，否則正式版上傳會失敗。
- ⚠️ **merge 時資料夾的 UUID**：內建分類的資料夾在新裝置上，`addMissingBuiltInFolders()` 會產生新的 UUID，和備份裡的 UUID 不同。`restoring` 必須用 `builtIn` 把內建資料夾對應起來，並把備份截圖的 `folderID` 改寫成本機的 UUID。這一點已經列入測試計畫，實作時要特別注意。
- ❓ 無其他未決問題。

## 實作與 plan 的差異

- `BackupService` 不依賴 `LibraryStore`：`restore(assets:)`、`matchPending(assets:)` 回傳 `BackupRestore`，由 `LibraryStore.applyRestore` 套用；`backUp(_ library:)` 直接收 `Library`。避免 service 和 store 互相依賴。
- `Library.restoring(_:mergingFolders:)` 只覆蓋已經在 library 裡的截圖，所以 `applyRestore` 先 `sync(with:)` 再 `restoring`，不需要傳 `assets`。
- `PendingRestore` 包一份 `BackupSnapshot`（只剩還沒找到的截圖），不重複定義欄位；pending 比對時傳 `mergingFolders: false`，不重新加回使用者已經刪掉的資料夾。
- 沒有新增 `SettingsSheet.swift`（見 D16）。
- 新增 D19、D20。

## 修訂紀錄

| 版本 | 日期 | 變更 |
|------|------|------|
| v1 | 2026-10-13 | 初版 |
| v2 | 2026-10-13 | 實作完成，補上與 plan 的差異、D19、D20 |
