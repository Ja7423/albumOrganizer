# 資料儲存

App 的資料是一個值型別 `Library`，執行時整份放在記憶體裡，存檔時寫進 SQLite。這份文件說明儲存的架構、資料庫 schema，以及讀寫與版本升級的機制。

| 項目 | 內容 |
|------|------|
| 資料庫 | `Application Support/library.sqlite`（WAL 模式，旁邊會有 `-wal`、`-shm` 檔） |
| 存取方式 | [GRDB](https://github.com/groue/GRDB.swift) 7，只在 `Packages/LibraryPersistence` 裡使用 |
| 舊格式 | `library.json`（SQLite 之前的格式）：第一次開啟資料庫時匯入一次，之後改名為 `library.imported.json` 保留 |
| 內容 | 截圖索引、OCR 文字、資料夾、標籤、分類狀態。**沒有任何圖片**（圖片一律即時向 Photos 要，見 [README §1.5](README.md#15-匯入與檔案處理)） |
| 設計決策 | 為什麼選 SQLite、為什麼不用 SwiftData，見 [plan/library-storage-sqlite-2026-10-11.md](plan/library-storage-sqlite-2026-10-11.md) |
| 文件更新日期 | 2026-10-11（對應 `feature/llm-refinement`：新增 `shot.isRefined`） |

---

## 1. 架構

```
LibraryStore（App，@MainActor）
  ├─ library: Library                 記憶體裡唯一的資料，畫面都讀它
  ├─ lastSaved: Library               上次成功寫入的內容，用來算變動
  └─ persistence: any LibraryPersisting
                    │  load() / save(_:changes:)，在背景執行
                    ▼
  Packages/LibraryPersistence ─────────────────────────────────────────
       SQLiteLibraryDatabase          開啟資料庫、跑 migration、load / save
         ├─ LibraryMigrator           所有 schema 變更，依序執行
         │    └─ 匯入舊的 library.json（JSONLibraryFile → LibraryCodec）
         ├─ LibraryRows               Library ↔ 各張表的 row，決定寫入順序
         └─ Records                   每張表一個 struct，與領域型別互相轉換
                    │
                    ▼
                  GRDB（DatabasePool）→ library.sqlite
```

| 型別 | 位置 | 負責 | 不負責 |
|------|------|------|------|
| `Library` 與規則 | `ScreenshotKit` | 資料本身與所有規則；`changes(since:)` 算出變動 | 任何 I/O，不依賴 GRDB |
| `LibraryCodec` | `ScreenshotKit/LibraryCodec.swift` | `library.json` 的編解碼，現在只用於匯入 | — |
| `LibraryPersisting` | `LibraryPersistence/LibraryPersisting.swift` | 儲存層協定：`load`、`save`；`Logger.persistence` | — |
| `SQLiteLibraryDatabase` | `LibraryPersistence/SQLiteLibraryDatabase.swift` | 開啟資料庫、跑 migration、匯入後把 `library.json` 改名；`load` / `save` 各在一個 transaction 裡 | 領域規則 |
| `LibraryMigrator` | `LibraryPersistence/LibraryMigrator.swift` | 所有 schema 變更 | 平常的讀寫 |
| `LibraryRows` | `LibraryPersistence/LibraryRows.swift` | 讀出整份 Library；依 `LibraryChanges` 只寫有變動的 row | 決定何時存檔 |
| `ShotRecord` 等 | `LibraryPersistence/Records.swift` | 一張表一個 struct；與 `Shot`、`Folder` 互相轉換（純函式），不認得的值照 §2.4 處理 | — |
| `JSONLibraryFile` | `LibraryPersistence/JSONLibraryFile.swift` | 讀舊的 `library.json`；讀不懂時改名保留 | — |
| `LibraryStore` | App `Store/LibraryStore.swift` | 何時讀、何時寫、寫入排隊、失敗時的處理 | SQL、檔案格式 |

規則：

- **所有修改都經過 `store.mutate { $0.xxx }`**，規則寫在 `Library` 的 mutating 方法裡。畫面和 Store 都不寫 SQL。
- **記憶體裡的 `library` 才是準的**。資料庫只在啟動時讀一次，之後只寫不讀。
- **`ScreenshotKit` 不依賴 GRDB**，規則的測試照樣在 macOS 上 `swift test`。

---

## 2. Schema

### 2.1 使用者資料（不能遺失，改動要寫 migration）

**`folder`**

| 欄位 | 型別 | 說明 |
|------|------|------|
| `id` | TEXT PK | UUID 字串 |
| `name` | TEXT NOT NULL | 顯示名稱。不設 UNIQUE：名稱不重複由 `Library` 保證，資料庫若擋下來，整次存檔會失敗 |
| `builtIn` | TEXT | 內建類別的 key；使用者自建的資料夾為 NULL |
| `position` | INTEGER NOT NULL | 使用者看到的順序，從 0 開始 |

**`tag`**：`name` TEXT PK、`position` INTEGER NOT NULL（建立順序）。

**`shot`**

| 欄位 | 型別 | 對應 `Shot` | 說明 |
|------|------|------|------|
| `id` | TEXT PK | `id` | `PHAsset.localIdentifier` |
| `createdAt` | DOUBLE NOT NULL | `createdAt` | 從 2001-01-01 起算的秒數。不用 GRDB 預設的日期格式，因為它只保留到毫秒 |
| `pixelWidth`、`pixelHeight` | INTEGER NOT NULL | 同名 | 原圖尺寸 |
| `folderID` | TEXT，FK → `folder(id)` ON DELETE SET NULL | `folderID` | NULL 表示未分類，或還沒分類過的處理中截圖 |
| `placement` | TEXT NOT NULL | `placement` | `pending` / `auto` / `user` |
| `autoSource` | TEXT | `AutoPlacement.source` | 只有 `auto` 時有值：`rule` / `knn` / `llm` / `learned`；NULL 表示判斷不出來 |
| `classifierVersion` | INTEGER | `AutoPlacement.classifierVersion` | 只有 `auto` 時有值 |
| `isRefined` | BOOLEAN NOT NULL DEFAULT 0 | `AutoPlacement.isRefined` | Apple Intelligence 補判是否已經看過這張（見 [classification.md §4](classification.md#5-第三層apple-intelligence-補判)）。`auto` 以外的截圖一律是 0 |
| `tags` | TEXT NOT NULL | `tags` | JSON 陣列，使用者加的標籤 |
| `featureTags` | TEXT NOT NULL | `featureTags` | JSON 陣列，自動標籤的 key，已扣掉使用者移除過的 |
| `dismissedFeatureTags` | TEXT NOT NULL | `dismissedFeatureTags` | JSON 陣列，使用者移除過的自動標籤 |

**`hiddenShot`**：`id` TEXT PK。使用者「從 App 移除」的截圖，同步時不會加回；這些 id 不會出現在 `shot`。

**`deletedBuiltIn`**：`category` TEXT PK。使用者刪掉的內建類別，不會重建，也不會再分類進去。

### 2.2 可以重算的資料（版本不符時可以清掉重算）

**`recognition`**

| 欄位 | 型別 | 對應 `Shot` | 說明 |
|------|------|------|------|
| `shotID` | TEXT PK，FK → `shot(id)` ON DELETE CASCADE | — | 截圖刪除時一起刪除 |
| `state` | TEXT NOT NULL | `recognition` | `pending` / `done` / `failed` |
| `attempts` | INTEGER NOT NULL | `recognitionAttempts` | OCR 失敗次數，達到 3 次（`Shot.maxRecognitionAttempts`）就不再重試 |
| `blocks` | TEXT NOT NULL | `blocks` | JSON 陣列，每個元素是 `{id, text, box: {x, y, width, height}}`；座標 0 到 1、左上為原點；由上到下、同一列由左到右，已去掉狀態列 |
| `barcodes` | TEXT NOT NULL | `barcodes` | JSON 陣列，QR code 與條碼的內容 |

截圖沒有對應的 `recognition` row 時，讀出來就是 `recognition = pending`、沒有文字，會重新辨識。

### 2.3 列舉值

| 型別 | 值 |
|------|------|
| `RecognitionState` | `pending`、`done`、`failed` |
| `FeatureTag` | `link`（含連結）、`qrCode`（QR code）、`phone`（含電話）、`date`（含日期）、`address`（含地址） |
| `BuiltInCategory` | `receipt` 收據、`ticket` 票券、`social` 社群、`article` 文章、`code` 程式碼、`place` 地點、`recipe` 食譜、`shopping` 購物、`credential` 帳號資訊、`schedule` 行程、`note` 筆記、`stock` 股票、`info` 資訊 |
| `ClassifierSource` | `rule`、`knn`、`llm`、`learned` |

**資料庫裡存的是左邊的 key，畫面上的名稱只是顯示用**，改顯示名稱不需要動 schema。新增、刪除、改名 key 的影響見 §4.2。

### 2.4 不認得的值

另一個版本的 App 寫入的值，這一版可能不認得。讀取時只影響那一個值，不會讓整份資料讀取失敗：

| 欄位 | 不認得的值 |
|------|------|
| `shot.featureTags`、`shot.dismissedFeatureTags`、`deletedBuiltIn.category` | 略過那一個值 |
| `recognition.state` | 當成 `pending`，重新辨識 |
| `shot.placement`、`shot.autoSource` | 當成 `pending`，重新分類。`auto` 卻沒有 `classifierVersion` 也一樣 |
| `folder.builtIn` | 變成一般資料夾，名稱和裡面的截圖都保留 |
| `folder.id`、`shot.folderID` 不是合法的 UUID | 那個資料夾略過；截圖當成沒有資料夾 |

### 2.5 不變式

這些由 `Library` 的方法維持，外鍵負責其中兩條。手動修改資料庫時要遵守：

- 一張截圖最多在一個資料夾裡（`shot.folderID` 只有一個值）。
- `shot.folderID` 指向的資料夾必須存在（外鍵；資料夾刪除時設為 NULL）。
- `recognition.shotID` 指向的截圖必須存在（外鍵；截圖刪除時一起刪除）。
- `hiddenShot` 裡的 id 不會出現在 `shot`。
- `deletedBuiltIn` 裡的類別不會有資料夾。
- 資料夾名稱不重複，標籤名稱不重複。
- `placement = 'pending'` 的截圖仍可能有 `folderID`：分類器版本更新後被送回處理中的截圖，會留在原資料夾直到重新分類完成。

### 2.6 Migration 紀錄

GRDB 把已經執行過的 migration 記在 `grdb_migrations` 表。

| identifier | 內容 |
|------|------|
| `v1-schema` | 建立 §2.1、§2.2 的所有表 |
| `v3-shot-is-refined` | `shot` 加上 `isRefined` |
| `v2-import-legacy-json` | 如果有 `library.json`，匯入一次（見 §3.1） |

表格依**執行順序**排列。匯入舊 JSON 時是用目前的 Record 寫入，需要最新的 schema，所以它永遠註冊在最後（見 §4.2）。identifier 的編號代表加入的先後，不代表執行順序。

---

## 3. 操作機制

### 3.1 開啟資料庫（啟動時）

`LibraryStore` 建立 `SQLiteLibraryDatabase` 時：

1. 開啟 `library.sqlite`（`DatabasePool`，WAL 模式），不存在就建立。
2. 依序執行還沒跑過的 migration。每個 migration 各自在一個 transaction 裡，**失敗就整個退回**，資料庫維持原狀，下次啟動再試。
3. 如果這次才執行 `v2-import-legacy-json`：
   - `library.json` 正常讀到：整份寫進資料庫，完成後檔案改名為 `library.imported.json`。
   - `library.json` 讀不懂（損壞，或 `schemaVersion` 比目前新）：原檔改名為 `library.unreadable-<UTC 時間>.json` 保留，記錄 log，從空的資料庫開始。
   - `library.json` 存在但讀不到（例如裝置還沒解鎖）：這個 migration 失敗並退回，下次啟動重新匯入。
   - 沒有 `library.json`（全新安裝）：什麼都不做。

開啟或 migration 失敗時不會 crash：錯誤會保留下來，在 `load()` 時丟出（見 3.2）。

### 3.2 讀取（只在啟動時一次）

`LibraryStore.init` 呼叫 `persistence.load()`，在一個讀取 transaction 裡把所有表讀出來，組成一份 `Library`：

| 情況 | `load()` 的結果 | `LibraryStore` 的處理 |
|------|------|------|
| 資料庫是空的 | `.empty` | 從空的 Library 開始 |
| 有資料 | `.loaded(library)` | 使用它；不認得的值照 §2.4 處理 |
| 資料庫打不開、migration 失敗 | 丟出錯誤 | 記錄 log；**這次啟動完全不存檔**，避免蓋掉沒讀到的資料 |

讀到之後會立刻執行 `requeueOutdated(version: ClassificationPipeline.version)`，把舊版分類器的自動結果送回處理中。如果因此有任何變動，會排一次存檔。

資料庫裡缺少的內建資料夾（全新安裝，或新版本新增的分類），`Library` 會在記憶體裡補上，ID 每次啟動都不同。`lastSaved` 也包含這些資料夾，所以它們不算變動；等到下一次有截圖要寫入時，才會跟著寫進資料庫（見 3.3）。

### 3.3 寫入

**存檔時機**（`LibraryStore`）：

```
store.mutate { $0.xxx }
   └─ scheduleSave()：取消上一個還沒觸發的存檔，等 400ms
         └─ write(library)
               ├─ 這次啟動停用存檔 → 結束
               ├─ changes = library.changes(since: lastSaved)
               ├─ changes 為空 → 結束（不寫入）
               └─ 排在上一個寫入之後，在背景執行 persistence.save(…)
                     ├─ 成功 → lastSaved = 這次寫入的內容
                     └─ 失敗 → 記錄 log；lastSaved 不變，下次存檔會再寫一次這些變動
```

- **debounce 400ms**：連續的修改只會寫一次。
- **沒有變動就不寫**：例如同步沒有發現新截圖時。
- **寫入會依序排隊**：舊的內容不會蓋過新的。
- **App 進入背景時**呼叫 `saveNow()`：不等 debounce，立刻排一次寫入，並向系統申請背景時間讓它寫完。

**寫入內容**（`LibraryRows.write`，整次存檔在一個 transaction 裡，失敗就整個退回）：

| 順序 | 動作 | 什麼時候 |
|:----:|------|------|
| 1 | upsert 所有 `folder`（更新 `position`） | `hasFolderChanges`，或有變動的截圖時 |
| 2 | 刪除 `deletedShotIDs` 的 `shot`（`recognition` 由外鍵一起刪除） | 有刪除的截圖時 |
| 3 | upsert `upsertedShotIDs` 的 `shot` 和 `recognition` | 有變動的截圖時 |
| 4 | 刪除已經不在 Library 裡的 `folder` | `hasFolderChanges` |
| 5 | `tag`、`hiddenShot`、`deletedBuiltIn` 整張表重寫 | 各自的 `has…Changes` |

- 資料夾先 upsert、最後才刪除：截圖可能搬進新資料夾（外鍵要求資料夾先存在），被刪的資料夾在 `Library` 裡已經沒有截圖指向它。
- 有截圖要寫入時，就算 `hasFolderChanges` 是 false 也 upsert 資料夾：`Library()` 和讀出來的 `Library` 會在記憶體裡補上內建資料夾，跟它比對的差異永遠不會包含這些資料夾。只靠 `hasFolderChanges` 的話，全新資料庫裡就沒有內建資料夾，截圖一分類進去就外鍵失敗，之後每次存檔都失敗。
- 截圖用 **upsert**（`INSERT … ON CONFLICT DO UPDATE`），不用 `INSERT OR REPLACE`：REPLACE 會先刪掉舊的 row，觸發外鍵把 `recognition` 一起刪除。
- `tag` 等三張表很小，整張重寫比算出差異簡單。

### 3.4 誰會修改資料

| 來源 | 操作 | 位置 |
|------|------|------|
| Photos 同步（首次匯入、回到前景、Photos 變更通知、下拉更新） | `sync(with:)` | `LibraryStore` |
| 處理佇列 | `setRecognition`（每張 OCR 完成）、`applyClassification`（每張分類完成） | `ScreenshotProcessor` |
| 啟動 | `requeueOutdated` | `LibraryStore.init` |
| 資料夾 | `createFolder`、`renameFolder`、`deleteFolder`、`move` | `Sheets.swift`、`LibraryStore.deleteFolder` |
| 標籤 | `createTag`、`deleteTag`、`toggleTag`、`addTag`、`dismissFeatureTag` | `Sheets.swift`、`TagsScreen.swift` |
| 從 App 移除 | `hide` | `AppShell.swift` |

首次匯入時，每張截圖完成 OCR 和分類都會觸發一次存檔，但每次只寫那一張的 `shot` 和 `recognition`。

---

## 4. 版本與升級

### 4.1 調整分類規則（不需要改 schema）

改了規則、門檻或 Apple Intelligence 的 prompt，**只要調高 `ClassificationPipeline.version`**。下次啟動時，`requeueOutdated` 會把 `classifierVersion` 比較舊的自動分類送回處理中重新分類；使用者放入的（`placement = 'user'`）不動。結果經由一般的存檔寫回資料庫。

### 4.2 修改 schema

**一律新增一個 migration**，identifier 依序編號（下一個是 `v4-…`）。**已經發佈的 migration 永遠不要修改**：使用者的資料庫已經執行過它，改了也不會再跑。

新的 schema migration 要加在 `v2-import-legacy-json` **前面**、其他 schema migration 後面。匯入舊 JSON 時是用目前的 `ShotRecord` 寫入整份資料，表格必須已經是最新的 schema，否則從舊 JSON 升級的裝置會寫入失敗。GRDB 會執行所有還沒套用的 migration（遷移目標是最後一個註冊的），所以已經跑過匯入的資料庫，仍然會補跑插在前面的新 migration。`v3-shot-is-refined` 就是這樣加入的，`testDatabaseFromBeforeRefinementGainsTheColumn` 驗證了這個行為。

先看相容性：

- **新版讀舊資料庫**：一定要能讀，使用者升級 App 時就會發生。migration 會在開啟時把資料庫升到最新。
- **舊版讀新資料庫**：只有在使用者裝回舊版時才會發生。GRDB 看到不認得的 migration 不會報錯，舊版會照常讀取它認得的欄位，不認得的值照 §2.4 處理。

| 變動 | 做法 |
|------|------|
| 新增欄位 | migration 用 `ALTER TABLE … ADD COLUMN`，給預設值或允許 NULL；Record 加上屬性，並在 `ShotRecord(shot)` / `shot(recognition:)` 這類轉換裡對應。舊版的 Record 會忽略多出來的欄位 |
| 新增表 | migration 用 `db.create(table:)`，加一個 Record，並在 `LibraryRows` 的讀寫裡處理 |
| 刪除欄位 | 先停止讀寫它；確定不會再裝回舊版後，再用 migration 刪除：`db.alter(table:) { $0.drop(column:) }`（SQLite 原生的 `DROP COLUMN`）。主鍵、外鍵、有索引或 UNIQUE 的欄位不能這樣刪，要建新表、搬資料、再換名 |
| 新增列舉值 | 不需要 migration。舊版會依 §2.4 略過或重設 |
| 刪除列舉值 | 不需要 migration，但要確認 §2.4 的結果可以接受：刪掉的內建類別的資料夾會變成一般資料夾；自動標籤直接消失 |
| 列舉值改名、欄位改名、改型別 | 寫 migration 用 SQL 轉換既有資料（例如 `UPDATE shot SET placement = …`），否則舊的值會被當成不認得而重設 |
| 可以重算的資料要整個重做 | migration 清掉 `recognition`（或之後的 embedding 表）即可，不用轉換。注意文字變了會影響分類和自動標籤，見 §4.3 |

**測試**：每加一個 migration，就用上一版的資料庫（或用 `migrate(_:upTo:)` 建出來的資料庫）當起點，跑完新的 migration 後檢查資料。`Packages/LibraryPersistence/Tests` 用 in-memory 的 `DatabaseQueue`，不需要檔案。

### 4.3 OCR 演算法改變

目前 `recognition` 沒有記錄是用哪一版 OCR 辨識的，這是刻意的：在第一次真的要改 OCR 之前，這個欄位不會有人用。到時候用 migration 加上即可，舊的 row 會拿到預設值 `0`，全部被視為過期。

**什麼時候算「OCR 改變」**：改動下面任何一項，已經辨識過的截圖就和新的截圖結果不一致：

- 辨識語言（`VisionScreenRecognizer.languages`）、`recognitionLevel`、`usesLanguageCorrection`
- 狀態列的過濾範圍（`TextBlockFilter.statusBarHeight`）
- 文字行的排序規則（`VisionScreenRecognizer.recognize` 結尾的 `sorted`）
- 條碼偵測的方式
- 換成其他 Vision API（例如 iOS 26 的新文字辨識 API）

**第一次改 OCR 時要做的事：**

1. **加上版本號**：新增 migration，`recognition` 加 `ocrVersion INTEGER NOT NULL DEFAULT 0`；`Shot` 和 `RecognitionRecord` 加對應的屬性；OCR 那邊加一個目前版本的常數，設為 `1`；`setRecognition` 成功時寫入目前版本。
2. **啟動時把過期的截圖重新排進 OCR 佇列**：仿照 `requeueOutdated` 在 `Library` 加一個方法，把 `ocrVersion` 較舊的截圖設回 `recognition = .pending`，並且**把 `recognitionAttempts` 歸零**。否則以前失敗過 3 次的截圖永遠不會再辨識。
3. **分類也要重做**：文字變了，自動分類（`placement == auto`）可能就不對了，要一起送回處理中。使用者放入的（`user`）維持不動。
4. **使用者放入的截圖，自動標籤要另外更新**：`applyClassification` 只處理「處理中」的截圖，使用者放入的截圖不會經過它，所以重新辨識後「含連結」「含日期」這些自動標籤不會跟著更新。要把自動標籤的更新從 `applyClassification` 拆出來，讓每張截圖辨識完就重算一次（仍要扣掉 `dismissedFeatureTags`）。
5. **不要一次把所有截圖丟回處理中**：重新辨識要重新取原圖跑 Vision，iCloud 上的原圖還得重新下載。幾千張會跑很久、很耗電，而且這段時間所有截圖都會出現在「處理中」。比較好的做法是：
   - 舊的 `blocks`、`barcodes` 在新結果出來前保留，搜尋和標題照常可用；
   - 只有自動分類的截圖才回到處理中，或乾脆保留原本的分類，等新文字出來再重新分類；
   - 新匯入的截圖優先，舊的在 App 開著時慢慢處理。

   這部分會改變處理佇列和「處理中」的意義，動工前先寫規劃文件。
6. **測試**：確認舊資料庫跑完 migration 後全部被重新排入；確認使用者放入的截圖分類不變，但自動標籤有更新。

### 4.4 舊的 `library.json`

`library.json` 只會在 `v2-import-legacy-json` 讀一次，讀取規則仍由 `LibraryCodec` 負責：

- 缺少的欄位用預設值；`Shot` 只有 `id`、`createdAt`、像素尺寸是必要的。
- 不認得的列舉值依 §2.4 的同樣規則略過或重設。
- 有 `schemaVersion`（目前是 1），沒有時視為 0；比目前新的檔案當成讀不懂，改名保留。

App 不會再寫入 `library.json`。`LibraryCodec` 與 `JSONLibraryFile` 保留下來只為了匯入，以及讀取 `library.imported.json` 這類備份檔時使用。

---

## 5. 限制與注意事項

- **OCR 文字是明文**：截圖裡的密碼、帳號、地址都會原樣存在 `recognition.blocks`。資料庫在 App sandbox 裡，使用系統預設的檔案保護等級，沒有另外加密。
- **整份 Library 常駐記憶體**：OCR 文字也在記憶體裡（標題、搜尋、詳細頁都直接讀它）。幾千張截圖沒問題；上萬張或加上 embedding 之後，要改成用到才從資料庫讀，見規劃文件。
- **每次存檔都比對整份 Library**：`changes(since:)` 是 O(n)，幾千筆只要幾毫秒。
- **最多會掉最後 400ms 的修改**：App 在 debounce 期間直接被系統終止（沒有先進背景，例如 crash）時，最後那筆修改不會寫入。
- **備份檔不會自動清除**：`library.imported.json`、`library.unreadable-*.json` 會一直留在 `Application Support/`。
- **裝回 SQLite 之前的版本**：那個版本只認得 `library.json`，而它已經改名，所以會從空的狀態重新匯入。資料仍在 `library.sqlite` 和 `library.imported.json` 裡，升級回來就會恢復。開發時在新舊 branch 間切換也會遇到。

---

## 6. 除錯

在模擬器上找到資料庫：

```bash
open "$(xcrun simctl get_app_container booted com.chiawei.albumOrganizer data)/Library/Application Support"
```

查看內容（App 開著時也可以讀，WAL 模式不會互相鎖住）：

```bash
sqlite3 "$(xcrun simctl get_app_container booted com.chiawei.albumOrganizer data)/Library/Application Support/library.sqlite" "SELECT placement, COUNT(*) FROM shot GROUP BY placement; SELECT identifier FROM grdb_migrations;"
```

查看儲存相關的 log（subsystem 是 bundle id，category 是 `persistence`）：

```bash
xcrun simctl spawn booted log show --last 10m --predicate 'subsystem == "com.chiawei.albumOrganizer" AND category == "persistence"'
```

手動修改資料庫之前先關掉 App：App 只在啟動時讀一次，之後存檔會依記憶體裡的內容覆寫有變動的 row。

---

## 7. iCloud 備份與還原

規劃與決策理由見 [plan/icloud-library-backup-2026-10-13.md](plan/icloud-library-backup-2026-10-13.md)。

### 7.1 備份什麼

`BackupSnapshot`（`ScreenshotKit/Backup/`）是 `Library` 的使用者資料，不含任何可以重算的東西：

| 有 | 沒有 |
|----|----|
| 資料夾、標籤、刪掉的內建分類 | OCR 文字、條碼（還原後在背景重新辨識） |
| 每張截圖的資料夾、placement（`user` / `auto`）、標籤、feature tags、被移除的 feature tags | 學習層模型（還原後依 user placement 重新訓練） |
| 隱藏的截圖 | 最近搜尋 |
| 處理中（`pending`）以外的所有截圖 | 處理中的截圖（還沒有結果可以保留） |

每張截圖用 `BackupShotKey` 記錄怎麼找回它：備份時的 `localIdentifier`、`PHCloudIdentifier`（沒開 iCloud 照片時為 `nil`）、拍攝時間、像素尺寸。

格式由 `BackupCodec` 編碼，規則和 `LibraryCodec` 相同：有 `schemaVersion`，比目前新的快照拒讀。

### 7.2 存在哪裡

CloudKit 私有資料庫（container `iCloud.com.chiawei.albumOrganizer`）的預設 zone，record type `LibrarySnapshot`，固定兩個 record：`snapshot-0`、`snapshot-1`。每次上傳覆寫較舊的那個，所以雲端永遠保留最近兩份。欄位：`payload`（CKAsset，JSON）、`createdAt`、`schemaVersion`、`shotCount`。

讀取時從新的開始解碼，讀不懂的（壞檔或 `newerSchema`）就改用另一份。

### 7.3 什麼時候上傳

- App 進背景時（`LibraryStore.backUp()`，有 background task），或在設定頁按「立即備份」。
- 內容和這次執行中上次上傳的相同就略過。
- **上傳閘門** `BackupService.canUpload`：只有確定不會蓋掉該保留的備份時才打開。
  - 使用者回答了還原詢問（還原或從頭開始）。
  - 確認 iCloud 裡沒有可讀的備份。
  - 這台裝置在備份功能出現前就完成 onboarding（本機本來就有資料）。
  - 檢查逾時、網路失敗、還原失敗時**不會**打開；設定頁會顯示還沒處理的備份，讓使用者選「還原」或「略過」。

### 7.4 還原

```
fetchScreenshots() → BackupMatcher.match → Library.sync(with:) → Library.restoring → requeueOutdated
                                   └─ 沒找到的 → pending-restore.json
```

- **對應截圖**（`BackupMatcher`）：先把 cloud identifier 換成這台的 `localIdentifier`。換不到時，用「拍攝時間（到秒）＋像素尺寸」比對，只有雙方都剛好一張時才算。
- **合併**（`Library.restoring`）：
  - placement：這台的 user placement 優先，其次備份的 user、備份的 auto，最後才是這台的 auto 或 pending。
  - 資料夾：依序用 id、內建分類、名稱對應；都對不上就新增。這台刪掉的內建分類維持刪除；備份刪掉的內建分類，只有在這台的資料夾是空的時才刪。
  - 標籤、被移除的 feature tags 取聯集。
- **還沒找到的截圖**：存在 `Application Support/pending-restore.json`。每次 Photos 同步後重新比對，對上的就套用（這時不再新增資料夾，資料夾已經被刪掉的截圖維持原狀）。30 天後清除。下一次備份會把它們一起寫進快照，所以不會因為換手機而遺失。
- 還原後，比目前分類器版本舊的 auto placement 會照 `requeueOutdated` 重新分類，和升級 App 時一樣。

### 7.5 注意事項

- **CloudKit schema 要部署到 Production**：record type 在 Development 環境第一次上傳時自動建立，上架前要在 CloudKit Console 部署到 Production。
- **沒開 iCloud 照片**：跨裝置只能靠拍攝時間＋尺寸對應，同一秒同尺寸的截圖會重新分類。
- **背景時間有限**：上傳失敗不影響本機資料，下次進背景時重試，設定頁顯示原因。
