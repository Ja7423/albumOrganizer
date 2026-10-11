# Feature Plan：自動分類評估工具

| 項目 | 內容 |
|------|------|
| 規劃日期 | 2026-10-11 |
| 規劃方式 | 直接規劃 |
| 目前分支 | `feature/classification-eval`（base `feature/llm-refinement`） |
| 狀態 | 已實作 |
| 上層計畫 | [截圖自動分類](screenshot-auto-classification-2026-10-07.md) 的風險項目「沒有真實截圖的評估集」 |

## 需求摘要

用使用者手動放入的截圖（`placement = 'user'`）當正確答案，量測規則層與 Apple Intelligence 補判在真實資料上的準確率。一個指令跑完兩層，印出每個分類的 precision / recall、混淆矩陣、整體錯放率與未分類率，之後調整門檻或 prompt 時可以重跑比較。

### 範圍

- **In scope**
  - 匯出腳本：從 `library.sqlite` 匯出 user placement 的截圖成 JSON 評估集（含 OCR 區塊座標與條碼數）
  - ScreenshotKit：評估集的資料型別、用 pipeline 跑評估、算指標（純函式）
  - macOS 命令列工具：讀評估集，依 App 的順序跑規則層，再對規則判斷不出來的樣本跑 Apple Intelligence，印出報告
  - 把 `FoundationModelsClassifier` 從 App 搬進套件，讓 App 和工具用同一份程式碼
  - `doc/classification.md` §7.1
- **Out of scope**
  - 自動調整門檻（只提供量測）
  - 自建資料夾的評估（目前沒有分類層會分進自建資料夾）
  - 把真實評估集放進 repo 或 CI

## 決策紀錄

| # | 決策 | 選擇 | 理由 / 被放棄的選項 |
|---|------|------|------|
| D1 | 工具怎麼用到 App 的模型設定 | 把 `FoundationModelsClassifier` 和 `ClassificationPipeline.appleIntelligence` 搬到 ScreenshotKit 套件的新 target `ScreenshotKitLLM`，App 改成 link 這個 product；CLI 也依賴它 | 規則 4：instructions、schema、取樣、門檻只有一份，不可能分歧。放棄：(a) 在 CLI 複製 schema 程式碼，會漂移；(b) 用 `swiftc` 編譯 App 的檔案，App 預設 MainActor 隔離，且每次要手動列檔案 |
| D2 | 為什麼不放進 `ScreenshotKit` target | 新 target | ScreenshotKit 是純邏輯、可在 macOS 14 測試；FoundationModels 需要 iOS 26 / macOS 26。分開後 ScreenshotKit 的依賴不變 |
| D3 | 指標計算放哪 | ScreenshotKit `Classification/Evaluation/`，純函式 | 規則 3：可以用 `swift test` 驗證計算；CLI 只負責 I/O 和排版 |
| D4 | 評估集格式 | 沿用 `labeled-ocr.json`：`expected`（分類 key 或 `null`）、`text`、`layout`、`barcodes`（數量），另加選填的 `id`、`blocks` | 有 `blocks` 時用真實座標算訊號（對話泡泡）；沒有時照 fixture 的方式合成。`RuleClassifierTests` 改用同一個型別，去掉重複的合成程式碼 |
| D5 | 匯出哪些截圖 | `placement = 'user'`、有文字；資料夾是內建分類，或沒有資料夾（正確答案 = 未分類） | 任務指定。沒有文字的截圖兩層都不會處理，放進來只會灌高未分類率 |
| D6 | 匯出檔放哪 | 預設 `eval/labeled-shots.json`，`/eval/` 加進 `.gitignore` | 含個人資訊，不 commit |
| D7 | 腳本位置與語言 | `scripts/export-labeled-shots.sh`，用 `sqlite3` 的 JSON 函式 | 預設值。repo 沒有既有的 scripts 目錄；macOS 內建 `sqlite3`，不需要額外相依 |
| D8 | 錯放率定義 | 被放進資料夾、但不是正確分類的樣本 / 全部樣本（包含正確答案是未分類卻被放進資料夾） | 對應「錯放比不放更糟」；另外印「放進資料夾的樣本中放對的比例」 |
| D9 | 模型不可用時 | CLI 開始前檢查可用性，不可用就印出原因、只輸出規則層結果並以非 0 結束；評估途中丟錯就中止 | 用 `classifyOrThrow`，避免把「模型不能用」算成「沒答案」 |
| D10 | 被刪除的內建分類 | 評估時不排除任何分類 | 預設值。被刪除的分類沒有資料夾，不會出現在正確答案裡；影響很小，寫進文件 |

