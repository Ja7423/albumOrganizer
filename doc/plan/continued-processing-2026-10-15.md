# Feature Plan：離開 App 後繼續整理截圖（BGContinuedProcessingTask）

| 項目 | 內容 |
|------|------|
| 規劃日期 | 2026-10-15 |
| 規劃方式 | grilling（1 輪，Q1–Q4）＋ feature-planner |
| 目前分支 | `claude/priceless-feistel-4d526c`（base `feature/processing-progress` `93437ed`） |
| 狀態 | 已實作，待實機驗證 |

## 需求摘要

使用者匯入 5000 張截圖（約 33 分鐘）途中切到別的 App 或鎖定螢幕時，OCR 與分類透過 iOS 26 的 `BGContinuedProcessingTask` 繼續跑，系統 UI（動態島／鎖定畫面）顯示進度。回到 App 時，tab bar 上方進度列的數字接續；被系統取消時不遺失已完成的結果。

這是 [background-processing-progress-2026-10-14.md](background-processing-progress-2026-10-14.md) D7 列為下一階段的工作。

### 範圍

- **In scope**
  - 使用者操作時提交 continued processing task：首次匯入、下拉重新整理、點進度列
  - 系統 UI 的標題、副標題、進度數字跟著 `ProcessingProgress` 更新
  - 到期（系統取消或使用者在系統 UI 按停止）時：暫停處理器、寫回已完成批次、存檔、結束 task
  - 回到前景時恢復暫停的那一輪，進度列數字接續
  - Info.plist 的 `BGTaskSchedulerPermittedIdentifiers`
- **Out of scope**
  - refinement（Apple Intelligence）在背景跑：task 在 OCR＋分類結束時就完成
  - 沒有使用者操作的自動處理輪（啟動時的新截圖、分類器升版）提交 task
  - `BGProcessingTask`（夜間充電時的排程處理）
  - 背景 GPU（`.gpu` resource 需要額外 entitlement，Vision OCR 不需要）

## 決策紀錄

| # | 決策 | 選擇 | 理由 / 被放棄的選項 |
|---|------|------|------|
| D1 | 何時提交 | 使用者操作時提交，且本輪 ≥ 20 張（`ProcessingProgress.visibilityThreshold`）：首次匯入（「允許取用照片」「還原備份」「從頭開始」之後開始匯入時）、下拉重新整理、點進度列 | Q2。`BGContinuedProcessingTaskRequest` 只能「代表目前在前景的 App」建立（SDK header），Apple 也要求由使用者明確操作觸發，所以**不能**在 `scenePhase == .background` 時才提交。被放棄：只在首次匯入（之後的大量處理離開就停）、任何 ≥ 20 張的輪次自動提交（違反使用者觸發原則） |
| D2 | 系統 UI 文案 | 標題「正在整理截圖」，副標題「已完成 1,234 / 5,000 張」，每批更新；開始前副標題「準備中」 | Q3。和 App 內進度列一致 |
| D3 | 到期處理 | 暫停而非結束：停止派新工作，等 2 張進行中的做完（約 0.4 秒），合併寫回，`saveNow()`，`setTaskCompleted(success: false)`。這一輪維持 `.running`，不呼叫 `onRunFinished` | Q4。進度列回到前景時數字接續（例如 1,234 / 5,000），不會從 0 重算。被放棄：結束這一輪、回來再開新一輪 |
| D4 | 回到前景 | `scenePhase == .active` 時 `resumeProcessing()`，繼續同一輪，只在前景跑，不自動重新提交 | Q4。重新提交需要使用者操作；使用者可以點進度列再次提交（D1） |
| D5 | 到期時 App 仍在前景 | 暫停、存檔後立刻恢復 | 預設值。系統可能因熱度或負載在前景就讓 task 到期，這時不該停止前景處理 |
| D6 | 何時完成 task | `onRunFinished`（OCR＋分類做完，refinement 之前）時 `setTaskCompleted(success: true)` | 預設值。和進度列範圍一致（原計畫 D4） |
| D7 | 提交策略 | `.queue`（SDK 預設） | 預設值。系統忙時排隊，輪到時若這一輪已結束就立刻完成；`.fail` 會讓使用者的操作直接沒有效果 |
| D8 | 識別碼與註冊 | Info.plist 允許 `$(PRODUCT_BUNDLE_IDENTIFIER).processing.*`；每次提交用新的 `<bundle>.processing.<UUID>`，提交前才註冊 handler | `BGContinuedProcessingTask` 不受「launch 結束前註冊」限制；同一個識別碼註冊兩次會讓 App 被殺，所以每次用新的識別碼 |
| D9 | 已有 task 時再次觸發 | 忽略（已提交或執行中都只保留一個） | 預設值 |
| D10 | 暫停途中回到前景 | `pause()` 等待進行中的工作時忽略 `resume()`；到期處理在 `pause()` 返回後，若 App 在前景就自行恢復 | 實作時發現：若在等待中恢復，這一輪會繼續跑，`pause()` 要等整輪結束才返回，到期 handler 就無法及時 `setTaskCompleted` |

