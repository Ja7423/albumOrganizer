# Feature Plan：Library 儲存層（JSON 防護 → SQLite）

| 項目 | 內容 |
|------|------|
| 規劃日期 | 2026-10-11 |
| 規劃方式 | 直接規劃（依對話中 JSON / SwiftData / SQLite 的比較） |
| 目前分支 | `main`（`a3ec6ea`，已是 Swift 6 language mode）；實作時另開 `feature/library-storage` |
| 狀態 | 階段 1 已實作（`feature/library-storage`）；階段 2、3 待開始 |

## 需求摘要

`Library` 目前整份存成 `Application Support/library.json`。這份計畫分三個階段改善儲存層：

1. **階段 1（上架前必做）**：修好「讀檔失敗會清空並覆蓋使用者資料」的漏洞，並建立 schema 版本與 migration 的機制。
2. **階段 2（做 kNN 之前）**：儲存層換成 SQLite（GRDB）。記憶體裡仍是值型別 `Library`，存檔改成只寫有變動的 row；使用者資料與可以重算的資料分表。
3. **階段 3（截圖量大或搜尋變慢時）**：加上 FTS5 全文索引。

成功的樣子：
- App 更新後，任何 schema 變動或檔案損壞都不會讓使用者的資料夾、標籤、手動分類消失。
- 首次匯入時的寫檔量從 O(n²) 降為 O(n)。
- 調整分類規則只需要調高版本號，不需要寫 migration。

### 範圍

- **In scope**
  - 階段 1：`schemaVersion`、所有欄位改用 `decodeIfPresent`、壞檔備份、寫檔失敗記錄 log、`requeueOutdated` 的結果在啟動時就寫入、同步沒有變化時不寫檔
  - 階段 2：GRDB 儲存模組、`DatabaseMigrator`、分表 schema、增量寫入、從 `library.json` 一次性匯入
  - 刪除未使用的 Core Data 範本（`Persistence.swift`、`albumOrganizer.xcdatamodeld`）
  - 階段 3 的設計方向（介面與限制），細節在動工前另開計畫
- **Out of scope**
  - SwiftData（見 D2）
  - OCR 文字與 embedding 改成用到才從資料庫讀（見 D6，等記憶體真的成為瓶頸再做）
  - kNN 本身、embedding 的產生方式
  - 讓 SQLite 成為畫面的唯一資料來源（GRDB `ValueObservation`，見替代方案 B）
  - iCloud 同步、匯出與備份功能

## 決策紀錄

