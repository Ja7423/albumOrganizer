# Feature Plan：首次匯入 UX、App 內處理進度與 OCR／分類加速

| 項目 | 內容 |
|------|------|
| 規劃日期 | 2026-10-14 |
| 規劃方式 | grilling（3 輪，Q1–Q18） |
| 目前分支 | `main`（`a7233c4`）；實作時另開 `feature/processing-progress` |
| 狀態 | 已實作（`feature/processing-progress`），待實機量測 |

## 需求摘要

使用者一次匯入 5000 張以上截圖時，要能馬上進入相簿，辨識和分類在 App 內繼續進行，並且隨時看得到進度。同時把處理速度提升到 5000 張可以在合理時間內跑完。

成功的樣子：
- 匯入畫面只有一顆主按鈕，而且一直可以按。不會再有「看不出來可以點」的 ghost 按鈕。
- 進入相簿後，tab bar 上方常駐一條進度列，顯示「正在整理截圖 X / Y」。處理完時顯示摘要，約 3 秒後消失。
- iPhone 15 等級的裝置，App 在前景時，5000 張在 10 分鐘內處理完（OCR＋規則分類，不含 refinement）。
- 分類結果和現在一致，不犧牲 OCR 品質。

### 範圍

- **In scope**
  - 匯入畫面按鈕調整，停在匯入畫面時關閉自動鎖定
  - App 內進度列：顯示條件、內容、點擊跳轉、完成摘要
  - 匯入畫面和 App 共用同一個 `ProcessingProgress` 模型
  - `os_signpost` 量測，加上每輪的總結 log
  - 處理器改為多個 worker 平行處理，平行數量依熱度和低耗電模式調整
  - 每 0.5 秒或每 20 張合併一次寫入 `Library`
  - 每輪只建一次工作佇列，消除每張都從頭掃描的 O(n²)
- **Out of scope**
  - 離開 App 後繼續處理（`BGContinuedProcessingTask`、`BGProcessingTask`），列為下一階段
  - 預估剩餘時間
  - 會降低品質的 OCR 手段（`.fast`、關閉語言校正、縮圖、條碼偵測條件化），要先用 ClassificationEval 驗證才考慮
  - 同一輪內重試失敗的截圖
  - refinement（Apple Intelligence）的平行化與進度顯示

## 決策紀錄

