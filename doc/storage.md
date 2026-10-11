# 資料儲存

App 目前**沒有資料庫**。所有資料是一個值型別 `Library`，整份編碼成一個 JSON 檔案。這份文件說明它的架構、schema，以及讀寫與版本升級的機制。

| 項目 | 內容 |
|------|------|
| 檔案 | `Application Support/library.json`（App sandbox 內） |
| 格式 | `JSONEncoder` 預設設定的 JSON，UTF-8，不縮排 |
| schema 版本 | `LibraryCodec.currentSchemaVersion = 1` |
| 內容 | 截圖索引、OCR 文字、資料夾、標籤、分類狀態。**沒有任何圖片**（圖片一律即時向 Photos 要，見 [README §1.5](README.md#15-匯入與檔案處理)） |
| 之後的規劃 | 改用 SQLite（GRDB），見 [plan/library-storage-sqlite-2026-10-11.md](plan/library-storage-sqlite-2026-10-11.md) |
| 文件更新日期 | 2026-10-11（對應 `feature/library-storage` 的階段 1 實作） |

---

## 1. 架構

```
LibraryStore（App，@MainActor）
  ├─ library: Library                 記憶體裡唯一的資料，畫面都讀它
  ├─ lastSaved: Library               上次成功寫入的內容，用來算變動
  └─ persistence: any LibraryPersisting
                    │  load() / save(_:changes:)，在背景執行
                    ▼
       JSONLibraryFile（App，nonisolated）
         ├─ 讀寫 library.json（atomic 寫入）
         └─ 讀不懂的檔案改名保留
                    │
                    ▼
       LibraryCodec（ScreenshotKit，純函式）
         └─ 檢查 schemaVersion → Library 的 Codable
```

| 型別 | 位置 | 負責 | 不負責 |
|------|------|------|------|
| `Library` 與其 Codable | `ScreenshotKit/Library.swift`、`Models.swift` | 資料本身與所有規則；缺少的欄位用預設值 | I/O |
| `LibraryCodec` | `ScreenshotKit/LibraryCodec.swift` | JSON 編解碼；拒絕比目前新的 `schemaVersion` | I/O |
| `Library.changes(since:)` | `ScreenshotKit/LibraryChanges.swift` | 比對兩份 Library，算出哪些地方有變動 | 決定何時存檔 |
| `LibraryPersisting` | `Store/LibraryPersisting.swift` | 儲存層的協定：`load`、`save` | 檔案格式 |
| `JSONLibraryFile` | `Store/JSONLibraryFile.swift` | 目前唯一的實作：整份寫入一個檔案 | 領域規則、存檔時機 |
| `LibraryStore` | `Store/LibraryStore.swift` | 何時讀、何時寫、寫入排隊、失敗時的處理 | 檔案格式 |

規則：

- **所有修改都經過 `store.mutate { $0.xxx }`**，規則寫在 `Library` 的 mutating 方法裡。沒有其他地方會改資料或碰檔案。
- **記憶體裡的 `library` 才是準的**。檔案只在啟動時讀一次，之後只寫不讀。
- **換儲存方式只需要提供另一個 `LibraryPersisting`**，`LibraryStore` 和 `Library` 不用改。

---

## 2. Schema

### 2.1 最外層

```json
{
  "schemaVersion": 1,
  "shots": [ Shot, … ],
  "folders": [ Folder, … ],
  "tags": [ "報帳", … ],
  "hiddenShotIDs": [ "8A3F…/L0/001", … ],
  "deletedBuiltIns": [ "recipe", … ]
}
```

| key | 型別 | 必要 | 說明 |
|-----|------|:----:|------|
| `schemaVersion` | Int | 否 | 沒有時視為 0（加入版本號之前寫的檔案） |
| `shots` | `[Shot]` | 否 | 所有截圖，**新到舊** |
| `folders` | `[Folder]` | 否 | 內建類別資料夾加上使用者自建的資料夾，順序就是使用者看到的順序 |
| `tags` | `[String]` | 否 | 使用者建立的標籤，依建立順序 |
| `hiddenShotIDs` | `[String]` | 否 | 使用者「從 App 移除」的截圖 id，同步時不會加回 |
| `deletedBuiltIns` | `[BuiltInCategory]` | 否 | 使用者刪掉的內建類別，不會重建，也不會再分類進去 |

缺少的 key 一律當成空的。讀進來時，沒有被刪掉、也還沒有資料夾的內建類別會自動補上資料夾。

### 2.2 `Shot`

| key | 型別 | 必要 | 預設值 | 說明 |
|-----|------|:----:|------|------|
| `id` | String | 是 | — | `PHAsset.localIdentifier`，回 Photos 拿圖的唯一連結 |
| `createdAt` | Number | 是 | — | 建立時間，從 2001-01-01 起算的秒數（`JSONEncoder` 預設） |
| `pixelWidth` / `pixelHeight` | Int | 是 | — | 原圖尺寸，用來算 grid 的長寬比 |
| `folderID` | String (UUID) | 否 | `null` | 所在資料夾；`null` 表示未分類，或還沒分類過的處理中截圖 |
| `placement` | `Placement` | 否 | `pending` | 怎麼進到這個資料夾的，見 2.4 |
| `tags` | `[String]` | 否 | `[]` | 使用者加的標籤 |
| `featureTags` | `[FeatureTag]` | 否 | `[]` | 分類時自動加上的標籤，已扣掉使用者移除過的 |
| `dismissedFeatureTags` | `[FeatureTag]` | 否 | `[]` | 使用者移除過的自動標籤，之後不會再加回 |
| `blocks` | `[TextBlock]` | 否 | `[]` | OCR 結果，由上到下、同一列由左到右，已去掉狀態列 |
| `barcodes` | `[String]` | 否 | `[]` | QR code 與條碼的內容 |
| `recognition` | `RecognitionState` | 否 | `pending` | OCR 狀態 |
| `recognitionAttempts` | Int | 否 | `0` | OCR 失敗次數，達到 3 次（`Shot.maxRecognitionAttempts`）就不再重試 |

只有 Photos 的身分（`id`、時間、尺寸）是必要的。其他欄位缺少時用預設值，這張截圖會重新走一次 OCR 和分類。

列舉欄位遇到這一版不認得的值（另一個版本的 App 寫的）時，不會讓整份檔案讀取失敗：

| 欄位 | 不認得的值 |
|------|------|
| `featureTags`、`dismissedFeatureTags` | 略過那一個值，其他照常 |
| `recognition` | 當成 `pending`，重新辨識 |
| `placement`（不認得的 case，或 `source` 不認得） | 當成 `pending`，重新分類。格式錯誤的 `placement` 也一樣處理 |

### 2.3 `Folder`、`TextBlock`

| 型別 | key | 說明 |
|------|-----|------|
| `Folder` | `id` | UUID，必要 |
| | `name` | 顯示名稱，必要；不能重複，可以改名 |
| | `builtIn` | 內建類別的 key；使用者自建的資料夾沒有這個 key（或為 `null`）。不認得的 key 會變成一般資料夾，名稱和裡面的截圖都保留 |
| `TextBlock` | `id` | 在這張截圖裡的序號，從 0 開始 |
| | `text` | 一行辨識出的文字 |
| | `box` | `{x, y, width, height}`，0 到 1 的正規化座標，**左上**為原點 |

### 2.4 `Placement`

Swift 自動產生的 enum 編碼，形式如下：

| 值 | JSON | 意義 |
|----|------|------|
| 處理中 | `{"pending": {}}` | 等待 OCR 或分類，出現在「處理中」 |
| 自動分類 | `{"auto": {"_0": {"source": "rule", "classifierVersion": 3}}}` | `source` 是 `rule` / `knn` / `llm`，或沒有這個 key（判斷不出來，放在未分類） |
| 使用者放入 | `{"user": {}}` | 使用者手動搬過，鎖定，永不自動重新分類 |

### 2.5 列舉值

| 型別 | 值 |
|------|------|
| `RecognitionState` | `pending`、`done`、`failed` |
| `FeatureTag` | `link`（含連結）、`qrCode`（QR code）、`phone`（含電話）、`date`（含日期）、`address`（含地址） |
| `BuiltInCategory` | `receipt` 收據、`ticket` 票券、`chat` 對話、`social` 社群貼文、`article` 文章、`code` 程式碼、`place` 地點、`recipe` 食譜、`coupon` 優惠、`credential` 帳號資訊、`schedule` 行程、`note` 筆記 |
| `ClassifierSource` | `rule`、`knn`、`llm` |

**JSON 裡存的是左邊的 key，畫面上的名稱只是顯示用**，改顯示名稱不需要動 schema。新增、刪除、改名 key 的影響見 4.2。

最外層的 `deletedBuiltIns` 遇到不認得的類別也會略過。

### 2.6 不變式

這些規則由 `Library` 的方法維持，手動修改檔案時要遵守：

- 一張截圖最多在一個資料夾裡（`folderID` 只有一個值）。
- `folderID` 指向的資料夾必須存在。刪除資料夾時，裡面的截圖會被移到未分類。
- `hiddenShotIDs` 裡的 id 不會出現在 `shots`。
- `deletedBuiltIns` 裡的類別不會有資料夾。
- 資料夾名稱不重複，標籤名稱不重複。
- `placement == pending` 的截圖仍可能有 `folderID`：分類器版本更新後被送回處理中的截圖，會留在原資料夾直到重新分類完成。

### 2.7 範例

```json
{
  "schemaVersion": 1,
  "shots": [{
    "id": "8A3F…/L0/001",
    "createdAt": 781000300,
    "pixelWidth": 1179, "pixelHeight": 2556,
    "folderID": "D29B973C-52FE-47E1-90BB-244F4181F584",
    "placement": { "auto": { "_0": { "source": "rule", "classifierVersion": 3 } } },
    "tags": ["報帳"],
    "featureTags": ["date"],
    "dismissedFeatureTags": ["link"],
    "blocks": [{ "id": 0, "text": "電子發票證明聯", "box": { "x": 0.1, "y": 0.12, "width": 0.5, "height": 0.03 } }],
    "barcodes": ["https://example.com"],
    "recognition": "done",
    "recognitionAttempts": 0
  }],
  "folders": [{ "id": "D29B973C-52FE-47E1-90BB-244F4181F584", "name": "收據", "builtIn": "receipt" }],
  "tags": ["報帳"],
  "hiddenShotIDs": [],
  "deletedBuiltIns": ["recipe"]
}
```

完整的真實樣本是測試用的 fixture：`Packages/ScreenshotKit/Tests/ScreenshotKitTests/Fixtures/library-v0.json`（加入 `schemaVersion` 之前的格式）。

---

## 3. 操作機制

### 3.1 讀取（只在啟動時一次）

`LibraryStore.init` 呼叫 `persistence.load()`：

| 情況 | `load()` 的結果 | `LibraryStore` 的處理 |
|------|------|------|
| 檔案不存在 | `.empty` | 從空的 Library 開始 |
| 正常讀到（包含缺少欄位的舊檔） | `.loaded(library)` | 使用它 |
| JSON 損壞 | `.unreadable` | 原檔已改名為 `library.unreadable-<UTC 時間>.json` 保留；記錄 log；從空的 Library 開始，之後的同步會重新匯入截圖 |
| `schemaVersion` 比目前新（裝回舊版 App） | `.unreadable` | 同上，新版寫的資料完整保留在備份檔裡 |
| 檔案存在但讀不到（例如裝置還沒解鎖就在背景啟動） | 丟出錯誤 | 記錄 log；**這次啟動完全不存檔**，避免蓋掉沒讀到的資料 |

讀到之後會立刻執行 `requeueOutdated(version: ClassificationPipeline.version)`，把舊版分類器的自動結果送回處理中。如果因此有任何變動，會排一次存檔。

### 3.2 寫入

```
store.mutate { $0.xxx }
   └─ scheduleSave()：取消上一個還沒觸發的存檔，等 400ms
         └─ write(library)
               ├─ 這次啟動停用存檔 → 結束
               ├─ changes = library.changes(since: lastSaved)
               ├─ changes 為空 → 結束（不寫檔）
               └─ 排在上一個寫入之後，在背景執行 persistence.save(…)
                     ├─ 成功 → lastSaved = 這次寫入的內容
                     └─ 失敗 → 記錄 log；lastSaved 不變，下次存檔會再寫一次這些變動
```

- **debounce 400ms**：連續的修改只會寫一次。
- **沒有變動就不寫**：例如回到前景或下拉更新時，同步沒有發現新截圖，就不會寫檔。
- **寫入會依序排隊**：每次寫入都等上一次寫完，舊的內容不會蓋過新的。
- **App 進入背景時**（`ScreenshotOrganizerApp` 監聽 `scenePhase`）呼叫 `saveNow()`：不等 debounce，立刻排一次寫入，並向系統申請背景時間讓它寫完。
- **`JSONLibraryFile` 每次都整份寫入**，`changes` 參數只是傳給未來的增量儲存（SQLite）用。寫入使用 `.atomic`，先寫暫存檔再取代，寫到一半當機不會留下半個檔案。

### 3.3 誰會修改資料

| 來源 | 操作 | 位置 |
|------|------|------|
| Photos 同步（首次匯入、回到前景、Photos 變更通知、下拉更新） | `sync(with:)` | `LibraryStore` |
| 處理佇列 | `setRecognition`（每張 OCR 完成）、`applyClassification`（每張分類完成） | `ScreenshotProcessor` |
| 啟動 | `requeueOutdated` | `LibraryStore.init` |
| 資料夾 | `createFolder`、`renameFolder`、`deleteFolder`、`move` | `Sheets.swift`、`LibraryStore.deleteFolder` |
| 標籤 | `createTag`、`deleteTag`、`toggleTag`、`addTag`、`dismissFeatureTag` | `Sheets.swift`、`TagsScreen.swift` |
| 從 App 移除 | `hide` | `AppShell.swift` |

首次匯入時，每張截圖完成 OCR 和分類都會觸發存檔。單張的處理時間通常超過 400ms，所以大約每張寫一次整個檔案。這是 JSON 方案的已知限制，換成 SQLite 增量寫入後才會解決。

---

## 4. 版本與升級

### 4.1 調整分類規則（不需要改 schema）

改了規則、門檻或之後的 prompt，**只要調高 `ClassificationPipeline.version`**。下次啟動時，`requeueOutdated` 會把 `classifierVersion` 比較舊的自動分類送回處理中重新分類；使用者放入的（`placement == user`）不動。

### 4.2 修改資料結構

先看相容性，再決定要不要調高 `schemaVersion`：

- **新版讀舊檔**：一定要能讀，使用者升級 App 時就會發生。
- **舊版讀新檔**：只有在使用者裝回舊版時才會發生，很少見。讀不懂時會改名保留後重新開始（見 3.1），不會遺失資料，但 App 會從頭匯入。

| 變動 | 新版讀舊檔 | 舊版讀新檔 | 做法 |
|------|------|------|------|
| 新增欄位 | 用預設值 | 忽略不認得的 key | 加進 `CodingKeys` **和** `init(from:)`，用 `decodeIfPresent` 加預設值；列舉欄位用 `decodeKnownValue` / `decodeKnownValues`。不用調高版本號 |
| 刪除欄位 | 忽略多出來的 key | 用預設值 | 直接拿掉。不用調高版本號 |
| 新增列舉值（例如 `FeatureTag.email`、新的內建類別） | 沒影響 | 依 §2.2 的規則略過或重設 | 不用調高版本號。新的內建類別在讀檔時會自動補上資料夾 |
| 刪除列舉值（例如拿掉 `BuiltInCategory.coupon`） | 依 §2.2 的規則略過或重設 | 沒影響 | 不用調高版本號，但要確認這個結果可以接受：被刪掉的內建類別的資料夾會變成一般資料夾、截圖留在裡面；自動標籤直接消失 |
| 列舉值改名 | 舊的值會被當成不認得 | 同左 | **要轉換**，否則等於「刪掉舊的、新增新的」，資料會被重設 |
| 欄位改名、改型別、改 `Placement` 的結構 | 讀取失敗或資料遺失 | 同左 | **要轉換** |

**`Shot`、`Folder`、`Library` 都是手寫的 `init(from:)`**：新增欄位時只加屬性、忘了加進 `CodingKeys`，編譯會過，但這個欄位**不會被寫進檔案**，重新啟動就不見了。加欄位時一定要同時改 `CodingKeys`、`init(from:)`，並在 `LibraryCodecTests` 加一個往返測試。

**需要轉換時**（目前還沒有轉換程式，第一次需要時再建）：

1. 調高 `LibraryCodec.currentSchemaVersion`。
2. 轉換必須在**原始 JSON** 上做，不能放在 `init(from:)` 裡：新版的 `init(from:)` 讀到舊結構會先失敗，輪不到轉換。做法是在 `LibraryCodec.decode` 裡用 `JSONSerialization` 讀成字典，依序套用每一版的轉換（v0→v1、v1→v2…），轉完再交給 `JSONDecoder`。每一版一個函式，不要寫成一條長 `switch`。
3. 把轉換前的檔案存成 fixture（例如 `library-v1.json`），測試轉換後的內容。

調高版本號後，舊版 App 讀到新檔一律當成讀不懂。所以**能靠預設值或略過不認得的值處理的變動，就不要調高版本號**。

已知的邊界情況：新增內建類別後裝回舊版、再升級回新版。舊版會把那個資料夾讀成一般資料夾並寫回檔案；新版讀到時已經沒有那個內建類別的資料夾，會再建一個同名的內建資料夾，畫面上出現兩個同名資料夾。這需要裝回舊版才會發生，目前不處理。

### 4.3 OCR 演算法改變

目前 `Shot` 沒有記錄是用哪一版 OCR 辨識的，這是刻意的：在第一次真的要改 OCR 之前，這個欄位不會有人用。因為所有欄位都有預設值，到時候再加，效果和現在先加完全一樣。

**什麼時候算「OCR 改變」**：改動下面任何一項，已經辨識過的截圖就和新的截圖結果不一致：

- 辨識語言（`VisionScreenRecognizer.languages`）、`recognitionLevel`、`usesLanguageCorrection`
- 狀態列的過濾範圍（`TextBlockFilter.statusBarHeight`）
- 文字行的排序規則（`VisionScreenRecognizer.recognize` 結尾的 `sorted`）
- 條碼偵測的方式
- 換成其他 Vision API（例如 iOS 26 的新文字辨識 API）

**第一次改 OCR 時要做的事：**

1. **加上版本號**：`Shot` 加 `ocrVersion`（`decodeIfPresent`，預設 `0`）；OCR 那邊加一個目前版本的常數，設為 `1`；`setRecognition` 成功時寫入目前版本。不需要調高 `schemaVersion`（見 4.2）。舊檔讀進來全是 `0`，所以全部會被視為過期。
2. **啟動時把過期的截圖重新排進 OCR 佇列**：仿照 `requeueOutdated` 加一個方法，把 `ocrVersion` 較舊的截圖設回 `recognition = .pending`，並且**把 `recognitionAttempts` 歸零**。否則以前失敗過 3 次的截圖永遠不會再辨識。
3. **分類也要重做**：文字變了，自動分類（`placement == auto`）可能就不對了，要一起送回處理中（`placement = .pending`）。使用者放入的（`user`）維持不動。
4. **使用者放入的截圖，自動標籤要另外更新**：`applyClassification` 只處理「處理中」的截圖，使用者放入的截圖不會經過它，所以重新辨識後「含連結」「含日期」這些自動標籤不會跟著更新。要把自動標籤的更新從 `applyClassification` 拆出來，讓每張截圖辨識完就重算一次（仍要扣掉 `dismissedFeatureTags`）。
5. **不要一次把所有截圖丟回處理中**：重新辨識要重新取原圖跑 Vision，iCloud 上的原圖還得重新下載。幾千張會跑很久、很耗電，而且這段時間所有截圖都會出現在「處理中」。比較好的做法是：
   - 舊的 `blocks`、`barcodes` 在新結果出來前保留，搜尋和標題照常可用；
   - 只有自動分類的截圖才回到處理中，或乾脆保留原本的分類，等新文字出來再重新分類；
   - 新匯入的截圖優先，舊的在 App 開著時慢慢處理。

   這部分會改變處理佇列和「處理中」的意義，動工前先寫規劃文件。
6. **測試**：用沒有 `ocrVersion` 的 fixture（`library-v0.json`）確認全部被重新排入；確認使用者放入的截圖分類不變，但自動標籤有更新。

換成 SQLite 之後，OCR 結果會放在獨立的 `recognition` 表，並帶有 `ocrVersion`（見規劃文件），上面第 1、2 步會改成在那張表上處理，第 3 到 5 步的考量不變。

---

## 5. 限制與注意事項

- **OCR 文字是明文**：截圖裡的密碼、帳號、地址都會原樣存在 `blocks`。檔案在 App sandbox 裡，使用系統預設的檔案保護等級，沒有另外加密。
- **整份常駐記憶體、整份寫入**：幾千張截圖沒問題；上萬張或加上 embedding 之後，要換成 SQLite。
- **最多會掉最後 400ms 的修改**：App 在 debounce 期間直接被系統終止（沒有先進背景，例如 crash）時，最後那筆修改不會寫入。
- **備份檔不會自動清除**：`library.unreadable-*.json` 會一直留在 `Application Support/`，需要時手動處理。

---

## 6. 除錯

在模擬器上找到檔案：

```bash
open "$(xcrun simctl get_app_container booted com.chiawei.albumOrganizer data)/Library/Application Support"
```

查看儲存相關的 log（subsystem 是 bundle id，category 是 `persistence`）：

```bash
xcrun simctl spawn booted log show --last 10m --predicate 'subsystem == "com.chiawei.albumOrganizer" AND category == "persistence"'
```

手動修改 `library.json` 之前先關掉 App，否則記憶體裡的內容會在下次存檔時蓋掉你的修改。