| # | 決策 | 選擇 | 理由 / 被放棄的選項 |
|---|------|------|------|
| D1 | 長期儲存技術 | SQLite，透過 GRDB | migration 每一步都是 transaction，失敗就 rollback；可以用 in-memory DB 測試；Record 可以是 struct，不必改動 `Library` 的值型別設計；有 FTS5 可用 |
| D2 | SwiftData | 不採用 | `@Model` 必須是 class，會把 `ScreenshotKit` 的規則打散到 `ModelContext` 的操作裡；migration 失敗時只能刪掉 store；全文搜尋與向量搜尋都幫不上忙。取代掉原計畫 `screenshot-auto-classification-2026-10-07.md` 的 D18 中「等 kNN 時再評估」 |
| D3 | 原始 SQLite C API 或 SQLite.swift | 不採用，選 GRDB | 原始 C API 的樣板程式碼和執行緒處理太多；GRDB 的 migrator、`DatabasePool`、FTS5 支援都比較完整，維護也比較久 |
| D4 | 時程 | 先做階段 1，階段 2 在 kNN 之前，階段 3 視截圖量而定 | 階段 1 改動小、風險最高，最急；階段 2 的必要性來自 embedding 會讓 JSON 爆量 |
| D5 | SQLite 與記憶體的關係 | 架構 A：SQLite 只取代存檔，記憶體裡仍是 `Library` | 規則、測試、畫面都不用改；替代方案 B 等於重寫 Store 和大部分畫面 |
| D6 | OCR 的 blocks 是否常駐記憶體 | 階段 2 仍常駐 | `Shot.title`（grid、搜尋列表）、`Library.search`、`classifierInput`、詳細頁都直接讀 `shot.blocks`，改成用到才讀的話影響範圍太大。分表之後再改成用到才讀，就只需要改讀取這一側（預設值，可推翻） |
| D7 | 增量寫入怎麼知道改了什麼 | 比對新舊兩份 `Library`（`Library.changes(since:)`，純函式） | `Shot` 是 `Hashable`，比對幾千筆只需要幾毫秒；不用在 17 個 mutating 方法裡各自記錄 dirty id，也不會把儲存的考量混進領域層。放棄：在 `Library` 裡維護 `dirtyShotIDs` |
| D8 | 資料怎麼分表 | 使用者資料和可以重算的資料分開 | 可以重算的資料（OCR、條碼）在版本不符時可以清掉重算，不必寫轉換 |
| D9 | 調整分類規則 | 維持 `ClassificationPipeline.version` 加上 `Library.requeueOutdated` | 在架構 A 下，規則仍在記憶體裡的 `Library` 執行，結果再透過增量寫入存檔；不需要在 SQL 裡重寫一份規則 |
| D10 | 讀檔失敗時 | 舊檔改名備份，從空的 Library 開始，記錄 log | 絕對不覆蓋。要不要顯示提示給使用者，見未決問題 |
| D11 | 從 `library.json` 匯入 | 階段 2 做一次性匯入，成功後把舊檔改名為 `library.imported.json` | 開發中和 TestFlight 的資料也值得保留；匯入共用階段 1 的 `LibraryCodec`，幾乎沒有額外成本（預設值） |
| D12 | 儲存模組放哪裡 | 新的本地 package `Packages/LibraryPersistence`（`swift-tools-version: 6.0`，與 `ScreenshotKit` 相同），依賴 `ScreenshotKit` 和 GRDB 7 | `ScreenshotKit` 維持零依賴，`swift test` 不需要先抓 GRDB；邊界也比「同一個 package 的第二個 target」清楚。放棄：在 `ScreenshotKit/Package.swift` 加 target（可行，但會讓領域層的 package 帶著第三方依賴） |
| D15 | Swift 6 並行模型 | 儲存相關型別一律 `Sendable`；App target 裡的協定與 `JSONLibraryFile` 標 `nonisolated` | App target 設定 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，不標的話會被隔離在 MainActor，無法在背景存檔。比照 `TextRecognizer.swift` 的 `nonisolated protocol ScreenRecognizing: Sendable` |
| D13 | log | 使用 `os.Logger`（subsystem 為 bundle id，category 為 `persistence`） | 專案目前沒有任何 log 機制；先用系統的 Logger，不引入第三方套件（預設值） |
| D14 | 中文全文搜尋（階段 3） | FTS5 搭配 `trigram` 斷詞器；關鍵字少於 3 個字時退回 `LIKE` | 預設的 `unicode61` 不會切中文；trigram 查不到兩個字的詞，例如「發票」「密碼」 |

## 現況分析

- **讀寫**：`LibraryStore`（`albumOrganizer/ScreenshotOrganizer/Store/LibraryStore.swift`）
  - `init` 用 `try? JSONDecoder().decode(...) ?? Library()` 讀檔，失敗時得到空的 Library
  - `mutate` → `scheduleSave()`：等 400ms debounce 後，在 detached Task 裡把整份 Library 編碼成 JSON，以 atomic 方式寫入
  - `saveNow()` 在 App 進入背景時同步寫入（`ScreenshotOrganizerApp.swift:19`）
  - 寫檔失敗都用 `try?` 吞掉，沒有任何 log