| # | 決策 | 選擇 | 理由 / 被放棄的選項 |
|---|------|------|------|
| D1 | 匯入畫面按鈕 | 只有一顆主按鈕，一直可以按。辨識中顯示「進入相簿（背景繼續辨識）」，完成後顯示「進入相簿」；拿掉 `total > 20` 門檻 | 現在的 ghost 樣式看不出來可以點，主按鈕又是 disabled。被放棄：兩顆按鈕並存、自動進入（Q1） |
| D2 | 進度列位置 | tab bar 上方常駐一條，所有 tab 都看得到 | Q2。**實作調整**：App 用的是自訂的 `TabBar`（[AppShell.swift](../../albumOrganizer/ScreenshotOrganizer/Views/Shell/AppShell.swift)），不是 `TabView`，所以沒有 `tabViewBottomAccessory` 可以用。改成在 `AppShell` 的 `VStack` 裡、`TabBar` 正上方放一個 `ProcessingBar`，視覺位置相同 |
| D3 | 顯示條件 | 本輪總數 ≥ 20 張時顯示。首次匯入、大量新截圖、分類器升版都適用；一旦出現就維持到本輪結束，不會因為剩餘數低於 20 而消失 | 1～2 張新截圖時不打擾使用者，也避免進度列中途閃掉（Q3，「維持到本輪結束」是預設值） |
| D4 | 進度涵蓋範圍 | 只算 OCR 和分類，不算 refinement | refinement 很慢，失敗時也會暫停，算進去會讓進度停在 99%（Q4） |
| D5 | 速度目標 | ~~iPhone 15 等級，App 在前景時，5000 張 ≤ 10 分鐘~~ → **改為：5000 張約 33 分鐘，搭配離開 App 後繼續處理（下一階段）** | 原目標見 Q5。2026-10-15 實機量測發現 Vision `.accurate` 繁中 OCR 每張約 0.4 秒且會排隊執行，調整參數最多只快 9% 還會降低品質，10 分鐘做不到；使用者同意改目標 |
| D6 | 加速手段 | 只做不影響品質的：平行處理、讀圖和 OCR 重疊、合併寫入、消除 O(n²) | 會降低品質的手段要先用 ClassificationEval 驗證（Q6） |
| D7 | 離開 App 後 | 不處理，列為下一階段 | Q7 |
| D8 | 進度列內容 | 細進度條加上「正在整理截圖 X / Y」；點擊後切到「資料夾」tab，打開「處理中」 | 預估時間前幾十張不準（Q8） |
| D9 | 完成後 | 顯示「整理完成：已分類 X 張，未分類 Y 張」，有失敗時加「N 張稍後重試」；約 3 秒後消失 | Q9、Q11 |
| D10 | 分母 | 本輪已處理數＋還沒處理的數量。新截圖進來時變大，隱藏時變小，本輪結束後歸零 | 數字跟「處理中」實際張數一致（Q10） |
| D11 | 失敗的截圖 | 算作本輪已處理，但不從「處理中」移走。分母裡的「還沒處理」＝~~處理中張數~~ **`Library.processingWorkCount`（需要辨識或分類的張數，v4 修正）**－本輪失敗張數 | 重試要等下一輪，不算的話進度會卡住（Q11） |
| D12 | 完成判定 | 本輪已經沒有可以做的 OCR 或分類工作就算完成，等重試的截圖不擋完成 | 跟現在 `onIdle` 的觸發時機相同（Q17） |
| D13 | 重試機制 | 維持現況：下一輪再試，最多 3 次（`Shot.maxRecognitionAttempts`） | Q18 |
| D14 | 進度模型 | 匯入畫面和 App 共用 `LibraryStore.processingProgress`，取代 `ImportProgress`。匯入畫面自己多顯示「掃描」那一步 | 只有一個資料來源，切換畫面時數字能接上（Q12） |
| D15 | 平行數量 | 平常 ~~3~~ **2** 個 worker（2026-10-15 依實機量測調整）。`thermalState ≥ .serious` 或低耗電模式時降到 1 個，每次取下一張之前重新判斷 | 避免發熱降頻後反而更慢（Q13） |
| D16 | 自動鎖定 | 只在匯入畫面（`ImportStep`）出現時關閉，離開就恢復 | Q14 |
| D17 | 寫入頻率 | 處理結果先暫存，每 0.5 秒或累積 20 張時合併成一次 `mutate` | 看起來仍然即時，重繪和存檔的 diff 次數大幅減少（Q15） |
| D18 | 量測 | `OSSignposter`（subsystem 沿用 bundle id，category `processing`）標出 `loadImage`、`recognize`、`classify`、`apply` 四段；每輪結束 log 一行「張數／耗時／每分鐘張數／失敗數」 | 成本最低，正式版裡也可以保留（Q16） |
| D19 | 讀圖和 OCR 重疊 | 不另外寫 prefetch。每個 worker 依序做「讀圖 → OCR → 分類」，多個 worker 同時跑，自然就有一個在讀圖、另一個在 OCR | 達到 Q6「預先讀下一張圖」的目的，不用多一套 prefetch 狀態。**預設值（可推翻）** |
| D20 | 分類在哪裡跑 | 在 worker 裡，OCR 完立刻用這次的 OCR 結果組 `ClassifierInput` 分類；結果和 OCR 一起放進同一筆 `ProcessingOutcome` | 不必等寫回 `Library` 再讀出來分類，一張只要一次寫入。**預設值** |
| D21 | 工作佇列 | 每輪開始時掃一次 `Library` 建出 `ProcessingQueue`。之後 `start()` 再被呼叫時（Photos 變動等），只把新出現的 id 補進去 | 取代每張都跑一次 `pendingRecognitionIDs`、`shot(id)` 的 O(n) 掃描。**預設值** |
| D22 | 手動搬移的競態 | worker 拿到結果時，使用者可能已經手動搬移或隱藏這張截圖。合併寫入時沿用 `applyClassification` 的規則：已經不是 processing 就忽略分類結果，id 不在了就整筆略過 | 沿用現有「手動搬移優先」的語意。**預設值** |
| D23 | Apple Intelligence 再分類的進度（v5） | 一輪分兩個階段：①辨識並分類「處理中」②Apple Intelligence 再看一次留在「未分類」的截圖。進度列依階段顯示各自的 x / y（標題「正在整理截圖」→「正在分類截圖」），完成摘要等第②階段結束才出現，並把被移進資料夾的截圖從「未分類」改算「已分類」（只扣本輪放進未分類的；前幾輪留下的只加到已分類）。第②階段時點進度列開「未分類」。匯入畫面與系統背景任務都在第①階段結束時完成，因為 Apple Intelligence 在背景會被系統限流 | 第②階段一次只跑一張，5000 張時可能有上千張要跑，原本卻沒有任何進度顯示 |

## 現況分析

- **最相似的既有功能**
  - [ScreenshotProcessor.swift](../../albumOrganizer/ScreenshotOrganizer/Services/ScreenshotProcessor.swift)：這次主要改的就是它。它的職責邊界保持不變：不持有 library 狀態，只透過 `library`、`mutate` 兩個 closure 讀寫。優先處理（`prioritize`）、本輪不重試（`attemptedThisRun`）、佇列清空後才做 refinement 這三個行為都保留。
  - [LibraryStore.swift](../../albumOrganizer/ScreenshotOrganizer/Store/LibraryStore.swift)：`ImportProgress` 和 `finishImportSteps()` 是這次要取代的進度邏輯。
  - [OnboardingView.swift:189](../../albumOrganizer/ScreenshotOrganizer/Views/Onboarding/OnboardingView.swift:189) 的 `ImportStep`：進度條和 `StepRow` 的視覺樣式沿用。
