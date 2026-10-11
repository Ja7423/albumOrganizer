# Feature Plan：Apple Intelligence 補判（FoundationModelsClassifier）

| 項目 | 內容 |
|------|------|
| 規劃日期 | 2026-10-11 |
| 規劃方式 | 直接規劃，加上 3 個產品問題 |
| 目前分支 | `main`，實作時開 `feature/llm-refinement` |
| 狀態 | 已實作 |
| 上層計畫 | [截圖自動分類](screenshot-auto-classification-2026-10-07.md) 的第 3 步 |

## 需求摘要

在裝置上用 Apple Foundation Models 分類規則層判斷不出來的截圖，把它們從「未分類」放進 12 個內建分類資料夾。LLM 不在主佇列裡跑，而是在規則分類跑完之後，對「未分類、還沒補判過」的截圖做第二階段的**補判**（refinement）。首次匯入的速度維持不變。

成功的樣子：
- 首次匯入完成的時間和現在一樣。
- 之後未分類的截圖數量明顯減少，詳細頁顯示「自動分類 · Apple Intelligence」。
- 不支援 Apple Intelligence 的裝置行為和現在完全一樣。之後模型變得可用時，會自動補判還沒判過的未分類截圖。

### 範圍

- **In scope**
  - `FoundationModelsClassifier`（app target）：檢查可用性、guided generation、把錯誤分成「這張判斷不了」和「現在判斷不了」
  - `LLMCategoryPrompt`（ScreenshotKit，純函式）：instructions、prompt、可選類別、把模型的回答轉成 `ClassifierVerdict`
  - 補判狀態：`AutoPlacement.isRefined`、`Library.pendingRefinementIDs`、`Library.applyRefinement`
  - SQLite migration：`shot.isRefined` 欄位
  - `ScreenshotProcessor`：主佇列清空後接著跑補判佇列，主佇列的工作永遠優先
  - `ClassificationPipeline.classifyOrThrow`：讓呼叫端分辨「沒有答案」和「這次失敗」
- **Out of scope**
  - 分類到使用者自建的資料夾（Q2：等 kNN）
  - 不可用時的 UI 提示（Q3：安靜略過）
  - kNN 層，以及「kNN 多了樣本」這個重新分類時機
  - 補判在 App 進入背景後繼續跑（`BGTaskScheduler`）
  - 評估集與門檻調校（沿用上層計畫的風險項目）

## 決策紀錄