- **漏洞**：讀檔失敗得到空的 Library 後，啟動時的同步會呼叫 `mutate`，400ms 後就把舊檔覆蓋掉
- **Codable**：
  - `Library.init(from:)`（`Library.swift:45`）對 5 個 key 都用 `decode`
  - `Shot`、`Folder`、`Placement` 都是編譯器自動產生的 Codable，新增任何非 optional 欄位都會讓舊檔解碼失敗
- **`requeueOutdated`**：在 `init` 裡直接改 `library`，沒有經過 `mutate`，所以要等下一次 `mutate` 才會寫入
- **`sync(with:)`**：會回傳 `SyncResult`（新增的 id、刪除的數量），但 `LibraryStore.apply` 沒有使用，沒有變化也照樣寫檔
- **`Library.update(_:_:)`**（`Library.swift:263`）：所有修改單張截圖的操作都經過它
- **`blocks` 的讀取方**：`Shot.title`、`allText`、`languageSummary`、`Search.swift`、`classifierInput`、`ShotPage`、`ShotDetailScreen`（見 D6）
- **測試**：`Packages/ScreenshotKit/Tests/ScreenshotKitTests` 使用 XCTest，fixture 放在 `Fixtures/`
- **專案設定**：App target 使用 `PBXFileSystemSynchronizedRootGroup`，新增或刪除檔案不必改 pbxproj；本地 package 透過 `XCLocalSwiftPackageReference` 加入
- **Swift 6**：App target 是 `SWIFT_VERSION = 6.0`、`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`；`ScreenshotKit` 是 `swift-tools-version: 6.0`（commit `a3ec6ea`）。要在背景執行的型別已用 `nonisolated` 標示，例如 `ScreenRecognizing`、`VisionScreenRecognizer`、`PhotoLibraryService`
- **目前的背景存檔**：`scheduleSave()` 在 `Task.detached` 裡編碼並寫檔，捕捉的是 `Library` 快照（`Sendable`）與 `URL`；改成注入 `any LibraryPersisting` 後，協定本身必須是 `Sendable` 且非 MainActor 隔離
- **未使用的程式碼**：`albumOrganizer/Persistence.swift`（Core Data 範本 `PersistenceController`）與 `albumOrganizer.xcdatamodeld`，沒有任何地方引用

## 架構設計

```
階段 1
LibraryStore ──(any LibraryPersisting)──▶ JSONLibraryFile ──▶ LibraryCodec（ScreenshotKit，純函式）
                                               └─ 讀檔失敗：改名成 library.corrupt-<時間>.json，記錄 log

階段 2
LibraryStore ──(any LibraryPersisting)──▶ SQLiteLibraryDatabase（Packages/LibraryPersistence）
     │                                         ├─ LibraryMigrator（DatabaseMigrator，每一步都是 transaction）
     │                                         ├─ Records（ShotRecord、RecognitionRecord…，純對應）
     │                                         └─ 第一次開啟：透過 LibraryCodec 匯入 library.json
     └─ 存檔前：library.changes(since: lastSaved) ──▶ 只寫有變動的 row
```

分層說明：

| 層 | 負責 | 不負責 |
|----|------|------|
| `ScreenshotKit` | `Library` 與所有規則；`LibraryCodec`（JSON 格式與版本轉換）；`Library.changes(since:)` | 任何 I/O、GRDB |
| `LibraryPersistence` | SQLite schema、migration、Record 與 `Library` 之間的轉換、增量寫入、匯入 JSON | 領域規則（不判斷分類、不決定哪些要重新排入佇列） |
| `LibraryStore` | 何時存檔（debounce、進背景）、保留上次存檔的快照、記錄失敗 | 檔案格式、SQL |

### SQLite schema（階段 2，migration `v1`）

**使用者資料（不能遺失，需要認真寫 migration）**