## 現況分析

- **處理器**：[ScreenshotProcessor.swift](../../albumOrganizer/ScreenshotOrganizer/Services/ScreenshotProcessor.swift) 的 `run()` 每輪呼叫 `onRunStarted` → `processQueue()` → `onRunFinished`，之後做 refinement。`processQueue()` 以 `withTaskGroup` 派工作，迴圈裡 `addWork` 依 `concurrency()` 補位，結果進 `OutcomeBuffer`，結束時一定 `apply(buffer.drain())`，所以只要讓 `addWork` 不再派工作，迴圈自然收尾並寫回，這就是「暫停」需要的全部收尾。
- **進度**：[ProcessingProgress.swift](../../Packages/ScreenshotKit/Sources/ScreenshotKit/Processing/ProcessingProgress.swift) 是純值型別；`LibraryStore` 在 `beginProcessingRun`、`onBatchApplied`、`finishProcessingRun`、`mutate` 四處改它。
- **存檔**：`LibraryStore.saveNow()` 已經用 `beginBackgroundTask` 確保寫入完成，到期時直接重用。
- **背景時間的既有用法**：`saveNow()`、`backUp()` 用 `UIApplication.beginBackgroundTask`。
- **可重用**：`ProcessingBar.FinishedContent.summary`（完成摘要字串）搬到 ScreenshotKit 後，進度列和系統 UI 共用。
- **會被影響的既有程式碼**：`ScreenshotOrganizerApp`（`.active` 時恢復）、`ProcessingBar`（點擊時提交）、`LibraryStore.refresh()`／`startImport()`、`albumOrganizer/Info.plist`。

## 架構設計

```
使用者操作（匯入／下拉／點進度列）
  └─ LibraryStore.continueInBackground()
       └─ ContinuedProcessingService.submit(_:)     ── BGTaskScheduler（I/O）
LibraryStore.updateProgress { … }  ── 每次改 ProcessingProgress 後
       └─ ContinuedProcessingService.report(_:)     ── task.progress、updateTitle
            └─ ContinuedProcessingStatus(progress:)  ── ScreenshotKit，純函式：文案與數字
onRunFinished ── ContinuedProcessingService.finish()  ── setTaskCompleted(true)
到期 ── service.onExpired ── LibraryStore.handleContinuedProcessingExpired()
          └─ ScreenshotProcessor.pause()（等進行中的做完、寫回）→ saveNow() → 前景就 resume()
scenePhase .active ── LibraryStore.resumeProcessing() ── ScreenshotProcessor.resume()
```