- **可重用**
  - `Library.setRecognition`、`applyClassification`（[Library.swift:158](../../Packages/ScreenshotKit/Sources/ScreenshotKit/Library.swift:158)、[Library+Classification.swift](../../Packages/ScreenshotKit/Sources/ScreenshotKit/Library+Classification.swift)）：裡面對單一 `Shot` 的修改抽成 `Shot` 的 mutating 方法，單筆 API 和新的批次 API 都呼叫它們。
  - `Library.classificationSummary`：完成摘要直接用它。
  - `SignalExtractor.extract`、`FeatureDetector.detect`、`ClassificationPipeline.classify`：worker 分類時照原樣呼叫。
  - `ScreenRecognizing` / `VisionScreenRecognizer`：已經是 `Sendable`，而且在 `Task.detached` 裡執行，可以直接被多個 worker 同時呼叫，不用修改。
  - `PhotoLibraryService.imageData(for:)`：已經是 `nonisolated`，可以被多個 worker 同時呼叫。
  - `UIState.Route.processing`、`folderPath`：點擊進度列後的跳轉直接用。
  - `ContinueButton`、`Palette`、`Typeface`、`Hairline`：UI 元件沿用。
- **需新增的資料來源**：無。
- **效能瓶頸（量測前的推測，步驟 1 要驗證）**
  1. 一次只處理一張，讀圖、OCR、分類完全串行。
  2. 每張處理都會呼叫 `nextID()` → `pendingRecognitionIDs`（O(n) filter）、`canRecognize` → `shot(id)`（O(n)）、`update([id])`（O(n)）。5000 張時整體是 O(n²)，大約 2,500 萬次 `Shot` 存取。
  3. 每張兩次 `mutate`（辨識、分類各一次），每次都觸發 `@Observable` 讓讀 `library` 的 view 重繪；每 400ms debounce 一次的 `changes(since:)` 也要比對 5000 個 `Shot`。
  4. `onRecognized` 每張都改一次 `importProgress`，也會觸發重繪。
- **會被影響的既有程式碼**
  - [ScreenshotProcessor.swift](../../albumOrganizer/ScreenshotOrganizer/Services/ScreenshotProcessor.swift)：重寫執行迴圈。
  - [LibraryStore.swift](../../albumOrganizer/ScreenshotOrganizer/Store/LibraryStore.swift)：移除 `ImportProgress`，新增 `processingProgress`、`importFoundCount`。
  - [OnboardingView.swift](../../albumOrganizer/ScreenshotOrganizer/Views/Onboarding/OnboardingView.swift)：`ImportStep` 改用新的進度模型並調整按鈕。
  - [AppShell.swift](../../albumOrganizer/ScreenshotOrganizer/Views/Shell/AppShell.swift)：在 `TabBar` 上方放 `ProcessingBar`。
  - [UIState.swift](../../albumOrganizer/ScreenshotOrganizer/Store/UIState.swift)：新增 `showProcessing()`。
  - [ShotGridScreen.swift:109](../../albumOrganizer/ScreenshotOrganizer/Views/Library/ShotGridScreen.swift:109)：不受影響（仍然用 `processingCount`）。

## 架構設計

```
ScreenshotKit（純值型別，用 swift test 測）
  ├─ ProcessingProgress        進度狀態與轉換：開始、記錄批次、更新剩餘、完成、清除
  ├─ ProcessingQueue           本輪工作佇列：優先處理、補進新 id、本輪已嘗試過的 id
  ├─ ProcessingOutcome         一張截圖的處理結果（OCR 結果或失敗＋分類結果）
  ├─ OutcomeBuffer             決定何時合併寫入（張數或時間到了），時間由呼叫端傳入
  ├─ ProcessingConcurrency     由 thermalState 和低耗電模式算出 worker 數量
  └─ Library.applyProcessingOutcomes(_:version:)   一次掃描就套用整批結果

App（@MainActor）
  LibraryStore ── processingProgress ──▶ ImportStep / ProcessingBar
      │  onBatchApplied / onRunFinished
      ▼
  ScreenshotProcessor（排程：佇列、worker pool、合併寫入、refinement）
      │  每個 worker：imageData → recognize → classify → ProcessingOutcome
      ├─ PhotoLibraryService.imageData（nonisolated）
      ├─ ScreenRecognizing（Task.detached）
      ├─ ClassificationPipeline
      └─ ProcessingSignposts（OSSignposter 量測與每輪總結 log）
```