| 表 | 欄位 |
|----|------|
| `folder` | `id TEXT PK`、`name TEXT UNIQUE`、`builtIn TEXT NULL`、`position INT` |
| `tag` | `name TEXT PK`、`position INT` |
| `shot` | `id TEXT PK`、`createdAt REAL`、`pixelWidth INT`、`pixelHeight INT`、`folderID TEXT NULL REFERENCES folder ON DELETE SET NULL`、`placement TEXT`（`pending`/`auto`/`user`）、`autoSource TEXT NULL`、`classifierVersion INT NULL`、`tags TEXT`（JSON 陣列）、`featureTags TEXT`、`dismissedFeatureTags TEXT` |
| `hiddenShot` | `id TEXT PK` |
| `deletedBuiltIn` | `category TEXT PK` |

**可以重算的資料（版本不符時清掉重算）**

| 表 | 欄位 |
|----|------|
| `recognition` | `shotID TEXT PK REFERENCES shot ON DELETE CASCADE`、`state TEXT`、`attempts INT`、`blocks BLOB`（JSON）、`barcodes BLOB`（JSON）、`ocrVersion INT` |
| `embedding`（kNN 時新增） | `shotID TEXT PK`、`embeddingVersion INT`、`vector BLOB` |
| `shotSearch`（階段 3） | FTS5 virtual table，`tokenize='trigram'` |

`shot` 沒有對應的 `recognition` row 時，就視為 `recognition == .pending`。

`tags`、`featureTags` 這類集合先存成 JSON 欄位。階段 2 不需要用 SQL 查詢它們；真的需要時再加一步 migration 拆成關聯表。

### 替代方案

| 方案 | 優點 | 缺點 | 結論 |
|------|------|------|------|
| B：SQLite 當唯一資料來源，畫面用 `ValueObservation` 直接查 | 記憶體用量最低、查詢最快 | 要重寫 `LibraryStore` 和大部分畫面；規則必須搬進 SQL 或 repository，`swift test` 的單元測試價值會下降 | 不採用，等真的有效能問題再評估 |
| 只做階段 1，不換 SQLite | 改動最小 | embedding 放不進 JSON；首次匯入仍是 O(n²) | 作為階段 1 的終點可以接受，但 kNN 一定要換 |

## 檔案變更清單

| 動作 | 檔案 | 層 | 職責 |
|------|------|----|------|
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/LibraryCodec.swift` | Domain | JSON 編解碼、`schemaVersion`、版本轉換 |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Library.swift` | Domain | `init(from:)` 改用 `decodeIfPresent`，`encode` 寫入 `schemaVersion` |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Models.swift` | Domain | `Shot`、`Folder` 自訂 `init(from:)`，識別欄位以外都用 `decodeIfPresent` 加預設值 |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/LibraryChanges.swift` | Domain | `LibraryChanges` 與 `Library.changes(since:)` |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/LibraryCodecTests.swift` | Test | 舊格式、缺欄位、損壞檔案 |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/Fixtures/library-v0.json` | Test | 目前格式（沒有 `schemaVersion`）的真實樣本 |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/LibraryChangesTests.swift` | Test | 各種修改產生的變動集合 |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Store/LibraryPersisting.swift` | Store | `LibraryPersisting` 協定、`LibraryLoadResult` |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Store/JSONLibraryFile.swift` | Store | 階段 1 的實作：讀、寫、壞檔備份 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Store/LibraryStore.swift` | Store | 改為注入 `any LibraryPersisting`；保留 `lastSaved` 快照；記錄 log；啟動時 requeue 有變動就存檔；同步沒有變化就不存 |
| 刪除 | `albumOrganizer/Persistence.swift`、`albumOrganizer/albumOrganizer.xcdatamodeld` | — | 未使用的 Core Data 範本 |
| 新增 | `Packages/LibraryPersistence/Package.swift` | Build | `swift-tools-version: 6.0`，依賴 `ScreenshotKit`（path）和 GRDB 7 |
| 新增 | `Packages/LibraryPersistence/Sources/LibraryPersistence/SQLiteLibraryDatabase.swift` | Persistence | `LibraryPersisting` 的 SQLite 實作 |
| 新增 | `Packages/LibraryPersistence/Sources/LibraryPersistence/LibraryMigrator.swift` | Persistence | 所有 schema migration |
| 新增 | `Packages/LibraryPersistence/Sources/LibraryPersistence/Records.swift` | Persistence | `ShotRecord`、`FolderRecord`、`RecognitionRecord`… 與 `Library` 之間的轉換（純函式） |
| 新增 | `Packages/LibraryPersistence/Sources/LibraryPersistence/JSONImport.swift` | Persistence | 一次性匯入 `library.json` |
| 新增 | `Packages/LibraryPersistence/Tests/LibraryPersistenceTests/*` | Test | migration、往返一致、增量寫入、匯入 |
| 移動 | `LibraryPersisting` 協定 → `Packages/LibraryPersistence` | Persistence | 階段 2 時讓 JSON 和 SQLite 兩種實作共用同一個協定 |
| 修改 | `albumOrganizer.xcodeproj/project.pbxproj` | Build | 加入 `Packages/LibraryPersistence` 的本地 package 參照 |
| 修改 | `doc/README.md` | Doc | §1.1 表格、§1.5「匯入與檔案處理」、儲存那一列 |