| # | 決策 | 選擇 | 理由 / 被放棄的選項 |
|---|------|------|------|
| D1 | LLM 什麼時候跑 | 分兩階段：主佇列只跑規則；主佇列清空後，對未分類的截圖補判 | 使用者選擇（Q1）。放棄：當成 pipeline 的第二層放在主佇列，首次匯入會多出幾十分鐘 |
| D2 | 自建資料夾 | 這次不支援，只分到內建分類 | 使用者選擇（Q2）。自建資料夾沒有 hint，只靠名稱容易分錯 |
| D3 | 不可用時 | 安靜略過，可用之後自動補跑 | 使用者選擇（Q3）。對應上層計畫 D10「LLM 變得可用時，只重新分類未分類的截圖」 |
| D4 | 怎麼記錄「補判過」 | `AutoPlacement.isRefined: Bool` | 預設值。只有 `.auto` 的截圖需要這個標記；重新排入佇列時會產生新的 `AutoPlacement`，標記自然歸零，不需要另外的版本號 |
| D5 | 版本號 | 繼續只用 `ClassificationPipeline.version`；改 prompt 也提高這個版本號。這次**不提高**版本號 | 預設值。改版會重排所有自動分類，規則層很便宜，未分類的截圖會再補判一次。新增 LLM 層本身不需要改版：既有的未分類截圖解碼後 `isRefined == false`，會自然被補判 |
| D6 | LLM 的信心分數 | 回答時同時選一個 `certainty`（high / medium / low），分別對應 0.9 / 0.6 / 0.3；門檻 0.6。另外有一個 `none` 選項，表示「都不符合」 | 預設值，等評估集調整。只回答類別的話，門檻就沒有作用；`none` 和 `low` 讓模型可以表示「沒把握」，符合「錯放比不放更糟」 |
| D7 | 錯誤分類 | 這張判斷不了（guardrail、refusal、context 超過上限、語言不支援、解碼失敗、guide 不支援）→ 回傳 `nil`，標記為已補判。現在判斷不了（模型不可用、assets 不可用、rate limit、同時請求、其他錯誤）→ 丟出錯誤，這一輪補判停止，下一輪再試 | 預設值。前者重試結果也一樣；後者重試可能成功 |
| D8 | 什麼時候「下一輪」 | 沿用現有的 `ScreenshotProcessor.start()` 時機：啟動、回到前景同步完、刪除資料夾 | 預設值。不額外監聽 `SystemLanguageModel` 的可用性變化；回到前景就會重試，對使用者夠快 |
| D9 | Model use case | `SystemLanguageModel(useCase: .general)` | 預設值。`.contentTagging` 偏向自由產生標籤，這裡是從固定選項中挑一個。有評估集後可以 A/B |
| D10 | 送進模型的文字 | `Shot.allText` 取前 1500 個字元 | 預設值。模型的 context 是 4096 tokens，中文大約一字一 token，要留空間給 instructions 和 schema。超過上限時視為「這張判斷不了」 |
| D11 | Session | 每張截圖建立一個新的 `LanguageModelSession` | 預設值。共用 session 的 transcript 會越來越長，前一張的內容也會影響下一張 |
| D12 | 沒有文字的截圖 | 不補判 | 沿用上層計畫 D4 |

## 現況分析

- **最相似的既有功能**：主佇列的分類流程。
  - [ScreenshotProcessor.swift:78](../../albumOrganizer/ScreenshotOrganizer/Services/ScreenshotProcessor.swift)：`classify(_:)` 先組出輸入、呼叫 pipeline，再用 `mutate` 寫回。補判照這個形狀寫。
  - [Library+Classification.swift:38](../../Packages/ScreenshotKit/Sources/ScreenshotKit/Library+Classification.swift)：`applyClassification` 用 `guard shot.isProcessing` 確保手動搬移優先。`applyRefinement` 用同樣的方式，檢查截圖還在「自動、未分類」。
  - [RuleClassifier.swift](../../Packages/ScreenshotKit/Sources/ScreenshotKit/Classification/RuleClassifier.swift)：`ScreenshotClassifier` 的實作範例。
- **可重用**
  - `BuiltInCategory.hint`、`defaultName`（[Category.swift:37](../../Packages/ScreenshotKit/Sources/ScreenshotKit/Category.swift)）：當初就是為了 LLM prompt 加的
  - `Library.classifierInput(for:)`：已經會排除被刪除的內建分類
  - `ClassificationPipeline` 的門檻、排除邏輯
  - `ClassifierSource.llm` 和它的顯示文字「Apple Intelligence」（[ShotFormat.swift:46](../../albumOrganizer/ScreenshotOrganizer/Views/Common/ShotFormat.swift)）：已經存在，UI 不用改
  - `Library.update(_:_:)`
- **需要新增的資料來源**：`FoundationModels`（iOS 26，只有 app target 能用；app 的 deployment target 已經是 26.0）。ScreenshotKit 是 iOS 17 / macOS 14，不能引用它。
- **會被影響的既有程式碼**
  - `Placement.swift`：`AutoPlacement` 多一個欄位，JSON 解碼要相容舊資料
  - `LibraryPersistence`：`ShotRecord`、`LibraryMigrator` 新增 migration
  - `ScreenshotProcessor`、`LibraryStore.init`
  - `ScreenshotClassifier` 協定的文件註解：寫清楚 `nil` 和 throw 的差別

