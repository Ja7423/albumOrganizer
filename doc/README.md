# 截圖整理（albumOrganizer）文件目錄

讀取 iOS「螢幕截圖」相簿，在裝置上辨識圖中文字、自動分類，讓使用者用資料夾、標籤、全文搜尋整理截圖。**相簿原檔永遠不會被移動或修改**，資料夾、標籤、辨識結果都只存在 App 裡。

| 項目 | 內容 |
|------|------|
| 平台 | iOS 26.0+（`IPHONEOS_DEPLOYMENT_TARGET`），只支援淺色模式 |
| UI | SwiftUI，`@Observable` 狀態，預設 actor isolation 為 `MainActor` |
| 領域邏輯 | 本地 Swift Package `ScreenshotKit`（iOS 17 / macOS 14，可單獨 `swift test`） |
| 儲存 | SQLite（GRDB 7）：`Application Support/library.sqlite`，本地 Swift Package `LibraryPersistence`（見 [storage.md](storage.md)） |
| 文件更新日期 | 2026-10-11（對應 `feature/llm-refinement`） |

## 文件索引

| 文件 | 內容 |
|------|------|
| [README.md](README.md)（本文件） | 架構、資料流、使用流程、目錄結構 |
| [storage.md](storage.md) | 資料儲存：SQLite 的架構、schema、讀寫與 migration 機制 |
| [classification.md](classification.md) | 自動分類：OCR、訊號、規則層、Apple Intelligence 補判、截圖狀態、重新分類 |
| [spec/tab-screenshots.md](spec/tab-screenshots.md) | 「截圖」tab：所有截圖 grid、篩選 chip、批次選取 |
| [spec/tab-folders.md](spec/tab-folders.md) | 「資料夾」tab：資料夾列表、處理中／未分類、新增／改名／刪除 |
| [spec/tab-tags.md](spec/tab-tags.md) | 「標籤」tab：自動標籤、我的標籤、新增／刪除 |
| [spec/tab-search.md](spec/tab-search.md) | 「搜尋」tab：全文搜尋、結果高亮 |
| [spec/shared-detail-and-sheets.md](spec/shared-detail-and-sheets.md) | 四個 tab 共用的部分：詳細頁、移到資料夾／標籤 sheet、命名對話框、批次列、toast |
| [plan/](plan/) | 各功能的規劃紀錄（決策與理由） |

---

## 1. 架構總覽

整個專案分成三個部分：App target、領域層 `ScreenshotKit`、儲存層 `LibraryPersistence`。