- **ScreenshotKit（純）**：`ContinuedProcessingStatus` 把 `ProcessingProgress` 轉成標題／副標題／完成數／總數；`ProcessingProgress.isWorthContinuing(processingCount:)` 決定要不要提交；`ProcessingTally.summary` 是完成摘要。
- **`ContinuedProcessingService`（App，Services/）**：唯一碰 `BackgroundTasks` 的地方。負責註冊、提交、保存目前的 task、把狀態寫到 task、完成 task、到期時通知 store。不知道處理器存在。
- **`ScreenshotProcessor`**：新增 `pause()`／`resume()`。暫停期間 `start()` 不開新一輪；恢復時延續被暫停的那一輪，不再呼叫 `onRunStarted`（所以進度不會重置）。
- **`LibraryStore`**：把使用者操作轉成提交，把處理器事件轉成進度回報，協調到期時的暫停與存檔。

### 替代方案

| 方案 | 優點 | 缺點 | 結論 |
|------|------|------|------|
| 在 `.inactive` 時提交 | 不用改 UI 觸發點 | 非使用者操作；`.inactive` 也發生在控制中心、通知等情況，提交後不一定真的離開 | 不採用 |
| 到期時結束這一輪 | 處理器不用加暫停狀態 | 回到前景進度從 0 重算，違反「數字接上」 | 不採用（D3） |

## 檔案變更清單

| 動作 | 檔案 | 層 | 職責 |
|------|------|----|------|
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Processing/ContinuedProcessingStatus.swift` | 純邏輯 | 系統 UI 的文案與數字 |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Processing/ProcessingProgress.swift` | 純邏輯 | `isWorthContinuing(processingCount:)` |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Processing/ProcessingOutcome.swift` | 純邏輯 | `ProcessingTally.summary` |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/ContinuedProcessingStatusTests.swift` | 測試 | |
| 修改 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/ProcessingProgressTests.swift` | 測試 | |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Services/ContinuedProcessingService.swift` | Service | BGTaskScheduler 的註冊／提交／回報／完成／到期 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Services/ScreenshotProcessor.swift` | Service | `pause()`／`resume()` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Store/LibraryStore.swift` | Store | `continueInBackground()`、`resumeProcessing()`、`updateProgress`、到期處理 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/App/ScreenshotOrganizerApp.swift` | App | `.active` 時 `resumeProcessing()` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Shell/ProcessingBar.swift` | View | 點擊時提交；完成摘要改用 `tally.summary` |
| 修改 | `albumOrganizer/Info.plist` | 設定 | `BGTaskSchedulerPermittedIdentifiers` |
| 修改 | `doc/classification.md` | 文件 | 背景處理一段 |

## 介面草案

```swift
// ScreenshotKit
public struct ContinuedProcessingStatus: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let completed: Int64
    public let total: Int64
    public init(progress: ProcessingProgress)
    /// Before the first run reports in.
    public static let preparing: ContinuedProcessingStatus
}

extension ProcessingProgress {
    /// A run big enough to show the bar is worth keeping alive once the app leaves the screen.
    public func isWorthContinuing(processingCount: Int) -> Bool
}

extension ProcessingTally {
    /// 「已分類 N 張，未分類 M 張（K 張稍後重試）」
    public var summary: String { get }
}

// App
@MainActor
final class ContinuedProcessingService {
    /// Asked to stop: the store pauses processing and saves before the task ends.
    var onExpired: () async -> Void
    func submit(_ status: ContinuedProcessingStatus)
    func report(_ status: ContinuedProcessingStatus)
    func finish()
}

extension ScreenshotProcessor {
    /// Stops starting new screenshots, waits for the ones in flight and writes them back. The run stays open.
    func pause() async
    /// Carries on the paused run.
    func resume()
}

extension LibraryStore {
    /// From a user action: keeps a large run going after the app leaves the screen.
    func continueInBackground()
    func resumeProcessing()
}
```

## 規則檢核（pre-review）