### Foundation Models API（iOS 26.5 SDK）

- `SystemLanguageModel.availability`：`.available` / `.unavailable(.deviceNotEligible | .appleIntelligenceNotEnabled | .modelNotReady)`
- `DynamicGenerationSchema(name:anyOf: [String])`：可以在執行時決定可選的值，所以被刪除的內建分類可以直接從選項中拿掉（`@Generable` enum 做不到）
- `LanguageModelSession.respond(to:schema:options:)` → `GeneratedContent`，用 `value(String.self, forProperty:)` 取值
- `GenerationOptions(sampling: .greedy)`：同樣的輸入得到同樣的結果
- `GenerationError` 的 case：`exceededContextWindowSize`、`assetsUnavailable`、`guardrailViolation`、`unsupportedGuide`、`unsupportedLanguageOrLocale`、`decodingFailure`、`rateLimited`、`concurrentRequests`、`refusal`

## 架構設計

```
LibraryStore.init(pipeline: .standard, refinement: .appleIntelligence)
   │
   ▼
ScreenshotProcessor（@MainActor）
   nextWork():  .process(id)  ← 主佇列：OCR + 規則（優先）
                .refine(id)   ← 補判佇列：Library.pendingRefinementIDs
   │
   ├ pipeline.classify(input)               規則層，失敗就略過
   └ refinement.classifyOrThrow(input)      丟錯 → 這一輪補判停止
          │
          ▼
   ClassificationPipeline(layers: [Layer(FoundationModelsClassifier(), threshold: 0.6)])
          │
   FoundationModelsClassifier（app）── LLMCategoryPrompt（ScreenshotKit，純函式）
          │                                ├ instructions / prompt(for:)
          │                                ├ choices(excluding:)
          │                                └ verdict(category:certainty:)
          └ SystemLanguageModel / LanguageModelSession（FoundationModels）
```

各層的職責：

- **ScreenshotKit（純邏輯，macOS 上可以測）**
  - `LLMCategoryPrompt`：prompt 的所有文字、可選類別、把模型回答的字串轉成 verdict。不知道 FoundationModels 的存在。
  - `Library`：哪些截圖需要補判、套用補判結果。
  - `ClassificationPipeline.classifyOrThrow`：和 `classify` 一樣的門檻與排除規則，但會把錯誤傳出去。
- **App**
  - `FoundationModelsClassifier`：只負責和 FoundationModels 互動：檢查可用性、從 `LLMCategoryPrompt` 建出 schema、呼叫模型、分類錯誤。
  - `ScreenshotProcessor`：佇列排程。主佇列優先；主佇列清空時通知 `onIdle`（首次匯入的進度靠它），然後才開始補判。
- **Views**：不改。

### 補判的狀態

```
placement = .auto(source: nil, isRefined: false)    未分類，等待補判
   │ 補判：有答案
   ├──────────────▶ .auto(source: .llm, isRefined: true)，folderID = 類別資料夾
   │ 補判：沒答案 / 這張判斷不了
   ├──────────────▶ .auto(source: nil, isRefined: true)，留在未分類
   │ 補判：現在判斷不了
   └──────────────▶ 不變，下一輪再試
使用者搬移 → .user（補判寫回時發現已經不是自動未分類，忽略結果）
版本更新 → .pending → 規則層 → 新的 AutoPlacement（isRefined: false）
```

### 替代方案

| 方案 | 優點 | 缺點 | 結論 |
|------|------|------|------|
| `AutoPlacement` 存 `refinementVersion: Int?`，讓 LLM 有自己的版本號 | 改 prompt 時不用重跑規則層 | 多一個版本號要維護；規則層本來就只要幾毫秒 | 不採用（D5） |
| 可用性用協定方法 `isAvailable` 判斷，不用 throw | 少呼叫一次 | 協定多一個只有 LLM 需要的方法（違反 I）；可用性在判斷途中仍然可能改變，throw 的路徑還是要處理 | 不採用。不可用就丟出錯誤，第一張就會讓這一輪停下來，成本只有一次可用性檢查 |