## 現況分析

- **最相似的既有功能**：`RuleClassifierTests.testLabeledSamples`（[RuleClassifierTests.swift](../../Packages/ScreenshotKit/Tests/ScreenshotKitTests/RuleClassifierTests.swift)）已經在跑合成評估集，但只 assert，不算指標。其中「文字 → blocks」的合成搬進 `LabeledSample`。
- **可重用**
  - `ClassificationPipeline.standard`、`classifyOrThrow`（[ClassificationPipeline.swift](../../Packages/ScreenshotKit/Sources/ScreenshotKit/Classification/ClassificationPipeline.swift)）
  - `SignalExtractor.extract(blocks:barcodes:)`、`TextBlock`（Codable，和資料庫的 `recognition.blocks` 格式相同）
  - `LLMCategoryPrompt`
- **會被影響的既有程式碼**
  - `albumOrganizer/ScreenshotOrganizer/Services/FoundationModelsClassifier.swift`：搬走
  - `albumOrganizer/ScreenshotOrganizer/Store/LibraryStore.swift`：`import ScreenshotKitLLM`
  - `albumOrganizer.xcodeproj/project.pbxproj`：App link `ScreenshotKitLLM` product
  - `Packages/ScreenshotKit/Package.swift`：新增 target 與 product

## 架構設計

```
scripts/export-labeled-shots.sh ── sqlite3 ──▶ eval/labeled-shots.json（gitignored）
                                                        │
classification-eval（executable，macOS 26）◀────────────┘
  ├─ ScreenshotKit
  │    └─ Classification/Evaluation
  │         ├─ LabeledSample          評估集的一筆；→ ClassifierInput
  │         ├─ ClassificationEvaluation.outcomes(of:using:)   跑 pipeline，回傳 [EvaluationOutcome]
  │         └─ EvaluationReport       從 outcomes 算 precision / recall / 混淆矩陣 / 比例（純）
  └─ ScreenshotKitLLM
       ├─ FoundationModelsClassifier（從 App 搬來）
       └─ ClassificationPipeline.appleIntelligence（門檻 0.6）
App ── ScreenshotKit + ScreenshotKitLLM
```

- `classification-eval` 只做：讀檔、解碼、依序呼叫兩層、排版輸出。
- 指標的定義全部在 `EvaluationReport`，CLI 不自己算。

## 檔案變更清單

| 動作 | 檔案 | 職責 |
|------|------|------|
| 新增 | `scripts/export-labeled-shots.sh` | 匯出評估集 |
| 修改 | `.gitignore` | 忽略 `/eval/` |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Classification/Evaluation/LabeledSample.swift` | 評估集型別、轉成 `ClassifierInput` |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Classification/Evaluation/ClassificationEvaluation.swift` | `EvaluationOutcome`、跑 pipeline、兩層合併 |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Classification/Evaluation/EvaluationReport.swift` | 指標 |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKitLLM/FoundationModelsClassifier.swift` | 從 App 搬來，加上 `public` 與 availability |
| 新增 | `Packages/ScreenshotKit/Sources/ClassificationEval/main.swift`、`ReportPrinter.swift` | CLI |
| 修改 | `Packages/ScreenshotKit/Package.swift` | 新 target / product |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/ClassificationEvaluationTests.swift` | 指標與 outcomes 測試 |
| 修改 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/RuleClassifierTests.swift` | 改用 `LabeledSample` |
| 刪除 | `albumOrganizer/ScreenshotOrganizer/Services/FoundationModelsClassifier.swift` | 搬走 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Store/LibraryStore.swift`、`albumOrganizer.xcodeproj/project.pbxproj` | 改用套件裡的分類器 |
| 修改 | `doc/classification.md` | §1.1 元件位置、§7.1 評估流程、§8 限制 |

## 介面草案

```swift
public struct LabeledSample: Codable, Hashable, Sendable {
    public var id: String?
    /// `nil` means the right answer is 未分類.
    public var expected: BuiltInCategory?
    public var text: String
    public var layout: String?      // "chat" for synthetic samples without blocks
    public var barcodes: Int?
    public var blocks: [TextBlock]?
    public var classifierInput: ClassifierInput { get }
}

public struct EvaluationOutcome: Hashable, Sendable {
    public var expected: BuiltInCategory?
    public var predicted: BuiltInCategory?
}