分層說明：
- **ScreenshotKit**：所有「怎麼算」的規則都放這裡，包括進度數字、佇列順序、何時合併寫入、平行數量、批次套用時的競態判斷。這些都不碰 Photos、Vision 或時鐘，全部用 `swift test` 測。
- **ScreenshotProcessor**：只負責排程和 I/O。它用 `withTaskGroup` 維持 N 個 worker，把每張的結果交給 `OutcomeBuffer`，該合併寫入時呼叫一次 `mutate`，再透過 callback 通知 store。它不知道進度怎麼顯示。
- **LibraryStore**：持有 `processingProgress`，在 processor 的 callback 裡呼叫 `ProcessingProgress` 的轉換方法。完成摘要的 3 秒自動消失也由 store 負責。
- **Views**：`ImportStep` 和 `ProcessingBar` 只讀 `store.processingProgress` 來呈現。自動鎖定的開關是 view 的生命週期副作用，用一個 view modifier 處理。

### worker 怎麼跑

```
run():
  queue = ProcessingQueue(library)            // 一次 O(n)
  withTaskGroup:
    同時維持 width 個 child task；每有一個完成就：
      buffer.append(outcome, now)
      if buffer.shouldFlush(now) → flush()
      width = ProcessingConcurrency.width(...)   // 每次補新工作前重新判斷
      if let next = queue.next() → addTask(work(next))
  flush()
  onRunFinished(...)
  while 有 refinement 工作 → refine（維持現在的串行做法）
```

- 補新工作時只要正在跑的 worker 數量 ≥ width 就不補，所以降溫或升溫時 worker 數會自然收斂。
- `prioritize(id)`：插到佇列最前面。正在跑的 run 下一次取工作時就會拿到它，不用重新開始。
- `start()` 在 run 進行中又被呼叫（Photos 變動）：設一個 `needsRefill` 旗標，下一次取工作前讓佇列用目前的 `Library` 補進新的 id。

### 替代方案

| 方案 | 優點 | 缺點 | 結論 |
|------|------|------|------|
| A. 在 `Library` 裡加 `[String: Int]` 索引，讓 `shot(id)` 變 O(1) | 所有呼叫 `shot(id)` 的地方都變快 | `Library` 是 `Codable`、`Hashable` 的值型別，索引要從 `==`、`hash`、Codable 裡排除，每個修改 `shots` 的 mutating 方法也都要維護索引，範圍大、容易出錯 | 不採用。改用 `ProcessingQueue` 加上批次套用（一次掃描、用 `Set` 查詢），把 O(n²) 侷限在處理器裡解決 |
| B. 把 OCR 搬到 actor 或 `OperationQueue`，`Library` 改成 actor 持有 | 寫入完全離開 main actor | 跟現有「`Library` 是 store 持有的值、view 直接讀」的架構衝突，要改所有 view | 不採用。合併寫入後 main actor 每 0.5 秒才做一次 O(n) 套用，負擔可以接受 |

## 檔案變更清單

| 動作 | 檔案 | 層 | 職責 |
|------|------|----|------|
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Processing/ProcessingProgress.swift` | 純邏輯 | 進度狀態與轉換、顯示條件、摘要 |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Processing/ProcessingQueue.swift` | 純邏輯 | 本輪工作佇列 |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Processing/ProcessingOutcome.swift` | 純邏輯 | 處理結果型別＋`Library.applyProcessingOutcomes` |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Processing/OutcomeBuffer.swift` | 純邏輯 | 合併寫入的時機 |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Processing/ProcessingConcurrency.swift` | 純邏輯 | 計算 worker 數量 |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Models.swift` | 純邏輯 | 新增 `Shot.recordRecognition(_:)`、`Shot.applyAutoPlacement(...)`（由 `Library` 現有方法抽出來） |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Library.swift` | 純邏輯 | `setRecognition` 改呼叫 `Shot.recordRecognition` |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Library+Classification.swift` | 純邏輯 | `applyClassification` 改呼叫 `Shot.applyAutoPlacement`；新增 `classifierInput(blocks:barcodes:)`，讓 worker 不用先寫回再讀 |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/ProcessingProgressTests.swift` | 測試 | |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/ProcessingQueueTests.swift` | 測試 | |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/ProcessingOutcomeTests.swift` | 測試 | 批次套用、競態、跟單筆 API 結果一致 |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/OutcomeBufferTests.swift` | 測試 | |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/ProcessingConcurrencyTests.swift` | 測試 | |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Services/ProcessingSignposts.swift` | Service | `OSSignposter` 包裝、每輪總結 log |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Services/ScreenshotProcessor.swift` | Service | worker pool、佇列、合併寫入；callback 改成 `onBatchApplied`、`onRunFinished` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Store/LibraryStore.swift` | Store | 移除 `ImportProgress`、`finishImportSteps`；新增 `processingProgress`、`importFoundCount`、自動消失計時 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Store/UIState.swift` | Store | 新增 `showProcessing()` |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Views/Shell/ProcessingBar.swift` | View | tab bar 上方的進度列 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Shell/AppShell.swift` | View | 在 `TabBar` 上方放 `ProcessingBar`（選取模式下不顯示） |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Onboarding/OnboardingView.swift` | View | `ImportStep` 改用新的進度模型、單一按鈕、`.keepsScreenAwake()` |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Views/Common/KeepsScreenAwake.swift` | View | 出現時關閉自動鎖定、消失時恢復的 view modifier |
| 修改 | `doc/classification.md` | 文件 | 補充處理流程（worker、合併寫入、量測方式） |

## 介面草案

```swift
// ScreenshotKit/Processing/ProcessingProgress.swift