```
┌──────────────────────────── App target（albumOrganizer/ScreenshotOrganizer）────────────────────────────┐
│                                                                                                        │
│  Views ──讀取/呼叫──▶  Store                         Services                                          │
│  (SwiftUI 畫面)        ├─ LibraryStore  ─────────▶   ├─ PhotoLibraryService（Photos 唯讀存取、縮圖快取）  │
│                        │  (領域狀態 + 存檔 + 同步)    ├─ ScreenshotProcessor（辨識 → 分類的工作佇列）     │
│                        ├─ UIState                    └─ VisionScreenRecognizer（Vision OCR + 條碼）      │
│                        │  (導航與暫時 UI 狀態)                                                         │
│                        └─ DetailSession                                                                │
│                           (詳細頁可翻頁的 id 快照)                                                      │
│  Theme（Palette / Typeface / 按鈕樣式 / 共用元件）                                                       │
└───────────────────────┬───────────────────────────────────────────────────────┬────────────────────────┘
                        │ import                                                │ import
                        │        ┌──── LibraryPersistence（Packages/LibraryPersistence）────┐
                        │        │  SQLiteLibraryDatabase · LibraryMigrator · Records · GRDB │
                        │        └───────────────────────────┬──────────────────────────────┘
                        ▼                                    │ import
┌───────────────────────────── ScreenshotKit（Packages/ScreenshotKit）─────────────────────────────────────┐
│  Library（唯一的資料根：shots / folders / tags / hiddenShotIDs / deletedBuiltIns，所有規則都在這）        │
│  Shot · Folder · Placement · TextBlock · Scope · FeatureTag · BuiltInCategory                          │
│  Search（Library.search）· Signals（SignalExtractor）· FeatureDetector                                  │
│  Classification：ScreenshotClassifier 協定 · ClassificationPipeline · RuleClassifier                    │
└────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 1.1 ScreenshotKit（純值型別領域層）

不依賴 Photos、Vision、SwiftUI，所有「資料夾／標籤／分類」的規則都在這裡，有單元測試覆蓋。

| 檔案 | 職責 |
|------|------|
| `Library.swift` | 資料根。`Scope` 篩選、Photos 同步（`sync(with:)`）、資料夾 CRUD、標籤 CRUD、`hide`（從 App 移除） |
| `Library+Classification.swift` | 待分類與待補判清單、`classifierInput`、`applyClassification` / `applyRefinement`（使用者手動搬過就不覆蓋）、`requeueOutdated` |
| `LibraryCodec.swift` | 舊格式 `library.json` 的編解碼，現在只用於第一次啟動時匯入 |
| `LibraryChanges.swift` | `Library.changes(since:)`：比對兩份 Library，算出哪些截圖、資料夾、標籤有變動 |
| `Models.swift` | `Shot`、`Folder`、`TextBlock`、`NormalizedRect`、`AssetInfo`、`TextBlockFilter`（去掉狀態列文字） |
| `Placement.swift` | `Placement`：`.pending`（處理中）/ `.auto(source, version, isRefined)` / `.user`（鎖定） |
| `Category.swift` | 13 個內建類別 `BuiltInCategory`（key 固定、名稱只是顯示） |
| `FeatureTag.swift` / `FeatureDetector.swift` | 自動標籤：含連結、QR code、含電話、含日期、含地址 |
| `Signals.swift` | 從文字與版面算出訊號（連結、電話、日期、地址、條碼數、對話泡泡、程式符號密度） |
| `Search.swift` | 全文搜尋，回傳切好前後文的 `SearchHit` |
| `Classification/*` | 分類器協定、依序執行各層的 `ClassificationPipeline`（目前 `version = 10`）、規則層 `RuleClassifier`、學習層的訓練資料 `TrainingSet`、Apple Intelligence 的 prompt `LLMCategoryPrompt`（見 [classification.md](classification.md)） |
| `Resources/seed-samples.json` | 合成的 OCR 樣本：規則層的回歸測試集，也是學習層的種子樣本 |

`LibraryPersistence`（`Packages/LibraryPersistence`，儲存層）依賴 `ScreenshotKit` 與 GRDB，是專案裡唯一碰到 SQLite 的地方：

| 檔案 | 職責 |
|------|------|
| `LibraryPersisting.swift` | 儲存層協定（`load` / `save`）與 `LibraryLoadResult`；`Logger.persistence` |
| `SQLiteLibraryDatabase.swift` | 協定的 SQLite 實作：開啟資料庫、跑 migration、匯入舊的 `library.json` |
| `LibraryMigrator.swift` | 所有 schema 變更 |
| `LibraryRows.swift`、`Records.swift` | `Library` 與各張表的 row 互相轉換；只寫有變動的 row |
| `JSONLibraryFile.swift` | 讀舊的 `library.json`（只用於匯入） |

### 1.2 App target

| 目錄 | 檔案 | 職責 |
|------|------|------|
| `App/` | `ScreenshotOrganizerApp.swift` | 建立 `LibraryStore`、`UIState` 放進 environment；`RootView` 依 `store.phase` 切換 Onboarding / AppShell；監聽 scenePhase（進背景立即存檔並備份到 iCloud、回前景重新同步） |
| `Store/` | `LibraryStore.swift` | 持有 `Library`；首次匯入流程（含 iCloud 還原詢問）；Photos 同步；餵處理佇列；`mutate` 後 400ms debounce 存檔（沒有變動就不寫）；套用備份還原 |
| | `UIState.swift` | 目前 tab、截圖 tab 的 chip、各 tab 的 NavigationStack path、批次選取、詳細頁、sheet、dialog、toast |
| | `DetailSession.swift` | 詳細頁開啟時拍下的 id 清單與目前頁 |
| `Services/` | `PhotoLibraryService.swift` | 權限、撈出所有螢幕截圖、變更通知、縮圖串流（`PHCachingImageManager` + 64MB `NSCache`）、原圖資料 |
| | `ScreenshotProcessor.swift` | 一次處理一張：先 OCR、再用規則分類；主佇列清空後，對未分類的截圖用 Apple Intelligence 補判；支援把某張插到最前面（`prioritize`） |
| | `FoundationModelsClassifier.swift` | 呼叫裝置上的 Foundation Models 補判；分辨「這張判斷不了」和「現在判斷不了」 |
| | `BackupService.swift` | iCloud 備份與還原的流程：上傳閘門、打包快照、對應截圖、暫存還沒找到的截圖（見 [storage.md §7](storage.md#7-icloud-備份與還原)） |
| | `BackupRemote.swift` | `CloudKitBackupRemote`：私有資料庫裡兩個輪流覆寫的快照 record |
| | `PendingRestoreStore.swift` | 讀寫 `pending-restore.json` |
| | `TextRecognizer.swift` | `VisionScreenRecognizer`：繁中 + 英文 OCR、條碼偵測，在 detached task 執行 |
| `Views/Shell/` | `AppShell.swift` | Tab 切換、TabBar / BatchBar、疊上詳細頁、SheetHost、NameDialog、Toast |
| | `Sheets.swift` | 「移到資料夾」「標籤」「設定」sheet 與命名對話框 |
| `Views/Settings/` | `BackupSection.swift` | 設定 sheet 的 iCloud 備份區塊（從資料夾 tab 右上角齒輪開啟） |
| `Views/Library/` | `ShotGridScreen.swift` 等 | 四個 tab 的畫面（見各 spec） |
| `Views/Detail/` | `ShotDetailScreen.swift`、`ShotPage.swift` | 詳細頁與單頁（含文字區塊選取） |
| `Views/Onboarding/` | `OnboardingView.swift` | 歡迎 → 權限 →（還原 iCloud 備份）→ 匯入 |
| `Views/Common/` | `AssetImage`、`LimitedAccessBanner`、`ShotFormat` | 共用元件與日期／分類方式格式化 |
| `Theme/` | `Classical.swift`、`Components.swift`、`ButtonStyles.swift` | 設計 token（顏色、間距、圓角、陰影、字型）與元件 |


### 1.3 狀態與資料流

```
Photos 相簿 ──fetchScreenshots──▶ LibraryStore.syncWithPhotos()
                                   └─ Library.sync(with:)    新的截圖以 .pending 加入、Photos 刪掉的移除
                                   └─ ScreenshotProcessor.start()
                                         ├─ 取原圖 → VisionScreenRecognizer → Library.setRecognition
                                         ├─ classifierInput → ClassificationPipeline（規則）→ FeatureDetector
                                         │    → Library.applyClassification（放進資料夾 + 加自動標籤）
                                         └─ 主佇列清空後：未分類的截圖 → Apple Intelligence
                                              → Library.applyRefinement（放進資料夾，或標記為已補判）
View 操作 ──store.mutate { $0.xxx }──▶ Library 改變 ──@Observable──▶ 所有畫面重繪
                                   └─ 400ms 後寫入有變動的部分（進背景時立即寫）
View 操作 ──ui.xxx──▶ UIState（導航、選取、sheet、toast）
```

規則：

- **Views 不直接碰 `PhotoLibraryService`**，唯一例外是 `AssetImage` 讀縮圖、`ShotImage` 分享原圖。
- **所有資料修改都走 `store.mutate`**，規則寫在 `Library` 的 mutating 方法裡。
- **導航狀態集中在 `UIState`**，sheet 透過 `ui.sheetTargets` 知道要作用在批次選取還是詳細頁目前這張。

### 1.4 截圖的生命週期

| 狀態 | 判斷 | 出現在哪 |
|------|------|------|
| 處理中 | `placement == .pending` | 資料夾 tab 的「處理中」列；不出現在「未分類」 |
| 自動分類 | `placement == .auto`，`source != nil` | 對應的內建資料夾；詳細頁資料夾按鈕顯示 ✦ 圖示 |
| 自動判斷不出來 | `placement == .auto`，`source == nil` | 未分類；`isRefined == false` 的會在背景用 Apple Intelligence 補判 |
| 使用者放入（鎖定） | `placement == .user` | 使用者選的資料夾（或未分類）；之後永不自動重分類 |
| 從 App 移除 | id 在 `hiddenShotIDs` | 哪裡都不出現；同步也不會加回，Photos 原檔保留 |

自動分類的完整規則見 [classification.md](classification.md)。OCR 失敗會在下一輪重試，最多 3 次（`Shot.maxRecognitionAttempts`），之後當作沒有文字直接分類。`ClassificationPipeline.version` 調高時，App 啟動會把舊版本自動分類的截圖送回處理中重新分類（使用者放入的不動）。

### 1.5 匯入與檔案處理

App 不複製、不搬移、不修改任何照片檔案，只讀取 Photos，並在自己的索引裡記錄結果。

| 資料 | 怎麼取得 | 放在哪 |
|------|------|------|
| 截圖清單 | `fetchScreenshots()` 用 `mediaSubtypes & photoScreenshot` 篩選，新到舊；只轉成 `AssetInfo`（`localIdentifier`、建立時間、像素尺寸），不讀圖片內容 | 轉成 `Shot` 存進資料庫（`library.sqlite`） |
| OCR 用的原圖 | `imageData(for:)` 以 `requestImageDataAndOrientation` 取原始解析度資料；原圖在 iCloud 時會下載（`isNetworkAccessAllowed`） | 只在記憶體，交給 Vision 辨識完就丟掉；辨識全程在裝置上，不上傳 |
| OCR 結果 | `VisionScreenRecognizer`：繁中 + 英文文字、條碼（條碼失敗不影響文字）；座標轉成左上原點、由上到下排序、去掉狀態列 | `Shot.blocks` / `barcodes`，存進資料庫的 `recognition` 表 |
| 畫面上的縮圖與大圖 | `images(for:targetSize:)` 向 `PHCachingImageManager` 即時要，先給低解析度版本再給最終版本 | 最終版本放在 64MB `NSCache`（記憶體），不寫進硬碟 |

資料庫裡只有識別碼、尺寸、日期、辨識文字、資料夾、標籤與分類狀態，**沒有任何圖片**。Photos 刪掉的截圖會在下次同步時從 Library 移除。

資料庫的 schema、讀取失敗時的保護、寫入時機與 migration，見 [storage.md](storage.md)。

首次匯入的進度條（`LibraryStore.ImportProgress`）比重是掃描 20%、OCR 70%（已辨識 / 總數）、分類 10%。辨識與分類實際上是同時進行的：佇列清空時才把步驟切到「分類」，停 600ms 後顯示「完成」，讓使用者看得到這一步。

---

## 2. 使用流程

### 2.1 首次啟動（Onboarding）

```
歡迎頁 ──「開始整理」──▶ 權限頁（一進來就跳系統權限詢問）
                           ├─ 拒絕 → 顯示說明 +「前往設定」
                           └─ 允許（完整或部分）──▶ iCloud 有備份？
                                                      ├─ 有 ──▶ 還原頁：「還原備份」或「從頭開始，不還原」──▶ 匯入頁
                                                      └─ 沒有、iCloud 不可用或 5 秒內沒有回應 ──▶ 匯入頁
匯入頁：掃描「螢幕截圖」相簿 → 辨識圖中文字（n / total）→ 自動分類 → 完成
  ├─ 超過 20 張時可按「先進入相簿，在背景繼續辨識」提早進入
  └─ 完成後顯示「已分類 X 張，未分類 Y 張」→「進入相簿」
```

完成後寫入 `UserDefaults["didFinishOnboarding"]`。下次啟動若已完成且仍有照片權限，直接進入 App；權限被收回則回到歡迎頁。

### 2.2 日常使用

| 我想… | 怎麼做 | 詳見 |
|------|------|------|
| 瀏覽所有截圖 | 截圖 tab，用 chip 篩選未分類／自動標籤／我的標籤 | [截圖 tab](spec/tab-screenshots.md) |
| 依類別找 | 資料夾 tab → 點資料夾 | [資料夾 tab](spec/tab-folders.md) |
| 依標籤找 | 標籤 tab → 點標籤 | [標籤 tab](spec/tab-tags.md) |
| 用圖中文字找 | 搜尋 tab 輸入關鍵字 | [搜尋 tab](spec/tab-search.md) |
| 看大圖、左右翻、複製文字、分享 | 任一列表點截圖進詳細頁 | [共用規格 §1](spec/shared-detail-and-sheets.md#1-詳細頁shotdetailscreen) |
| 改一張的資料夾或標籤 | 詳細頁下方資訊列 | [共用規格 §2](spec/shared-detail-and-sheets.md#2-移到資料夾-sheet) |
| 一次整理很多張 | 截圖 tab 或任一資料夾／標籤 grid 按「選取」→ 下方批次列 | [共用規格 §4](spec/shared-detail-and-sheets.md#4-批次列batchbar) |
| 從 App 移除 | 批次選取 → 垃圾桶（相簿原檔保留） | 同上 |

### 2.3 背景與同步

- App 回到前景、或 Photos 通知相簿變更時，自動重新同步並繼續處理佇列。
- 在任一截圖 grid 下拉可手動更新：在背景重新讀取相簿後同步（見 [截圖 tab §2.5](spec/tab-screenshots.md#25-下拉更新)）。
- 部分照片權限時，截圖 tab 與資料夾 tab 頂端顯示提示，可「選取更多截圖」或「前往設定」。
- 開啟某張處理中截圖的詳細頁時，它會被插到佇列最前面。
- App 進背景時備份到 iCloud（內容沒變就不上傳）；資料夾 tab 右上角齒輪 → 設定，可以立即備份或從備份還原。
- 還原時還沒出現在這台裝置的截圖（例如 iCloud 照片還在下載），之後每次相簿變更都會再比對一次，最多 30 天。

---

## 3. 目錄結構

```
albumOrganizer/
├─ albumOrganizer.xcodeproj
├─ albumOrganizer/
│  ├─ Info.plist                    照片權限說明、自訂字型、淺色模式
│  └─ ScreenshotOrganizer/
│     ├─ App/                       進入點與 RootView
│     ├─ Store/                     LibraryStore、UIState、DetailSession
│     ├─ Services/                  Photos、處理佇列、Vision、學習層的訓練排程、iCloud 備份
│     ├─ Views/
│     │  ├─ Shell/                  AppShell、TabBar、BatchBar、Toast、Sheets、NameDialog
│     │  ├─ Library/                ShotGridScreen、FoldersScreen、TagsScreen、SearchScreen
│     │  ├─ Detail/                 ShotDetailScreen、ShotPage
│     │  ├─ Onboarding/
│     │  ├─ Settings/               設定 sheet 的 iCloud 備份區塊
│     │  └─ Common/                 AssetImage、LimitedAccessBanner、ShotFormat
│     ├─ Theme/                     Palette、Typeface、Space、Radius、元件、按鈕樣式
│     └─ Resources/Fonts/           Lora、Cormorant Garamond、Noto Serif TC（OFL）
├─ Packages/ScreenshotKit/
│  ├─ Sources/ScreenshotKit/        領域模型與分類（見 §1.1）
│  ├─ Sources/ScreenshotKitLLM/     Apple Intelligence 補判（Foundation Models）
│  ├─ Sources/ScreenshotKitML/      學習層：在手機上用 Create ML 訓練的文字分類器
│  ├─ Sources/ClassificationEval/   評估工具 classification-eval
│  ├─ Tests/ScreenshotKitTests/     Library、編解碼、變動比對、搜尋、訊號、規則分類、pipeline、補判、prompt、訓練資料測試 + fixtures
│  └─ Tests/ScreenshotKitMLTests/   學習層的訓練、存讀、分類測試
├─ Packages/LibraryPersistence/
│  ├─ Sources/LibraryPersistence/   SQLite 儲存層（見 storage.md）
│  └─ Tests/LibraryPersistenceTests/ 讀寫、migration、舊 JSON 匯入測試（in-memory 資料庫）
└─ doc/
   ├─ README.md                     本文件
   ├─ storage.md                    資料儲存（schema、讀寫、版本升級）
   ├─ classification.md             自動分類（規則層、學習層、Apple Intelligence 補判）
   ├─ spec/                         各 tab 規格
   └─ plan/                         功能規劃紀錄
```

## 4. 開發

```bash
swift test --package-path Packages/ScreenshotKit
swift test --package-path Packages/LibraryPersistence
```

- App target 沒有測試；可測的規則請放進 `ScreenshotKit`，儲存相關的放進 `LibraryPersistence`。
- 改了分類規則、門檻、學習層的訓練方式或 Apple Intelligence 的 prompt，要調高 `ClassificationPipeline.version`，既有的自動分類結果才會重做（見 [classification.md §8](classification.md#8-調整與擴充)）。
- 新增功能前先在 `doc/plan/` 留規劃紀錄，做完後更新對應的 `doc/spec/`。