## 檔案變更清單

| 動作 | 檔案 | 層 | 職責 |
|------|------|----|------|
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Classification/LLMCategoryPrompt.swift` | 純函式 | instructions、prompt、可選類別、回答轉換 |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Classification/ClassificationPipeline.swift` | 純邏輯 | 新增 `classifyOrThrow`；`classify` 和它共用判斷是否採用的邏輯 |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Classification/ScreenshotClassifier.swift` | 協定 | 文件註解寫清楚 `nil` 和 throw 的差別 |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Placement.swift` | Model | `AutoPlacement.isRefined`；解碼時沒有這個 key 就當作 `false` |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Library+Classification.swift` | 純邏輯 | `pendingRefinementIDs`、`applyRefinement` |
| 修改 | `Packages/LibraryPersistence/Sources/LibraryPersistence/LibraryMigrator.swift` | Persistence | migration `v3-shot-is-refined`：`shot.isRefined INTEGER NOT NULL DEFAULT 0` |
| 修改 | `Packages/LibraryPersistence/Sources/LibraryPersistence/Records.swift` | Persistence | `ShotRecord.isRefined` 的讀寫 |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Services/FoundationModelsClassifier.swift` | Service | `ScreenshotClassifier` 實作；`ClassificationPipeline.appleIntelligence` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Services/ScreenshotProcessor.swift` | Service | 補判佇列、主佇列優先、這一輪補判暫停 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Store/LibraryStore.swift` | Store | 注入 `refinement` |
| 修改 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/` | Test | 新增 `LLMCategoryPromptTests.swift`、`RefinementTests.swift`；`ClassificationPipelineTests` 加上 `classifyOrThrow` 的測試；`LibraryCodecTests` 加上舊 JSON 的解碼測試 |
| 修改 | `Packages/LibraryPersistence/Tests/LibraryPersistenceTests/SQLiteLibraryDatabaseTests.swift` | Test | `isRefined` 存取；v2 資料庫升級 |
| 修改 | `doc/plan/screenshot-auto-classification-2026-10-07.md` | Doc | 架構圖的第 3 步指向這份計畫 |

`.xcodeproj` 如果用 synchronized folder，新增檔案就不用改 pbxproj；如果不是，就要把 `FoundationModelsClassifier.swift` 加進 target。實作時確認。

## 介面草案

```swift
// ScreenshotKit/Classification/LLMCategoryPrompt.swift
/// Everything the on-device LLM layer says and understands, kept free of FoundationModels so it can be tested.
public enum LLMCategoryPrompt {
    /// The answer meaning "none of these fit".
    public static let noneKey = "none"
    public static let maxTextLength = 1500

    public enum Certainty: String, CaseIterable, Sendable {
        case high, medium, low
        public var confidence: Double { get }   // 0.9 / 0.6 / 0.3
    }

    /// Category keys the model may answer, deleted built-ins removed, plus `noneKey`.
    public static func choices(excluding excluded: Set<ClassificationTarget>) -> [String]
    /// Role, rules and one line per offered category: "receipt（收據）：發票、訂單明細、付款完成畫面".
    public static func instructions(excluding excluded: Set<ClassificationTarget>) -> String
    /// The screenshot text, cut to `maxTextLength`.
    public static func prompt(for text: String) -> String
    /// `nil` for `noneKey`, unknown keys or an unknown certainty.
    public static func verdict(category: String, certainty: String) -> ClassifierVerdict?
}

// ScreenshotKit/Classification/ClassificationPipeline.swift
public extension ClassificationPipeline {
    /// Like `classify`, but a throwing layer ends the run and its error propagates, so the caller can
    /// retry later instead of recording "no answer".
    func classifyOrThrow(_ input: ClassifierInput) async throws -> ClassifierVerdict?
}