/// What the progress bar and the import screen show for one processing run. Pure: the store feeds it events.
public struct ProcessingProgress: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case running
        case finished(ProcessingSummary)
    }

    public static let visibilityThreshold = 20

    public private(set) var phase: Phase = .idle
    /// Recognized-and-classified plus failed ones, this run.
    public private(set) var processed = 0
    /// Failed recognitions this run; still in 處理中, retried next run.
    public private(set) var failed = 0
    /// Not yet looked at this run.
    public private(set) var remaining = 0
    /// Set once the run reaches the threshold; stays until the run ends so the bar never flickers away.
    public private(set) var isVisible = false

    public init() {}

    public var total: Int { processed + remaining }
    public var fraction: Double { total == 0 ? 0 : Double(processed) / Double(total) }

    /// `processingCount` is the library's 處理中 count; failed ones in it are not remaining.
    public mutating func begin(processingCount: Int)
    public mutating func record(processed: Int, failed: Int, processingCount: Int)
    /// Photos added or the user hid screenshots mid-run.
    public mutating func updateRemaining(processingCount: Int)
    public mutating func finish(summary: ClassificationSummary)
    public mutating func clear()
}

public struct ProcessingSummary: Equatable, Sendable {
    public var classified: Int
    public var unsorted: Int
    public var retryLater: Int
}
```

```swift
// ScreenshotKit/Processing/ProcessingQueue.swift

/// The run's work list, built from the library once instead of scanning it for every screenshot.
public struct ProcessingQueue: Sendable {
    public enum Work: Equatable, Sendable {
        /// Needs OCR, then classification.
        case recognizeAndClassify(String)
        /// OCR done or out of retries; only classification is left.
        case classify(String)
    }

    public init(library: Library)
    /// Adds screenshots that became pending since the queue was built; skips ones already queued or attempted.
    public mutating func refill(from library: Library)
    public mutating func prioritize(_ id: String)
    /// Next work item, marking it attempted for this run.
    public mutating func next() -> Work?
    public var isEmpty: Bool { get }
}
```

```swift
// ScreenshotKit/Processing/ProcessingOutcome.swift

public struct ProcessingOutcome: Equatable, Sendable {
    public enum Recognition: Equatable, Sendable {
        case recognized(blocks: [TextBlock], barcodes: [String])
        case failed
        /// `classify`-only work: recognition was already settled.
        case unchanged
    }

    public var id: String
    public var recognition: Recognition
    /// `nil` when recognition failed and will be retried, so the screenshot stays in 處理中.
    public var classification: Classification?

    public struct Classification: Equatable, Sendable {
        public var verdict: ClassifierVerdict?
        public var features: Set<FeatureTag>
    }

    public var didFail: Bool { recognition == .failed }
}

public extension Library {
    /// Applies a batch in one pass over `shots`. Ids no longer in the library are skipped; a classification is
    /// ignored for screenshots the user placed meanwhile, as in `applyClassification`.
    mutating func applyProcessingOutcomes(_ outcomes: [ProcessingOutcome], version: Int)

    /// Classifier input built from fresh OCR output, before it is written back.
    func classifierInput(blocks: [TextBlock], barcodes: [String]) -> ClassifierInput
}

// Models.swift — extracted so the single and batch paths share one rule each.
extension Shot {
    mutating func recordRecognition(blocks: [TextBlock]?, barcodes: [String])
    /// No-op unless still processing.
    mutating func applyAutoPlacement(folderID: UUID?, source: ClassifierSource?, features: Set<FeatureTag>, version: Int)
}
```

失敗但還沒用完重試次數時，`classification` 是 `nil`。失敗且這次已經是第 3 次時，worker 會接著用空文字分類（行為跟現在相同：用完重試次數的截圖會進 `pendingClassificationIDs`）。

```swift
// ScreenshotKit/Processing/OutcomeBuffer.swift

/// Collects outcomes and says when to write them: every `maxCount` outcomes or `maxDelay` after the first.
public struct OutcomeBuffer: Sendable {
    public init(maxCount: Int = 20, maxDelay: Duration = .milliseconds(500))
    /// `now` is passed in so tests need no clock.
    public mutating func append(_ outcome: ProcessingOutcome, at now: ContinuousClock.Instant)
    public func shouldFlush(at now: ContinuousClock.Instant) -> Bool
    public mutating func drain() -> [ProcessingOutcome]
}
```

```swift
// ScreenshotKit/Processing/ProcessingConcurrency.swift

public enum ProcessingConcurrency {
    public static let normalWidth = 2
    public static func width(thermalState: ProcessInfo.ThermalState, isLowPowerModeEnabled: Bool) -> Int
}
```

```swift
// App: ScreenshotProcessor（只列有變動的公開介面）