## 介面草案

```swift
// ScreenshotKit — LibraryCodec.swift
public enum LibraryCodec {
    /// Bump when the JSON shape changes; `decode` upgrades older files.
    public static let currentSchemaVersion = 1

    public enum DecodeError: Error, Equatable {
        case unreadable(String)
        case newerSchema(Int)   // written by a newer app version; never overwrite it
    }

    public static func decode(_ data: Data) throws -> Library
    public static func encode(_ library: Library) throws -> Data
}

// ScreenshotKit — LibraryChanges.swift
public struct LibraryChanges: Equatable, Sendable {
    public var upsertedShotIDs: [String]
    public var deletedShotIDs: [String]
    public var hasFolderChanges: Bool
    public var hasTagChanges: Bool
    public var hasHiddenChanges: Bool
    public var hasDeletedBuiltInChanges: Bool

    public var isEmpty: Bool { get }
}

public extension Library {
    /// What differs from `old`; used to write only the rows that changed.
    func changes(since old: Library) -> LibraryChanges
}

// App（階段 2 移到 LibraryPersistence 並改為 public）— LibraryPersisting.swift
// App target 預設 MainActor 隔離，必須標 nonisolated 才能在背景存檔（D15）
nonisolated enum LibraryLoadResult: Sendable {
    case loaded(Library)
    case empty
    /// The stored data could not be read; it was moved aside to `backupURL` and never overwritten.
    case unreadable(backupURL: URL)
}

nonisolated protocol LibraryPersisting: Sendable {
    func load() throws -> LibraryLoadResult
    /// `changes` lets incremental stores skip unchanged rows; whole-file stores ignore it.
    func save(_ library: Library, changes: LibraryChanges) throws
}

nonisolated struct JSONLibraryFile: LibraryPersisting {
    init(fileURL: URL, now: @escaping @Sendable () -> Date = Date.init)
}

// LibraryPersistence — SQLiteLibraryDatabase.swift
// 只持有 `let dbPool: DatabasePool`（GRDB 7 中為 Sendable），所以不需要 @unchecked
public final class SQLiteLibraryDatabase: LibraryPersisting {
    /// Opens (and migrates) the database; imports `legacyJSONURL` once if the database is new.
    public init(databaseURL: URL, legacyJSONURL: URL?) throws
    /// For tests.
    public static func inMemory() throws -> SQLiteLibraryDatabase
}

// LibraryPersistence — LibraryMigrator.swift
enum LibraryMigrator {
    static var migrator: DatabaseMigrator { get }   // "v1-initial", later "v2-embedding", …
}

// LibraryStore（修改）
init(
    photos: PhotoLibraryService = .shared,
    recognizer: any ScreenRecognizing = VisionScreenRecognizer(),
    pipeline: ClassificationPipeline = .standard,
    persistence: any LibraryPersisting = LibraryStore.defaultPersistence
)
```