public enum ClassificationEvaluation {
    /// One outcome per sample, in order. Throws when a layer cannot answer right now.
    public static func outcomes(of samples: [LabeledSample], using pipeline: ClassificationPipeline) async throws -> [EvaluationOutcome]
    /// The second pass only answers what the first left in 未分類, as in the app.
    public static func unsortedIndices(_ outcomes: [EvaluationOutcome]) -> [Int]
    public static func cascade(_ first: [EvaluationOutcome], then second: [EvaluationOutcome]) -> [EvaluationOutcome]
}

public struct EvaluationReport: Sendable {
    public struct CategoryMetrics { support, placed, correct, precision: Double?, recall: Double? }
    public init(_ outcomes: [EvaluationOutcome])
    public var total: Int
    public var categories: [BuiltInCategory: CategoryMetrics]
    public var confusion: [EvaluationOutcome: Int]
    public var misplacementRate: Double?  // 放錯 / total；空集合為 nil
    public var unsortedRate: Double?      // 沒放 / total
    public var placedPrecision: Double?   // 放對 / 放進資料夾
    public var noneAccuracy: Double?      // 正確答案是未分類、也留在未分類的比例
}

@available(iOS 26.0, macOS 26.0, *)
public struct FoundationModelsClassifier: ScreenshotClassifier { … }  // 內容不變
```

## 規則檢核（pre-review）

| 規則 | 設計對策 | 殘留風險 |
|------|----------|----------|
| 1. 框架慣例 | 分類相關型別放 `Classification/`；FoundationModels 程式碼原樣搬移；測試沿用 XCTest 與 `Bundle.module` fixture | 無 |
| 2. 架構可擴充性 | 新增分類層（kNN）時，CLI 只需多一次 `outcomes` + `cascade`；新增內建分類時指標自動涵蓋（以 `BuiltInCategory.allCases` 迭代）。門檻沿用 pipeline 的常數，不在工具裡寫死 | 無 |
| 3. 副作用 / Pure Function | `EvaluationReport.init`、`cascade`、`LabeledSample.classifierInput` 都是純函式；檔案讀取、模型呼叫、輸出只在 CLI | 無 |
| 4. 重複程式碼 | 分類器只有一份（D1）；`RuleClassifierTests` 的 blocks 合成移到 `LabeledSample` | 無 |
| 5. 命名 | `LabeledSample`、`EvaluationOutcome`、`EvaluationReport`、`misplacementRate`、`unsortedRate`；CLI 叫 `classification-eval` | 無 |
| 6. 巢狀與複雜度 | 報告排版拆成每一節一個函式（分類表、比例、混淆矩陣） | 無 |
| 7. SOLID | CLI 依賴 `ClassificationPipeline`（不直接依賴具體分類器）；`EvaluationReport` 只算指標不排版 | 無 |

## 實作步驟

1. **評估型別與指標** — `Evaluation/` 三個檔案、`ClassificationEvaluationTests`、`RuleClassifierTests` 改用 `LabeledSample`；驗證 `swift test`。
2. **搬移分類器** — `ScreenshotKitLLM` target、刪 App 檔、pbxproj；驗證 `swift build`、`xcodebuild … -sdk iphonesimulator build`。
3. **CLI** — `ClassificationEval`；驗證用 fixture 跑 `swift run classification-eval Tests/…/labeled-ocr.json`。
4. **匯出腳本與 .gitignore** — 驗證：在模擬器資料庫上執行（若有資料），或用暫存的資料庫測 SQL。
5. **文件** — `doc/classification.md`。

## 測試計畫

- `EvaluationReport`：precision / recall / 混淆矩陣的計算；沒有預測時 precision 為 `nil`；正確答案是未分類卻被放入算錯放；空集合。
- `cascade`：第一層有答案時保留，沒有時採用第二層。
- `outcomes`：用 fixture 跑 `.standard`，和 `testLabeledSamples` 的期望一致。
- `LabeledSample`：有 `blocks` 時用真實座標；沒有時合成。
- `FoundationModelsClassifier`：沒有自動化測試（同既有限制），用 CLI 手動跑。

## 風險與未決問題

- ⚠️ 評估集裡的正確答案只來自使用者手動搬移的截圖，可能偏向「自動分類分錯、被搬走」的樣本，指標會比整體真實準確率低。文件中說明。
- ⚠️ CLI 需要 macOS 26 並開啟 Apple Intelligence；Mac 上的模型版本可能和 iPhone 不同。

## 修訂紀錄

| 版本 | 日期 | 變更 |
|------|------|------|
| v1 | 2026-10-11 | 初版 |