// ScreenshotKit/Placement.swift
public struct AutoPlacement: Codable, Hashable, Sendable {
    public var source: ClassifierSource?
    public var classifierVersion: Int
    /// The refinement pass (on-device LLM) already looked at this screenshot.
    public var isRefined: Bool

    public init(source: ClassifierSource?, classifierVersion: Int, isRefined: Bool = false)
}

// ScreenshotKit/Library+Classification.swift
public extension Library {
    /// Automatic screenshots still in 未分類 that have text and no refinement pass yet.
    var pendingRefinementIDs: [String] { get }

    /// Records a refinement result. Ignored unless the screenshot is still automatic and in 未分類,
    /// so a manual move made meanwhile always wins.
    mutating func applyRefinement(_ id: String, verdict: ClassifierVerdict?)
}

// App: Services/FoundationModelsClassifier.swift
import FoundationModels

/// Asks the on-device model to pick a built-in category. Returns `nil` when this screenshot can't be
/// judged; throws when the model can't answer right now (unavailable, busy).
struct FoundationModelsClassifier: ScreenshotClassifier {
    enum Unavailable: Error { case model(SystemLanguageModel.Availability.UnavailableReason) }

    init(model: SystemLanguageModel = .default)
    func classify(_ input: ClassifierInput) async throws -> ClassifierVerdict?
}

extension ClassificationPipeline {
    static let appleIntelligence = ClassificationPipeline(layers: [Layer(FoundationModelsClassifier(), threshold: 0.6)])
}