@MainActor
final class ScreenshotProcessor {
    struct BatchResult { var processed: Int; var failed: Int }

    /// After each merged write.
    var onBatchApplied: (BatchResult) -> Void = { _ in }
    /// When the run has no OCR or classification work left, before refinement.
    var onRunFinished: () -> Void = {}

    /// Injected so tests and previews can pin the width.
    init(..., concurrency: @escaping () -> Int = ScreenshotProcessor.deviceConcurrency)

    func start()
    func prioritize(_ id: String)
}

// App: LibraryStore
private(set) var processingProgress = ProcessingProgress()
/// 「掃描」step on the import screen.
private(set) var importFoundCount = 0

// App: UIState
func showProcessing()   // tab = .folders, folderPath = [.processing]

// App: Views/Common/KeepsScreenAwake.swift
extension View { func keepsScreenAwake() -> some View }
```

## 規則檢核（pre-review）

| 規則 | 設計對策 | 殘留風險 |
|------|----------|----------|
| 1. 框架慣例 | 純邏輯放在 ScreenshotKit 的值型別，用 `swift test` 測（比照 Backup、Classification 目錄）；App 層 service 維持 `@MainActor`，重的工作放 `Task.detached`（比照現在的 `VisionScreenRecognizer`）；store 是 `@Observable`，view 透過 `@Environment` 讀；UI 用 `Palette`、`Typeface`、`ContinueButton`；log 用 `Logger`，subsystem 沿用 bundle id | 專案沒有 l10n 機制，字串照現有畫面直接寫中文。`tabViewBottomAccessory` 因為用自訂 `TabBar` 而無法使用（D2） |
| 2. 架構可擴充性 | 下一階段的 `BGContinuedProcessingTask` 只要在新的 entry point 呼叫同一個 `ScreenshotProcessor.start()`，再把 `onBatchApplied` 的數字轉成系統進度即可，`ProcessingProgress` 不用改；之後若要加入會影響品質的 OCR 參數，只動 `VisionScreenRecognizer`；worker 數量規則集中在 `ProcessingConcurrency`。沒有為單一實作新增 protocol | 無 |
| 3. 副作用 / Pure Function | 進度、佇列、合併時機、平行數量、批次套用都是純函式或值型別的 mutating 方法；`OutcomeBuffer` 由呼叫端傳入時間，不讀時鐘；`ProcessingConcurrency.width` 由呼叫端傳入熱度和低耗電狀態，不讀 `ProcessInfo`。I/O（Photos、Vision、`ProcessInfo`、`OSSignposter`、`isIdleTimerDisabled`）只出現在 `ScreenshotProcessor`、`ProcessingSignposts` 和 `KeepsScreenAwake` | 3 秒自動消失用 `Task.sleep`，留在 store；跟現在的 toast 計時一致，不另外注入 clock |
| 4. 重複程式碼 | `setRecognition`、`applyClassification` 的單張修改規則抽到 `Shot.recordRecognition`、`Shot.applyAutoPlacement`，批次和單筆 API 共用；完成摘要沿用 `classificationSummary`；`ImportStep` 和 `ProcessingBar` 的進度條共用一個 `ProgressLine` 小元件，放在 `Theme/Components.swift` | 無 |
| 5. 命名 | `ProcessingProgress`、`ProcessingQueue`、`ProcessingOutcome` 統一用專案原有的「processing」（＝「處理中」）一詞；callback 用 `onBatchApplied`、`onRunFinished` 描述事件，取代語意不準的 `onRecognized`、`onIdle`；bool 用 `isVisible`、`didFail`；`importFoundCount` 取代模糊的 `found` | 無 |
| 6. 巢狀與複雜度 | `ScreenshotProcessor.run()` 只負責 task group 迴圈；單張工作抽成 `work(_:) async -> ProcessingOutcome`，裡面再拆成 `loadAndRecognize` 和 `classify`；`applyProcessingOutcomes` 先建 `[String: ProcessingOutcome]` 再一次掃描 `shots.indices`，迴圈內只有一層 `if let`；`ProcessingBar` 依照 `phase` 拆成 `RunningContent` 和 `FinishedContent` 兩個子 view | 無 |
| 7. SOLID | **S**：佇列、緩衝、進度、平行數量各自獨立；processor 只排程，store 只轉換狀態。**O**：新增工作種類只要在 `ProcessingQueue.Work` 加 case，在 `work(_:)` 加分支。**L**：`ScreenRecognizing` 的語意不變。**I**：processor 只對外露兩個 callback。**D**：recognizer、pipeline、photos、`concurrency` 都由 init 注入 | 無 |

## 實作步驟

1. **量測基準** — 動到：新增 `ProcessingSignposts.swift`；在現有 `ScreenshotProcessor` 的 `recognize`、`classify`、`mutate` 周圍加 signpost，每輪結束時 log 總結。在實機上（iPhone 15 等級）用 Instruments 的 os_signpost 和 Time Profiler 量 ≥ 1000 張，把每張各段耗時和每分鐘張數記到本文件的「量測紀錄」。驗證：`xcodebuild -scheme albumOrganizer -destination 'generic/platform=iOS' build`，Console 看得到總結 log。
2. **抽出 `Shot` 的修改規則** — 動到：`Models.swift`、`Library.swift`、`Library+Classification.swift`。純重構，行為不變。驗證：`cd Packages/ScreenshotKit && swift test`（現有測試全過）。
3. **批次套用** — 新增 `ProcessingOutcome.swift`、`classifierInput(blocks:barcodes:)` 和測試。驗證：`swift test --filter ProcessingOutcomeTests`。
4. **佇列、緩衝、平行數量** — 新增 `ProcessingQueue.swift`、`OutcomeBuffer.swift`、`ProcessingConcurrency.swift` 和各自的測試。驗證：`swift test --filter 'ProcessingQueueTests|OutcomeBufferTests|ProcessingConcurrencyTests'`。
5. **進度模型** — 新增 `ProcessingProgress.swift` 和測試。驗證：`swift test --filter ProcessingProgressTests`。
6. **改寫 `ScreenshotProcessor`** — worker pool、佇列、合併寫入、新的 callback；refinement 維持串行。驗證：App build 成功；實機上「處理中」會清空，分類結果抽查跟 `main` 一致。
7. **`LibraryStore` 接上進度** — 移除 `ImportProgress`、`finishImportSteps`；`startImport` 設定 `importFoundCount` 並 `begin`；接 `onBatchApplied`、`onRunFinished`；`finished` 3 秒後 `clear`。驗證：build 成功。
8. **匯入畫面** — `ImportStep` 改用 `processingProgress`，只留一顆按鈕，加 `.keepsScreenAwake()`；新增 `KeepsScreenAwake.swift`；把進度條抽成 `ProgressLine`。驗證：模擬器跑一次 onboarding（刪掉 App 重裝），確認按鈕一直可以按，切到相簿後數字能接上。
9. **App 內進度列** — 新增 `ProcessingBar.swift`，放進 `AppShell`；`UIState.showProcessing()`。驗證：模擬器裡匯入超過 20 張時進度列出現，點擊後跳到「處理中」，完成後顯示摘要並在 3 秒後消失；少於 20 張時不出現。
10. **再次量測與文件** — 重做步驟 1 的量測，記錄 5000 張的總耗時、每分鐘張數，跟 D5 的目標比較；更新 `doc/classification.md` 的處理流程章節。驗證：數字寫進本文件的「量測紀錄」。
11. **回歸** — 跑 `swift run classification-eval`（`Packages/ScreenshotKit`），確認分類準確率跟 `main` 相同（這次沒有改 OCR 參數，應該完全一致）。

## 測試計畫

- `ProcessingProgressTests`
  - `begin` 低於 20 張時 `isVisible == false`，≥ 20 張時為 `true`
  - 本輪中剩餘數掉到 20 以下時，`isVisible` 仍維持 `true`
  - `record` 時失敗的不算進 `remaining`，`total` 一路保持 `processed + remaining`
  - `updateRemaining` 在新截圖進來和隱藏截圖時，分母會跟著增減，`remaining` 不會小於 0
  - `finish` 之後 `phase == .finished`，摘要帶有 `retryLater`；`clear` 之後回到 `.idle`，所有數字歸零
- `ProcessingQueueTests`
  - 建佇列時，需要 OCR 的排在只需要分類的前面，順序跟 `shots` 一致（最新的在前）
  - `prioritize` 會插到最前面；不在處理中的 id 會被忽略
  - `refill` 只補新的 id，不會重複加入已排入或本輪已嘗試過的
  - `next()` 取過的 id 在本輪不會再出現（取代 `attemptedThisRun`）
- `ProcessingOutcomeTests`
  - 一批結果的套用結果，跟逐筆呼叫 `setRecognition` 加 `applyClassification` 完全相同（等價性測試）
  - 截圖在批次寫入前被手動搬移：分類結果被忽略，OCR 結果仍然寫入
  - 截圖在批次寫入前被隱藏或刪除：整筆略過，不會 crash
  - 失敗但沒用完重試次數：`recognitionAttempts` 加 1，仍然在處理中
- `OutcomeBufferTests`：滿 20 張要 flush；第一筆之後 500ms 要 flush；`drain` 後計時重新開始
- `ProcessingConcurrencyTests`：`.nominal` / `.fair` 時是 3；`.serious` / `.critical` 時是 1；低耗電模式時是 1
- 實機手動驗證：見實作步驟 6、8、9、10

## 量測紀錄

| 時間點 | 裝置 | 張數 | 總耗時 | 每分鐘張數 | 各段平均（讀圖 / OCR / 分類 / 套用） |
|--------|------|------|--------|------------|------|
| 基準（步驟 1） | 未量測：改寫前沒有先在實機上量 | | | | |
| 優化後，實機 Debug（width 3） | iPhone（1206×2622 截圖） | 95 | 37.0s | 154 | OCR 每張約 0.38s，Console 顯示 OCR 呼叫一個接一個執行 |
| 優化後，模擬器（只用來確認流程） | iPhone 17 模擬器 | 40 | 24.9s | 96 | — |
| 優化後（步驟 10），實機 | | | | | |

### OCR 參數 benchmark（2026-10-15，實機 Debug，50 張，`claude/loving-noether-8b39f8` 分支）

| # | 設定 | avgMs | 文字相似度 | 分類變動 |
|---|------|------:|-----------:|---------:|
| 00 | 現行（基準） | 409 | 1.000 | 0 |
| 01 | 縮圖 0.75 | 406 | 0.937 | 1 |
| 02 | 縮圖 0.5 | 389 | 0.918 | 4 |
| 03 | 關閉語言校正 | 395 | 1.000 | 0 |
| 04 | 最小字高 0.01 | 398 | 1.000 | 0 |
| 05 | 最小字高 0.02 | 392 | 0.946 | 2 |
| 06 | 跳過狀態列與 home indicator | 390 | 0.914 | 0 |
| 07 | 關閉條碼偵測 | 385 | 1.000 | 0 |
| 08–11 | 上述組合 | 373–395 | 0.900–0.911 | 1–2 |

結論：所有參數都在 ±10% 內，縮圖到 1/4 像素只快 5%，時間花在每次呼叫的固定成本。不採用任何新參數；`.fast` 不支援繁中。

## 風險與未決問題

- ✅ **已確認（2026-10-15）**：Vision OCR 是瓶頸且無法靠參數解決，目標改為約 33 分鐘搭配背景處理（見 D5）。以下兩項保留作為當時的判斷紀錄。
- ⚠️ **3 個 worker 不保證能達到 10 分鐘的目標**。5000 張 10 分鐘等於每張平均 120ms。如果步驟 1 量到 `.accurate` OCR 單張就要 300ms 以上，只靠平行化不夠，就要回到 Q6 用 ClassificationEval 評估 `.fast` 或縮圖。這是下一份計畫的範圍，這次只負責量測出數字。
- ⚠️ **Vision 平行處理的實際效益不確定**。Vision 在 Neural Engine 或 GPU 上可能會排隊，3 個 worker 不一定有 3 倍效果。步驟 10 要記錄 1、2、3 個 worker 的比較，用數字決定 `normalWidth` 的最終值。
- ⚠️ **iCloud 原圖下載**。「最佳化 iPhone 儲存空間」開啟時，`imageData` 要先從 iCloud 下載。平行處理會同時發出多個下載，網路慢時失敗數可能增加。失敗的處理照 D11、D13（下一輪重試）。
- ⚠️ **記憶體**。3 張全尺寸圖同時解碼，大約多 3 × 12MB，在可接受範圍。步驟 10 要用 Instruments Allocations 確認沒有持續上升。
- ❓ 無其他需要使用者決定的問題。

## 修訂紀錄

| 版本 | 日期 | 變更 |
|------|------|------|
| v1 | 2026-10-14 | 初版 |
| v2 | 2026-10-14 | 實作時的調整：①`ProcessingQueue.Work` 帶上 worker 需要的資料（是否最後一次重試、已有的文字），worker 不必再查 `Library`；`classifierInput(blocks:barcodes:)` 改成 `ClassifierInput(blocks:barcodes:excluded:)` 加上 `Library.excludedTargets`。②`applyProcessingOutcomes` 回傳 `ProcessingTally`（已處理、失敗、已分類、未分類），完成摘要用本輪的數字，不再用整個 library 的 `classificationSummary`，也就不需要 `ProcessingSummary`。③processor 多一個 `onRunStarted` callback。④匯入畫面的步驟從三列改成兩列（「掃描」、「辨識文字並自動分類」），因為兩者是同一張截圖一起完成的，原本 600ms 的假延遲拿掉。⑤`ProgressLine` 放在 `Theme/Components.swift` |
| v3 | 2026-10-15 | 依實機量測與 OCR benchmark：速度目標改為約 33 分鐘搭配下一階段的背景處理（D5），worker 從 3 降到 2（D15），補上量測紀錄 |
| v4 | 2026-10-15 | 修正：從 iCloud 還原的截圖已有分類但沒有 OCR 文字，仍要辨識，卻不在「處理中」裡，造成進度分母漏算、進度列中途才出現。分母改用 `processingWorkCount`；完成摘要只計入這一輪實際放進資料夾的截圖 |
| v5 | 2026-10-16 | 新增 D23：OCR 與規則分類後，Apple Intelligence 再分類「未分類」的階段也顯示進度列。`ProcessingProgress` 加上 `.refining` 階段，`.running` 改名 `.recognizing`、`processed` 改名 `completed`；processor 多 `onRecognitionFinished`、`onRefined` callback，`onRunFinished` 改成整輪（含再分類）結束才呼叫 |