`newerSchema` 的情境：使用者裝回舊版 App，讀到新版寫的檔案。這時不能當成損壞而覆蓋，要保留原檔並以唯讀方式處理（見未決問題）。

## 規則檢核（pre-review）

| 規則 | 設計對策 | 殘留風險 |
|------|----------|----------|
| 1. 框架慣例 | 領域邏輯（Codec、changes）放在 `ScreenshotKit`，比照既有的 `Library+Classification.swift`；Store 層的新型別放在 `Store/`；新 package 比照 `Packages/ScreenshotKit` 的結構與 `swift-tools-version: 6.0`；背景執行的型別比照 `TextRecognizer.swift` 標 `nonisolated` 並符合 `Sendable`（D15）；測試比照既有的 XCTest 與 `Fixtures/`；註解風格比照現有的英文 `///` | 無 |
| 2. 架構可擴充性 | 新增欄位只要「加一步 migration 加上 Record 欄位」；新增可以重算的資料（embedding、FTS）是新增一張表；換儲存實作只要提供新的 `LibraryPersisting`，`LibraryStore` 不用改。規則仍只在 `Library` 裡 | 無 |
| 3. 副作用 / Pure Function | `LibraryCodec`、`changes(since:)`、Record 與 `Library` 的轉換都是純函式；I/O 只在 `JSONLibraryFile` 和 `SQLiteLibraryDatabase`；備份檔名用的時間由 `now` 注入 | 無 |
| 4. 重複程式碼 | JSON 的解碼與版本轉換只寫在 `LibraryCodec`，階段 1 的讀檔與階段 2 的匯入共用；分類重排只靠既有的 `requeueOutdated`，不在 SQL 裡再寫一份 | 無 |
| 5. 命名 | `LibraryCodec`（只做編解碼）、`LibraryPersisting`（能力型協定，比照既有的 `ScreenRecognizing`）、`JSONLibraryFile` / `SQLiteLibraryDatabase`（看名字就知道是哪種儲存）、`changes(since:)`；bool 用 `has…Changes`、`isEmpty`；表名、欄位名和 Swift 屬性同名 | 無 |
| 6. 巢狀與複雜度 | `LibraryCodec.decode` 的版本轉換用「每一版一個 `upgrade(fromVN:)`、迴圈依序套用」，不寫一條長 switch；`changes(since:)` 拆成 shots、folders、tags 三個小函式；`save` 依 `LibraryChanges` 分成數個 `write…` 子函式 | 無 |
| 7. SOLID | S：Codec 只管格式、Persisting 只管讀寫、Store 只管時機。O：新的儲存實作或 migration 都是新增程式碼。L：`JSONLibraryFile` 不支援增量寫入，但仍完整寫入，語意不變。I：協定只有 `load`、`save` 兩個方法。D：`LibraryStore` 透過 init 注入 `any LibraryPersisting`，取代寫死的 `fileURL` | 無 |

## 實作步驟

**階段 1（上架前）**

1. **Codable 容錯** — 動到：`Library.swift`、`Models.swift`、新增 `LibraryCodec.swift`、`LibraryCodecTests.swift`、`Fixtures/library-v0.json`（由目前版本的 App 產生）；驗證：`cd Packages/ScreenshotKit && swift test`
2. **變動比對** — 動到：新增 `LibraryChanges.swift`、`LibraryChangesTests.swift`；驗證：`swift test`
3. **持久化協定與 JSON 實作** — 動到：新增 `Store/LibraryPersisting.swift`、`Store/JSONLibraryFile.swift`；修改 `LibraryStore.swift`，改為注入、保留 `lastSaved`、使用 `os.Logger`、啟動時 requeue 有變動就存檔、`apply` 在 `changes.isEmpty` 時跳過存檔；驗證：Xcode build；在模擬器上手動破壞 `library.json` 後啟動，確認產生 `library.corrupt-*.json`，而且原內容還在
4. **刪除 Core Data 範本** — 動到：`Persistence.swift`、`albumOrganizer.xcdatamodeld`；驗證：Xcode build
5. **文件** — 動到：`doc/README.md`；驗證：閱讀檢查