| 規則 | 設計對策 | 殘留風險 |
|------|----------|----------|
| 1. 框架慣例 | Service 放 `Services/`，和 `ScreenshotProcessor`、`PhotoLibraryService` 並列；處理器事件用既有 callback 形式（`onExpired` 比照 `onRunStarted`）；`@MainActor final class` | 無 |
| 2. 架構可擴充性 | 之後加 `BGProcessingTask`（夜間）只要另一個 service 呼叫同一組 `pause()`／`resume()`／`start()`；加新的觸發點只要呼叫 `continueInBackground()`。沒有為單一實作新增 protocol | 無 |
| 3. 副作用 / Pure Function | 文案、數字、要不要提交都是 ScreenshotKit 的純函式並有測試；`BGTaskScheduler`、`UIApplication` 只出現在 service 與 store | 無 |
| 4. 重複程式碼 | 完成摘要從 `ProcessingBar` 搬到 `ProcessingTally.summary` 共用；store 四處改進度的地方收斂到 `updateProgress`，回報系統 UI 只寫一次；到期存檔重用 `saveNow()` | 無 |
| 5. 命名 | `pause`／`resume` 描述處理器狀態；`continueInBackground` 描述使用者意圖；`report` 只更新顯示不改狀態；`ContinuedProcessingStatus` 對應系統 API 名稱 | 無 |
| 6. 巢狀與複雜度 | 處理器只加一個 `isPaused` 和一個 `hasPausedRun` 旗標；`run()` 多一個 `if`；service 每個方法一層 guard | 無 |
| 7. SOLID | Service 只管系統 task 生命週期（S）；store 以建構子注入 service（D）；處理器不知道 BackgroundTasks | 無 |

## 實作步驟

1. **ScreenshotKit 純邏輯＋測試** — `ContinuedProcessingStatus`、`isWorthContinuing`、`ProcessingTally.summary`；驗證：`swift test`（`Packages/ScreenshotKit`）
2. **處理器暫停／恢復** — `ScreenshotProcessor.pause()`／`resume()`；驗證：app build
3. **ContinuedProcessingService** — 註冊、提交、回報、完成、到期；驗證：app build
4. **Store 與 App 接線** — `updateProgress`、`continueInBackground()`、`resumeProcessing()`、到期處理、`ProcessingBar` 點擊、`ScreenshotOrganizerApp` 的 `.active`；驗證：app build
5. **Info.plist、文件** — `BGTaskSchedulerPermittedIdentifiers`、`doc/classification.md`
6. **實機驗證**（模擬器不支援 continued processing）— 見下方測試計畫

## 測試計畫

- Unit（ScreenshotKit）
  - `ContinuedProcessingStatus`：執行中的文案與數字；完成時改為「整理完成」＋摘要；`preparing`
  - `isWorthContinuing`：執行中看 `isVisible`；尚未開始看處理中數量是否 ≥ 20
  - `ProcessingTally.summary`：有／沒有失敗
- 實機（手動）
  1. 刪除 App 重裝，匯入 ≥ 1000 張的相簿，按「允許取用照片」後馬上按 Home：動態島／鎖定畫面出現「正在整理截圖」，副標題的數字持續增加
  2. 等 1–2 分鐘回到 App：進度列的數字接在系統 UI 最後的數字之後，沒有從 0 開始
  3. 再次離開，在系統 UI 按停止：回到 App 時數字接續，處理繼續；Console（subsystem `com.chiawei.albumOrganizer`）看得到 pause／expire 的 log
  4. 處理到一半被系統取消後強制關閉 App 再開：已處理的截圖不會回到處理中
  5. 匯入完成後，系統 UI 消失

## 風險與未決問題

- ⚠️ Apple 文件沒有寫明 continued processing 是否需要 `UIBackgroundModes` 的 `processing`。先不加；若實機提交出現 `BGTaskSchedulerErrorCodeNotPermitted`，再補上。
- ⚠️ 背景時系統可能降低 CPU 優先權，背景速度可能低於前景的每分鐘 150 張；只能實機量。
- ⚠️ 模擬器不支援，只能在實機驗證。
- ❓ 到期後 App 被暫停期間，若使用者沒有回來，剩下的截圖等下次開 App 才繼續（符合 D4）。

## 修訂紀錄

| 版本 | 日期 | 變更 |
|------|------|------|
| v1 | 2026-10-15 | 初版 |