// App: ScreenshotProcessor
init(photos:recognizer:pipeline:refinement: ClassificationPipeline?, library:mutate:)
private enum Work { case process(String), refine(String) }
private var isRefinementPaused = false   // set by a thrown error; cleared by start()
```

模型輸出的 schema（`DynamicGenerationSchema`）：

```
CategoryAnswer {
  category:  anyOf LLMCategoryPrompt.choices(excluding:)
  certainty: anyOf ["high", "medium", "low"]
}
```

## 規則檢核（pre-review）

| 規則 | 設計對策 | 殘留風險 |
|------|----------|----------|
| 1. 框架慣例 | 分工比照上層計畫：純邏輯放 `ScreenshotKit`，I/O 放 app 的 `Services/`。`FoundationModelsClassifier` 和 `VisionScreenRecognizer` 一樣是 app 裡的 service，用 `struct` 加上建構子注入。Migration 依 `LibraryMigrator` 的規定「不改已上線的 migration，只新增」 | 無 |
| 2. 架構可擴充性 | kNN（第 4 步）只要在 `.appleIntelligence` 前面多加一個 `Layer`，或是加進主佇列的 `.standard`，不用改 processor。改 prompt 只需要提高 `ClassificationPipeline.version`。門檻、文字上限、certainty 對應的分數都是具名常數 | 「kNN 多了樣本」時要重新補判，`isRefined` 不夠用，到時候再改成版本號。現在不做，避免沒人用的擴充點 |
| 3. 副作用 / Pure Function | prompt 文字、可選類別、回答轉換、補判名單、套用結果全部是 `ScreenshotKit` 裡的純函式或 `mutating` 值型別方法，可以在 macOS 用 `swift test` 測試。I/O（模型呼叫）只在 `FoundationModelsClassifier.classify` | 無 |
| 4. 重複程式碼 | 重用 `hint`、`defaultName`、`classifierInput(for:)`、`Library.update`。`classify` 和 `classifyOrThrow` 共用私有的 `accepts(_:threshold:input:)`，不會寫兩份門檻判斷 | 無 |
| 5. 命名 | 「補判」在程式碼中統一叫 refinement：`isRefined`、`pendingRefinementIDs`、`applyRefinement`、`refinement`（pipeline）、`isRefinementPaused`。bool 用 `is` 開頭。不用 `llmChecked` 這類綁定實作的名稱，因為補判之後也可能由別的層負責 | 無 |
| 6. 巢狀與複雜度 | 錯誤分類放在獨立的 `isPerInput(_ error:) -> Bool`，用一個 `switch` 處理。Processor 的排程拆成 `nextWork()`、`process(_:)`、`refine(_:)`，迴圈本身只有一層 | 無 |
| 7. SOLID | S：`FoundationModelsClassifier` 只和模型互動，prompt 由 `LLMCategoryPrompt` 負責。O：新增分類層只要新增 `ScreenshotClassifier` 實作。L：`FoundationModelsClassifier` 遵守協定的 `nil` 和 throw 語意，協定文件同步更新。I：協定維持只有一個方法。D：`SystemLanguageModel` 由 init 注入；processor 的 `refinement` 由 `LibraryStore` 注入，傳入 `nil` 就完全不補判（測試、預覽） | `SystemLanguageModel` 和 `LanguageModelSession` 沒辦法 mock，`FoundationModelsClassifier` 只能手動驗證（見風險） |

## 實作步驟

1. **開分支** — `git switch -c feature/llm-refinement`
2. **`AutoPlacement.isRefined` 與持久化** — 動到：`Placement.swift`、`Records.swift`、`LibraryMigrator.swift` 和相關測試；驗證：`swift test --package-path Packages/ScreenshotKit`、`swift test --package-path Packages/LibraryPersistence`（包含舊 JSON fixture 和 v2 資料庫的升級）
3. **補判名單與套用** — 動到：`Library+Classification.swift`、`RefinementTests.swift`；驗證：ScreenshotKit 測試
4. **`classifyOrThrow`** — 動到：`ClassificationPipeline.swift`、`ScreenshotClassifier.swift`、`ClassificationPipelineTests.swift`；驗證：ScreenshotKit 測試
5. **`LLMCategoryPrompt`** — 動到：新檔案和 `LLMCategoryPromptTests.swift`；驗證：ScreenshotKit 測試
6. **`FoundationModelsClassifier`** — 動到：app 的新檔案；驗證：`xcodebuild build`（iOS Simulator）
7. **Processor 補判佇列與注入** — 動到：`ScreenshotProcessor.swift`、`LibraryStore.swift`；驗證：`xcodebuild build`
8. **模擬器驗證** — Mac 開啟 Apple Intelligence 時，模擬器可以使用模型：
   - 用一張規則判斷不出來的截圖（例如只有短文字的地圖畫面），確認它被補判到正確資料夾，詳細頁顯示 Apple Intelligence
   - 補判途中手動搬移截圖，確認不會被搬回去
   - 首次匯入完成的時間點不受補判影響
   - Mac 關閉 Apple Intelligence 時不會出錯，未分類的截圖維持 `isRefined == false`
9. **更新上層計畫** — 第 3 步指向這份計畫；這份計畫加上「實作與計畫的差異」
10. **precommit-review** 之後 commit

## 測試計畫

- **`LLMCategoryPrompt`**
  - 刪除的內建分類不出現在 `choices` 和 `instructions` 裡；`noneKey` 永遠在 `choices` 裡
  - 超過 `maxTextLength` 的文字會被截斷
  - `verdict`：合法的類別和 certainty 會轉成 `.builtIn`、`.llm`，信心分數正確；`none`、未知的 key、未知的 certainty 回傳 `nil`
- **`Library` 的補判**
  - `pendingRefinementIDs` 只包含 `.auto`、`source == nil`、`folderID == nil`、有文字、`!isRefined` 的截圖；不包含處理中、使用者放置的、已補判的、沒有文字的截圖
  - `applyRefinement` 有答案時：放進對應資料夾，`source = .llm`，`isRefined = true`，`classifierVersion` 不變
  - `applyRefinement` 沒答案時：只把 `isRefined` 設為 `true`
  - 截圖已經被使用者搬移、或已經不在未分類時：不做任何事
  - 回答的內建分類已經被刪除時：當作沒答案
  - `requeueOutdated` 之後再分類，`isRefined` 會歸零
- **`ClassificationPipeline.classifyOrThrow`**：門檻和排除規則與 `classify` 相同；某一層丟錯時錯誤會傳出去
- **持久化**：`isRefined` 存取 round trip；沒有 `isRefined` 的舊 JSON 解碼成 `false`；v2 資料庫升級後所有截圖都是 `false`
- **手動測試**：見實作步驟 8

## 風險與未決問題

- ⚠️ **`FoundationModelsClassifier` 沒有自動化測試**：FoundationModels 沒辦法 mock，app 也沒有 test target。邏輯能搬的都搬進了 `LLMCategoryPrompt`，剩下的只有呼叫模型和錯誤分類，靠模擬器手動驗證。
- ⚠️ **3B 模型對中文 OCR 文字的分類品質未知**：certainty 和門檻都是推測值。和上層計畫一樣，需要真實截圖的評估集來調整。
- ⚠️ **語言不支援時會被標記為已補判**：如果整個語系都不支援，所有截圖都會被標記；之後系統更新加入支援時，不會自動重試。發生時可以提高 `ClassificationPipeline.version` 來補救。
- ⚠️ **補判會讓未分類的數字在使用中慢慢變少**：使用者剛好在看「未分類」資料夾時，截圖會從畫面上消失。目前和主佇列分類完成時的行為一樣，先不處理。
- ⚠️ **耗電**：幾千張截圖的補判會跑一段時間，但只在前景執行，而且只處理未分類的截圖。
- ❓ **`.general` 還是 `.contentTagging`**（D9）：要靠評估集比較。

## 實作與計畫的差異

| 項目 | 計畫 | 實作 | 原因 |
|------|------|------|------|
| Migration 順序 | 新增 `v3-shot-is-refined` | 註冊順序是 `v1-schema`、`v3-shot-is-refined`、`v2-import-legacy-json` | 舊 JSON 的匯入用目前的 `ShotRecord` 寫入，要在所有 schema migration 之後執行。GRDB 會執行所有還沒套用的 migration，所以已經套用 v1、v2 的資料庫也會補上 v3 |
| 補判名單的條件 | 寫在 `Library.pendingRefinementIDs` | 抽成 `Shot.awaitsRefinement` | 比照 `isProcessing`、`needsRecognition`，把判斷放在 `Shot` 上 |
| `onIdle` | 主佇列清空時通知 | 第一次轉到補判、或整輪結束時通知；主佇列又有工作進來時會重新計算 | 補判途中有新截圖時，主佇列清空後仍要通知 |
| 不可用時的紀錄 | 未列入計畫 | `ScreenshotProcessor` 用 `Logger`（category `classification`）在 info 等級記錄暫停原因 | 方便確認模型為什麼沒有補判 |

### 模擬器驗證結果（iPhone 16 Pro，iOS 26.5 SDK）

- 舊的 `library.json` 匯入 SQLite 時，migration 依序執行 `v1-schema`、`v3-shot-is-refined`、`v2-import-legacy-json`
- 原本 5 張截圖的放置結果不變
- 新增的「番茄炒蛋」截圖：規則層沒有答案，補判後放進「食譜」，`autoSource = llm`、`isRefined = 1`
- 新增的天氣截圖（台北市、多雲、降雨機率）：補判後放進「地點」。預期應該是 `none`，這是**分錯了**：模型把城市名稱當成地點。要靠評估集決定是調整 prompt、`place` 的 hint，還是只接受 `high`
- 沒有驗證：模型不可用時的路徑（需要在 Mac 上關閉 Apple Intelligence）、補判途中手動搬移（已有單元測試）

## 修訂紀錄

| 版本 | 日期 | 變更 |
|------|------|------|
| v1 | 2026-10-11 | 初版 |
| v2 | 2026-10-11 | 實作完成，記錄與計畫的差異和模擬器驗證結果 |