**階段 2（kNN 之前）**

6. **建立 package** — 動到：新增 `Packages/LibraryPersistence/Package.swift`（tools 6.0、platforms 與 `ScreenshotKit` 相同），把 `LibraryPersisting` 移進來並改為 `public`（package 沒有預設 MainActor 隔離，可以拿掉 `nonisolated`）；驗證：`swift build` 在 Swift 6 模式下沒有並行相關的錯誤或警告
7. **schema 與 migrator** — 動到：`LibraryMigrator.swift`；驗證：migrator 在 in-memory DB 上跑完，檢查所有表與欄位
8. **Record 轉換與讀寫** — 動到：`Records.swift`、`SQLiteLibraryDatabase.swift`；驗證：`Library` 寫入再讀出後完全相等；增量寫入只動到預期的 row
9. **JSON 匯入** — 動到：`JSONImport.swift`；驗證：用 `library-v0.json` 匯入後內容相等，舊檔被改名
10. **接上 App** — 動到：`project.pbxproj`、`LibraryStore.defaultPersistence`；驗證：在模擬器上從有 `library.json` 的狀態升級，資料夾、標籤、手動分類都還在；首次匯入幾百張截圖時，Instruments 的 File Activity 確認寫入量隨張數線性成長
11. **文件** — 動到：`doc/README.md`；驗證：閱讀檢查

**階段 3（視需要）**：動工前另開計畫，方向見 D14 與「風險與未決問題」。

## 測試計畫

- **`LibraryCodec`**
  - 讀 `library-v0.json`（沒有 `schemaVersion`）成功，內容正確
  - 缺少 `deletedBuiltIns`、`hiddenShotIDs` 等 key 時使用預設值
  - `Shot` 缺少新欄位時使用預設值
  - 損壞的 JSON 丟出 `unreadable`
  - `schemaVersion` 比目前新時丟出 `newerSchema`
  - 編碼後再解碼，結果和原本相等
- **`Library.changes(since:)`**：同步新增或刪除、`setRecognition`、`applyClassification`、`move`、`hide`、`deleteFolder`（會改到多張截圖）、`renameFolder`、`createTag`、`requeueOutdated`，以及完全沒有變化時 `isEmpty`
- **`JSONLibraryFile`**（暫存目錄）：
  - 讀到壞檔時改名備份並回傳 `unreadable`
  - 檔案不存在時回傳 `empty`
  - 寫入失敗（目錄唯讀）時丟出錯誤
- **`LibraryMigrator`**：從空資料庫跑到最新版；之後每加一步 migration，就用前一版的 fixture 資料庫測升級
- **`SQLiteLibraryDatabase`**：
  - 寫入再讀出後相等
  - 增量寫入後只有預期的 row 改變
  - 刪除 folder 時，`shot.folderID` 變成 NULL
  - 刪除 shot 時，`recognition` 跟著刪除
  - 匯入 JSON 後內容相等，舊檔被改名，第二次開啟不會重複匯入
- **App（手動）**：壞檔情境、升級情境、首次匯入的寫入量

## 風險與未決問題

- ⚠️ **`blocks` 仍常駐記憶體（D6）**：幾千張截圖沒問題。到上萬張、或加上 embedding 之後，要再做「用到才讀」，需要改動 `Shot.title`、`Search`、`classifierInput` 和詳細頁。
- ⚠️ **`changes(since:)` 每次存檔都要比對整份 Library**：時間複雜度是 O(n)，幾千筆只需要幾毫秒；上萬筆要量測。真的太慢的話，再改為在 `Library.update` 裡記錄 dirty id。
- ⚠️ **FTS5 trigram 的限制（階段 3）**：關鍵字少於 3 個字時查不到，要退回 `LIKE`；`Search.swift` 的前後文片段與高亮仍用 Swift 計算，FTS 只負責篩選候選的截圖 id。
- ⚠️ **清掉 `recognition` 表不等於完整的重新辨識**：D8 說 OCR 版本不符時「清掉重算」，但文字變了之後，自動分類要跟著重做；使用者放入的截圖不會經過 `applyClassification`，自動標籤也不會更新；全部一起重算的成本很高。這些在 JSON 方案下就已存在，處理步驟見 [storage.md §4.3](../storage.md#43-ocr-演算法改變)，換成 SQLite 時沿用。
- ⚠️ **系統內建的 SQLite 不能載入擴充套件**：sqlite-vec 這類向量搜尋擴充不能用。kNN 用 Accelerate 暴力計算（幾千張只要幾毫秒），超過這個量級再評估自行編譯 SQLite。
- ❓ **讀檔失敗時要不要告訴使用者**：目前的設計只記錄 log 並保留備份檔。上架後是否要顯示「資料無法讀取，已重新整理」的提示，需要決定。
- ❓ **`newerSchema` 怎麼處理**：裝回舊版 App 是少見的情況。建議以唯讀模式開啟並不存檔，或直接顯示「請更新 App」；需要決定。
- ❓ **階段 2 的時機**：如果確定會在上架前換成 SQLite，D11 的 JSON 匯入可以省略。

## 階段 1 實作紀錄

和上面草案不同的地方：

- **`LibraryCodec.decode` 沒有 `upgrade(fromVN:)` 迴圈**：目前沒有任何需要轉換的舊格式（v0 → v1 只是多了 `schemaVersion`，靠預設值就夠），先不放空的擴充點；第一次真的要轉換格式時再加。
- **`newerSchema` 和損壞的檔案一樣改名保留**（未決問題的預設處理）：檔名為 `library.unreadable-<UTC 時間>.json`，內容完整保留，裝回新版後可以手動救回。
- **`LibraryLoadResult.unreadable` 多帶 `reason`**：讓 `LibraryStore` 能把原因寫進 log。
- **`load()` 丟出錯誤（檔案存在但讀不到）時，這次啟動完全不存檔**：例如裝置還沒解鎖就在背景啟動，這時存檔會蓋掉沒讀到的資料。
- **`saveNow()` 改為非同步並申請背景時間**：寫入改成依序排隊（`writeTask`），舊的快照不會在新的之後寫入；原本同步寫入的版本和背景中的 detached 寫入有這個競態。
- **讀檔失敗是否提示使用者**：維持只記錄 log。
- **列舉值容錯（v5 追加）**：`featureTags`、`dismissedFeatureTags`、`deletedBuiltIns` 略過不認得的值；`recognition`、`placement` 不認得時重設為 `pending`；`Folder.builtIn` 不認得時變成一般資料夾。原本只要一個不認得的列舉值，整份檔案就會讀取失敗並重設。規則見 [storage.md §4.2](../storage.md#42-修改資料結構)。
- **`JSONLibraryFile` 沒有單元測試**：App target 沒有 test target。階段 2 把它移進 `Packages/LibraryPersistence` 時補上；這次在模擬器上手動驗證了舊格式、損壞檔、`schemaVersion` 過新三種情境。

## 修訂紀錄

| 版本 | 日期 | 變更 |
|------|------|------|
| v1 | 2026-10-11 | 初版 |
| v2 | 2026-10-11 | 專案已改為 Swift 6 language mode（`a3ec6ea`）：移除 GRDB 7 工具鏈的風險；D12 改寫理由；新增 D15（`nonisolated` 與 `Sendable`）；介面草案、現況分析、規則檢核與步驟 6 隨之調整 |
| v3 | 2026-10-11 | 階段 1 實作完成，新增「階段 1 實作紀錄」 |
| v4 | 2026-10-11 | 風險新增「清掉 recognition 表不等於完整的重新辨識」，連到 storage.md §4.3 |
| v5 | 2026-10-11 | 階段 1 追加列舉值容錯；storage.md §4.2 改寫相容性規則 |
