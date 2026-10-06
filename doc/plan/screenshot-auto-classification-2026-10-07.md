# Feature Plan：截圖自動分類

| 項目 | 內容 |
|------|------|
| 規劃日期 | 2026-10-07 |
| 規劃方式 | grilling（4 輪，Q1–Q17） |
| 目前分支 | `claude/screenshot-classification-explanation-6350d6`（base `main`） |
| 狀態 | 已確認 |

## 需求摘要

把截圖自動放進「類別資料夾」：辨識完文字後，由分類器判斷主類別並直接放進對應資料夾，判斷不出來就留在「未分類」。使用者手動搬移的結果永遠鎖定，之後會成為 kNN 的樣本。標籤只用來放自動偵測到的特徵（含連結、QR code 等），以及使用者自己加的標籤。

成功的樣子：首次匯入完成後，大部分有文字的截圖已經在正確的資料夾裡；使用者修正過的截圖不會被搬回去；修改規則後，舊截圖會自動依新規則重新分類。

### 範圍

- **In scope（第一版）**
  - 資料模型：內建類別資料夾、分類狀態（處理中、自動、使用者鎖定）、系統特徵標籤、OCR 失敗重試
  - 規則層分類器，搭配 `ScreenshotClassifier` 協定與串接器，預留 kNN 和 LLM 的位置
  - 結構化訊號：Vision 條碼偵測、`NSDataDetector`、對話版面
  - 重新分類：分類器版本更新、刪除資料夾
  - UI：「處理中」列、空的內建資料夾淡化顯示、資料夾改名、詳細頁顯示判斷來源、首次匯入統計、系統標籤、有限存取時的提示
  - 拿掉建議機制（`suggestions`、`TagSuggester`、「有建議」chip、`SuggestionCard`）
- **Out of scope**
  - kNN 層、LLM 層，以及它們的重新分類時機（LLM 變得可用、kNN 多了樣本），留到第 3、4 步
  - 自動分類到使用者自建資料夾（要等 kNN）
  - 沒有文字的截圖分類（Q4）
  - 系統相簿同步（Q16，不做）
  - `BGTaskScheduler` 背景任務、`PHPersistentChangeToken` 增量同步、OCR 併發處理
  - SwiftData（見 D18）
  - 轉換舊的 `library.json`（Q3，App 還沒上架）

## 決策紀錄

| # | 決策 | 選擇 | 理由 / 被放棄的選項 |
|---|------|------|------|
| D1 | 自動分類的結果放在哪裡 | 主類別放資料夾（單選），特徵放標籤（多選） | Q1 C。放棄：只用資料夾、只用標籤、另外新增「類別」 |
| D2 | 類別由誰定義 | 內建類別，加上之後由使用者自建 | Q2 B。第一版只有內建類別 |
| D3 | 舊資料轉換 | 不轉換，直接改格式 | Q3：App 還沒上架 |
| D4 | 沒有文字的截圖 | 第一版不分類，放進未分類 | Q4 A |
| D5 | 資料夾和類別的關係 | 資料夾就是類別。內建資料夾可以改名和刪除；刪掉的內建類別會記下來，不再建回 | Q5 A。放棄：分成系統資料夾和使用者資料夾 |
| D6 | 自動套用還是建議 | 有把握就直接放進資料夾，並記錄判斷來源 | Q6 A。放棄：先建議、依信心高低決定 |
| D7 | 標籤 | 系統特徵標籤自動加上；使用者刪掉後不再加回 | Q7 A |
| D8 | 內建類別 | 收據、票券、對話、社群貼文、文章、程式碼、地點、食譜、優惠、帳號資訊、行程、筆記 | Q8，再加上「未分類」（`folderID == nil`） |
| D9 | 哪些操作算使用者修正 | 所有手動搬移（包含搬回未分類、辨識完成前就先搬）都算，並鎖定；只看過不算 | Q9 |
| D10 | 重新分類的範圍 | 版本更新時：所有自動判斷的截圖。LLM 或 kNN 帶來新能力時：只有未分類的截圖 | Q10。第一版只實作版本更新這個時機 |
| D11 | 刪除資料夾 | 自動判斷的截圖重新分類，並排除被刪掉的類別；使用者放的截圖移到未分類並鎖定 | Q11 B |
| D12 | 類別識別 | 內建類別用固定的 `BuiltInCategory` key 加上 `hint`，名稱只是顯示用 | Q12 A |
| D13 | 自動分類要多明顯 | 格狀列表不標示；詳細頁顯示來源；首次匯入完成時顯示一次統計；空的內建資料夾淡化顯示 | Q13 A |
| D14 | 特徵標籤 | 含連結、QR code、含電話、含日期、含地址；保留使用者自己加標籤 | Q14 |
| D15 | 處理中的截圖 | 資料夾列表最上面顯示「處理中 N 張」，不出現在未分類；OCR 失敗重試到上限後放進未分類 | Q15 B |
| D16 | 系統相簿同步 | 不做 | Q16 A |
| D17 | 有限存取 | 功能降級，顯示提示並提供選更多截圖的按鈕 | Q17 B |
| D18 | 儲存方式 | 繼續用 `Library` 值型別存成 JSON，不換 SwiftData | 預設值（可推翻）。所有規則都在 `ScreenshotKit` 的純值型別裡，不需要資料庫就能測試；幾千筆截圖用 JSON 就夠了。等 kNN 要存 embedding 時再評估 |
| D19 | 版本號 | 第一版只有 `classifierVersion` | 預設值。OCR 和 embedding 第一版不會改版，先不加 `ocrVersion` 和 `embeddingVersion`；kNN 那一步再加 `embeddingVersion` |
| D20 | OCR 失敗重試上限 | 3 次，每次執行時每張截圖最多試 1 次 | 預設值 |
| D21 | Vision API | 延用現有的 `VNRecognizeTextRequest`，加上 `VNDetectBarcodesRequest`，在同一個 handler 裡執行 | 預設值。和現有程式碼一致；換成 iOS 18 的 `RecognizeTextRequest` 是另一件事 |
| D22 | 規則層的判斷方式 | 每個類別算一個分數。最高分超過門檻，而且領先第二名夠多才採用，否則回傳 `nil` | 預設值。對應分析中提到的「高準確率才能直接結束判斷」，門檻放在 `RuleClassifier.Configuration` 裡 |

## 現況分析

- **最相似的既有功能**：`Library.setRecognition` 加上 `TagSuggester`（[Library.swift:100](../../Packages/ScreenshotKit/Sources/ScreenshotKit/Library.swift)、[TagSuggester.swift](../../Packages/ScreenshotKit/Sources/ScreenshotKit/TagSuggester.swift)）。它們示範了「`ScreenshotKit` 放純邏輯，`LibraryStore` 負責 I/O 和流程」的分工，新程式碼照這個分工寫。
- **可以重用的部分**
  - `TagSuggester.rules` 的關鍵字和 regex（地址、優惠碼、連結），搬進 `RuleClassifier` 的類別規則和 `FeatureDetector`
  - `Library.update(_:_:)` 這個 private helper，所有批次修改截圖都經過它
  - `Library.move`、`createFolder`、`deleteFolder`、`normalizedTag`
  - `TextBlockFilter.droppingStatusBar`
  - UI 元件：`FolderRow`、`TagRow`、`TagChip`、`ScreenHeader`、`NameDialog`、`MetaRow`、`ClassicalButtonStyle`
  - `Info.plist` 已經設了 `PHPhotoLibraryPreventAutomaticLimitedAccessAlert`
- **需要新增的資料來源**：Vision 條碼偵測，放進 `TextRecognizer` 同一次執行；`NSDataDetector` 是 Foundation 的 API，可以放在 `ScreenshotKit` 裡。
- **會被影響的既有程式碼**
  - `ScreenshotKit`：`Models.swift`（`Shot`、`Folder`）、`Library.swift`（`Scope`、同步、資料夾、標籤）、`Search.swift`（搜尋範圍要包含特徵標籤）、`TagSuggester.swift`（刪除）、兩個測試檔
  - App：`LibraryStore.swift`（辨識流程）、`TextRecognizer.swift`、`PhotoLibraryService.swift`（有限存取）、`UIState.swift`（`Route`、`Dialog`）、`FoldersScreen.swift`、`TagsScreen.swift`、`ShotGridScreen.swift`、`ShotDetailScreen.swift`、`Sheets.swift`、`OnboardingView.swift`

## 架構設計

```
SwiftUI Views ──讀取──▶ LibraryStore（@Observable：library、存檔、onboarding、同步）
                          │ mutate
                          ▼
                    ScreenshotProcessor（@MainActor：辨識與分類佇列）
                     │            │                     │
     PhotoLibraryService   ScreenRecognizing       ClassificationPipeline (ScreenshotKit)
      （讀取圖片資料）      （Vision：文字＋條碼）     ├ RuleClassifier        ← 第一版
                                                    ├ KNNClassifier         ← 第 4 步
                                                    └ FoundationModelsClassifier（app target）← 第 3 步
                                                   FeatureDetector / SignalExtractor（純函式）
```

各層的職責：

- **`ScreenshotKit`（純邏輯，不依賴 Photos 或 Vision）**
  - `Library`：所有狀態轉換，包括套用分類、使用者修正、刪除資料夾後重新排入佇列、列出需要分類的截圖、匯入統計。
  - `SignalExtractor`：從文字區塊和條碼算出 `ScreenshotSignals`，包括 `NSDataDetector` 的結果、對話版面、符號密度。
  - `FeatureDetector`：從 `ScreenshotSignals` 算出特徵標籤。
  - `RuleClassifier`：從 `ClassifierInput` 算出類別判斷結果，或回傳 `nil`。
  - `ClassificationPipeline`：依序呼叫各層，套用每一層的門檻，跳過被刪掉的內建類別。
- **App**
  - `ScreenshotProcessor`：只負責佇列。依序取圖、OCR、組出輸入、呼叫 pipeline，再用 `mutate` 寫回結果。佇列從 `LibraryStore` 搬過來，讓 `LibraryStore` 只管狀態、存檔和 onboarding。
  - `ScreenRecognizing`：協定。由 `VisionScreenRecognizer` 實作，把現在的 `TextRecognizer` 改成可以注入的版本。
- **Views**：只讀取 `Library` 的查詢結果，所有寫入都透過 `store.mutate`。不新增 view model，比照現有寫法。

### 狀態模型

```
                 sync 新增
                    ▼
   ┌──────── placement = .pending ◀────────────── 版本更新 / 所在資料夾被刪（只限 .auto）
   │   recognition: pending ─OCR─▶ done
   │                      └─失敗─▶ failed(attempts < 3) ─下次執行─▶ 重試
   │                               failed(attempts ≥ 3) ─▶ 當作沒有文字
   ▼ pipeline
 placement = .auto(source?, version)   folderID = 類別資料夾，或 nil（未分類）
   │ 使用者搬移（任何時候，包含 .pending）
   ▼
 placement = .user                     永遠不再自動處理；之後成為 kNN 樣本
```

- **處理中**：`placement == .pending`
- **未分類**：`folderID == nil && placement != .pending`

### 替代方案

| 方案 | 優點 | 缺點 | 結論 |
|------|------|------|------|
| 第一版只寫 `RuleClassifier`，不寫協定和串接器 | 程式碼更少 | 第 3、4 步要回頭重寫 `LibraryStore` 的流程；門檻和鎖定邏輯會散在各處 | 不採用。kNN 和 LLM 已經排進路線圖，屬於可預見的需求 |
| 用 `ClassificationState` 加上 `folderID` 組合表示狀態，不用 `Placement` | 欄位更扁平 | 會出現不合理的組合，例如 `.user` 卻沒有修正紀錄 | 不採用 |

## 檔案變更清單

| 動作 | 檔案 | 層 | 職責 |
|------|------|----|------|
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Category.swift` | Model | `BuiltInCategory`（key、預設名稱、`hint`）、`ClassificationTarget` |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Placement.swift` | Model | `Placement`、`AutoPlacement`、`ClassifierSource` |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/FeatureTag.swift` | Model | `FeatureTag` 與顯示名稱 |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Signals.swift` | 純函式 | `ScreenshotSignals`、`SignalExtractor` |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/FeatureDetector.swift` | 純函式 | 從訊號算出特徵標籤 |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Classification/ScreenshotClassifier.swift` | 協定 | `ClassifierInput`、`ClassifierVerdict`、`ScreenshotClassifier` |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Classification/RuleClassifier.swift` | 純函式 | 類別規則表、分數計算、門檻 |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Classification/ClassificationPipeline.swift` | 純邏輯 | 依序呼叫各層、門檻、排除被刪掉的類別、`version` |
| 新增 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Library+Classification.swift` | Model | `Library` 的分類相關修改與查詢 |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Models.swift` | Model | `Shot`：移除 `suggestions`，加上 `placement`、`featureTags`、`dismissedFeatureTags`、`barcodes`、`recognitionAttempts`。`Folder`：加上 `builtIn` |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Library.swift` | Model | `Scope` 移除 `.suggested`，加上 `.processing`、`.feature`；初始化時建立內建資料夾；`deletedBuiltIns`；`move` 標記為 `.user`；`deleteFolder` 依 D11 處理；`renameFolder`；`setRecognition` 改成只存 OCR 結果；移除建議相關的 API |
| 修改 | `Packages/ScreenshotKit/Sources/ScreenshotKit/Search.swift` | 純函式 | 搜尋範圍包含特徵標籤的顯示名稱 |
| 刪除 | `Packages/ScreenshotKit/Sources/ScreenshotKit/TagSuggester.swift` | — | 規則已經搬進 `RuleClassifier` 和 `FeatureDetector` |
| 修改 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/LibraryTests.swift` | Test | 移除建議相關的測試，加上狀態轉換的測試 |
| 改名 | `SearchAndSuggestTests.swift` → `SearchTests.swift` | Test | 只保留搜尋的測試 |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/RuleClassifierTests.swift` | Test | 各類別的正例、反例和模糊情況 |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/ClassificationPipelineTests.swift` | Test | 依序呼叫、門檻、排除被刪掉的類別 |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/SignalsAndFeaturesTests.swift` | Test | `SignalExtractor`、`FeatureDetector` |
| 新增 | `Packages/ScreenshotKit/Tests/ScreenshotKitTests/Fixtures/labeled-ocr.json` | Test | 合成的 OCR 文字和期望類別，做回歸測試用 |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Services/ScreenshotProcessor.swift` | Service | 辨識和分類佇列 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Services/TextRecognizer.swift` | Service | 改成 `ScreenRecognizing` 協定加上 `VisionScreenRecognizer`，同時回傳條碼 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Services/PhotoLibraryService.swift` | Service | 加上 `isLimited`、`presentLimitedLibraryPicker(from:)` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Store/LibraryStore.swift` | Store | 佇列交給 `ScreenshotProcessor`；`ImportProgress` 的第 2 步改成「自動分類」；加上 `isLimitedAccess` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Store/UIState.swift` | UI state | `Route` 加上 `.processing`、`.feature(FeatureTag)`；`Dialog` 加上 `.renameFolder(UUID)` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Library/FoldersScreen.swift` | View | 「處理中」列、空的內建資料夾淡化、改名選單、有限存取提示 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Library/TagsScreen.swift` | View | 移除 `SuggestionCard`；分「偵測到的特徵」和「我的標籤」兩區 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Library/ShotGridScreen.swift` | View | 移除「有建議」chip 和閃光圖示；支援新的 `Route`；更新空狀態文字 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Detail/ShotDetailScreen.swift` | View | 資料夾按鈕旁顯示「自動分類 · 規則」；顯示特徵標籤，可以刪除；移除建議區塊 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Shell/Sheets.swift` | View | 移除建議區塊；標籤 sheet 顯示特徵標籤；`NameDialog` 支援改名 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Onboarding/OnboardingView.swift` | View | 步驟文字改成「自動分類」；完成時顯示「已分類 N 張，未分類 M 張」 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Common/ShotFormat.swift` | View helper | `ClassifierSource` 的顯示文字（規則、kNN、LLM），比照現有的 `ShotFormat` |

## 介面草案

```swift
// Category.swift
/// A category the app ships with. The raw value is the stable key; the folder name is display-only.
public enum BuiltInCategory: String, Codable, CaseIterable, Sendable {
    case receipt, ticket, chat, social, article, code, place, recipe, coupon, credential, schedule, note

    public var defaultName: String { … }   // 收據、票券…
    /// Plain-language description for classifiers that need one (LLM prompt).
    public var hint: String { … }
}

/// What a classifier may answer. Custom folders become targets once kNN exists.
public enum ClassificationTarget: Hashable, Sendable {
    case builtIn(BuiltInCategory)
    case folder(UUID)
}

// Placement.swift
public enum ClassifierSource: String, Codable, Sendable { case rule, knn, llm }

public struct AutoPlacement: Codable, Hashable, Sendable {
    /// `nil` when no layer was confident enough and the shot stayed in 未分類.
    public var source: ClassifierSource?
    public var classifierVersion: Int
}

/// How a screenshot got into its folder.
public enum Placement: Codable, Hashable, Sendable {
    /// Waiting for recognition or classification; shown under 處理中.
    case pending
    case auto(AutoPlacement)
    /// Moved by the user. Never reclassified; a training sample for kNN.
    case user
}

// FeatureTag.swift
public enum FeatureTag: String, Codable, CaseIterable, Sendable {
    case link, qrCode, phone, date, address
    public var displayName: String { … }   // 含連結、QR code…
}

// Models.swift（只列出變動的部分）
public struct Shot {
    public var folderID: UUID?
    public var placement: Placement                  // 取代 suggestions
    public var tags: [String]                        // 只放使用者自己加的標籤
    public var featureTags: Set<FeatureTag>
    public var dismissedFeatureTags: Set<FeatureTag>
    public var barcodes: [String]
    public var recognition: RecognitionState
    public var recognitionAttempts: Int
}

public struct Folder {
    public let id: UUID
    public var name: String
    /// Set for folders the app created for a built-in category.
    public let builtIn: BuiltInCategory?
}

// Signals.swift
public struct ScreenshotSignals: Hashable, Sendable {
    public var links: Int, phones: Int, dates: Int, addresses: Int
    public var barcodes: Int
    public var hasAlternatingBubbles: Bool   // 對話版面
    public var symbolDensity: Double         // 程式碼
}

public enum SignalExtractor {
    public static func extract(blocks: [TextBlock], barcodes: [String]) -> ScreenshotSignals
}

public enum FeatureDetector {
    public static func detect(_ signals: ScreenshotSignals, text: String) -> Set<FeatureTag>
}

// Classification/ScreenshotClassifier.swift
public struct ClassifierInput: Sendable {
    public var text: String
    public var signals: ScreenshotSignals
    /// Targets this classifier must not answer (deleted built-ins).
    public var excluded: Set<ClassificationTarget>
}

public struct ClassifierVerdict: Hashable, Sendable {
    public var target: ClassificationTarget
    public var confidence: Double
    public var source: ClassifierSource
}

public protocol ScreenshotClassifier: Sendable {
    func classify(_ input: ClassifierInput) async throws -> ClassifierVerdict?
}

// Classification/RuleClassifier.swift
public struct RuleClassifier: ScreenshotClassifier {
    public struct Configuration: Sendable {
        public var minScore: Double      // 預設 0.7
        public var minMargin: Double     // 最高分領先第二名的最小差距，預設 0.2
    }
    public init(configuration: Configuration = .init())
    public func classify(_ input: ClassifierInput) async throws -> ClassifierVerdict?
    /// Exposed for tests and tuning.
    public func scores(for input: ClassifierInput) -> [BuiltInCategory: Double]
}

// Classification/ClassificationPipeline.swift
public struct ClassificationPipeline: Sendable {
    /// Bump whenever any layer's rules, thresholds or prompt change (D10/D19).
    public static let version = 1
    public init(layers: [(classifier: any ScreenshotClassifier, threshold: Double)])
    /// First verdict that clears its layer's threshold; `nil` → 未分類. A layer that throws is skipped.
    public func classify(_ input: ClassifierInput) async -> ClassifierVerdict?
}

// Library+Classification.swift
extension Library {
    /// Shots whose recognition is done (or gave up) and that need a classifier pass.
    public var pendingClassificationIDs: [String] { get }
    /// Builds the classifier input for one shot; excludes deleted built-ins.
    public func classifierInput(for id: String) -> ClassifierInput?
    /// Stores OCR output; does not classify.
    public mutating func setRecognition(_ id: String, blocks: [TextBlock]?, barcodes: [String])
    /// Applies a pipeline result unless the user has locked the shot in the meantime.
    public mutating func applyClassification(_ id: String, verdict: ClassifierVerdict?, version: Int)
    /// Marks every `.auto` shot older than `version` as pending (D10).
    public mutating func requeueOutdated(version: Int)
    public mutating func renameFolder(_ id: UUID, to name: String)
    public mutating func dismissFeatureTag(_ tag: FeatureTag, from id: String)
    public var importSummary: (classified: Int, unsorted: Int) { get }
}

// App: Services/TextRecognizer.swift
struct RecognitionOutput: Sendable { var blocks: [TextBlock]; var barcodes: [String] }
protocol ScreenRecognizing: Sendable {
    func recognize(_ data: Data, orientation: CGImagePropertyOrientation) async throws -> RecognitionOutput
}
struct VisionScreenRecognizer: ScreenRecognizing { … }

// App: Services/ScreenshotProcessor.swift
@MainActor
final class ScreenshotProcessor {
    init(photos: PhotoLibraryService,
         recognizer: any ScreenRecognizing,
         pipeline: ClassificationPipeline,
         library: @escaping @MainActor () -> Library,
         mutate: @escaping @MainActor ((inout Library) -> Void) -> Void,
         onProgress: @escaping @MainActor () -> Void)
    func start()                         // 重複呼叫沒有影響
    func prioritize(_ id: String)
}
```

`Library` 各個操作的規則：

- **`move(_:to:)`**：設定 `folderID`，並把 `placement` 設成 `.user`。
- **`deleteFolder(_:)`**
  - `.user` 的截圖：`folderID = nil`，維持 `.user`。
  - `.auto` 的截圖：`folderID = nil`，改成 `.pending`。
  - 如果刪掉的是內建資料夾，把它的類別加進 `deletedBuiltIns`。
- **`applyClassification`**
  - `.user` 的截圖不改（守住鎖定）。
  - 判斷結果是 `.builtIn(c)`：找到 `builtIn == c` 的資料夾。如果類別已被刪掉，或找不到資料夾，就當作 `nil`。
  - 同時更新 `featureTags`，扣掉 `dismissedFeatureTags`。
- **`Library.init` 和解碼後**：為不在 `deletedBuiltIns` 裡、也還不存在的內建類別建立資料夾，順序依照 `BuiltInCategory.allCases`。
- **`pendingRecognitionIDs`**：`recognition == .pending`，或是 `.failed` 而且 `recognitionAttempts < 3`。

## 規則檢核（pre-review）

| 規則 | 設計對策 | 殘留風險 |
|------|----------|----------|
| 1. 框架慣例 | 純邏輯放 `ScreenshotKit`，I/O 放 App 的 `Services/`，比照 `TagSuggester` 和 `LibraryStore` 的分工。Views 透過 `@Environment(LibraryStore.self)` 讀取、用 `store.mutate` 寫入。測試延用 XCTest。Vision 延用 `VN*` API（D21） | 無 |
| 2. 架構可擴充性 | 新增內建類別：加一個 enum case 和一筆規則，加完 Swift 的 exhaustive switch 會在編譯時指出漏掉的地方。新增分類層：實作 `ScreenshotClassifier`，加進 `layers`。新增特徵：加一個 `FeatureTag` case 和一個偵測函式。門檻集中在 `RuleClassifier.Configuration` 和 `layers` 的 threshold。協定目前只有一個實作，但 kNN 和 LLM 已排進路線圖（見替代方案） | 「LLM 變得可用、kNN 多了樣本」這兩種重新分類的時機，第一版刻意不做，避免出現沒人用的擴充點 |
| 3. 副作用 / Pure Function | 分類、訊號、特徵、狀態轉換都是 `ScreenshotKit` 的純函式或 `mutating` 值型別方法。`ScreenshotProcessor` 只有在取圖、OCR、寫回這三處有副作用。`NSDataDetector` 在函式內建立，沒有可變的全域狀態 | 無 |
| 4. 重複程式碼 | 重用 `TagSuggester` 的 regex、`Library.update`、`move`、`createFolder`、`FolderRow`、`TagRow`、`NameDialog`。`isUnsorted` 和 `isProcessing` 寫成 `Shot` 的具名 getter，`Scope` 和匯入統計共用 | 無 |
| 5. 命名 | `Placement`（截圖怎麼被放進資料夾）、`ClassifierVerdict`、`ClassificationTarget`、`BuiltInCategory`、`FeatureTag`、`ScreenshotSignals`、`ScreenshotProcessor`。bool 以 `is`/`has` 開頭（`hasAlternatingBubbles`、`isLimited`）。「未分類」在全程式只用 `folderID == nil && !isProcessing` 這個定義 | `ScreenshotProcessor` 有點籠統，但比 `Manager` 精確；替代名稱是 `RecognitionQueue` |
| 6. 巢狀與複雜度 | `RuleClassifier` 用規則表取代逐類別的 `if`：`score(rule:input:)` 只負責算一筆規則的分數，`pick(scores:)` 處理門檻和差距。`applyClassification` 用 guard clause 處理鎖定。`FoldersScreen` 的列拆成 `ProcessingRow`，並重用 `FolderRow`（加上 `isDimmed`） | 無 |
| 7. SOLID | **S**：`LibraryStore` 管狀態、存檔和 onboarding；`ScreenshotProcessor` 管佇列；`ClassificationPipeline` 管各層的順序。**O**：見規則 2。**L**：分類層判斷不出來時回傳 `nil`，不拋出 `fatalError` 或未實作的錯誤；pipeline 會跳過拋錯的那一層。**I**：`ScreenshotClassifier` 只有一個方法；`ScreenRecognizing` 只有一個方法。**D**：辨識器、pipeline 和 `PhotoLibraryService` 都由 `ScreenshotProcessor` 的建構子注入，取代現在的靜態 `TextRecognizer.recognize` | `PhotoLibraryService.shared` 仍然是單例，但已經透過 `LibraryStore` 的建構子注入，維持現狀 |

## 實作步驟

每一步完成後，`swift test` 和 App 都能 build 成功。

1. **新增模型型別** — 新增 `Category.swift`、`Placement.swift`、`FeatureTag.swift`。驗證：在 `Packages/ScreenshotKit` 執行 `swift build`。
2. **訊號與特徵** — 新增 `Signals.swift`、`FeatureDetector.swift`，以及 `SignalsAndFeaturesTests`。驗證：`swift test`。
3. **規則分類器與 pipeline** — 新增 `Classification/` 底下三個檔案；把 `TagSuggester` 的規則搬過來；新增 `RuleClassifierTests`、`ClassificationPipelineTests`、`Fixtures/labeled-ocr.json`（每個類別至少 3 個正例和 1 個容易混淆的反例）。驗證：`swift test`。
4. **`Library` 改造** — 修改 `Models.swift`、`Library.swift`，新增 `Library+Classification.swift`；刪除 `TagSuggester.swift`；修改 `Search.swift`；更新測試。這一步會讓 App 編譯失敗，要和第 5 步一起提交，或在 App 端先暫時接上。驗證：`swift test`。
5. **App 處理流程** — 修改 `TextRecognizer.swift`；新增 `ScreenshotProcessor.swift`；修改 `LibraryStore.swift`（啟動時呼叫 `requeueOutdated(version:)`）。驗證：在模擬器 build；匯入幾張含文字的截圖，確認截圖會被放進資料夾。
6. **資料夾 UI** — 修改 `UIState.swift`、`FoldersScreen.swift`、`ShotGridScreen.swift`、`Sheets.swift`（改名）。驗證：在模擬器上確認「處理中」列、淡化的空資料夾、改名、刪除後重新分類都正常。
7. **標籤與詳細頁 UI** — 修改 `TagsScreen.swift`、`ShotDetailScreen.swift`、`Sheets.swift`、`ShotFormat.swift`。驗證：特徵標籤會顯示，刪除後不會再出現；詳細頁顯示判斷來源。
8. **Onboarding 與有限存取** — 修改 `OnboardingView.swift`、`PhotoLibraryService.swift`、`FoldersScreen.swift`。驗證：在模擬器上選「有限存取」，確認會出現提示，也能開啟選取畫面。
9. **收尾** — 用 grep 確認專案裡已經沒有 `suggestion`、`Suggest`、`sparkles`；執行 `swift-format-runner`；用 `swift-code-review` 自我檢查。

## 測試計畫

- **`RuleClassifier`**
  - 每個類別的典型 OCR 文字都會分到正確的類別。
  - 只有弱訊號時回傳 `nil`，例如只出現 `total`。
  - 兩個類別分數接近時回傳 `nil`，例如對話裡有連結。
  - 被排除的類別不會成為判斷結果。
  - `labeled-ocr.json` 的整體準確率不低於基準值，作為回歸測試。
- **`ClassificationPipeline`**
  - 第一層沒超過門檻時，會交給下一層。
  - 某一層拋錯時會跳過。
  - 所有層都判斷不出來時回傳 `nil`。
  - 用假的 classifier 測順序。
- **`Library` 狀態轉換**
  - `move` 之後，`applyClassification` 不會改動截圖，包含截圖還是 `.pending` 時就先被搬走的情況（處理途中被搬）。
  - `deleteFolder`：`.auto` 的截圖改成 `.pending`，`.user` 的截圖移到未分類並維持 `.user`；刪掉內建資料夾後，下次分類不會再分到它，也不會把它重新建回來。
  - `requeueOutdated` 只會影響版本較舊的 `.auto` 截圖。
  - OCR 失敗 3 次後，截圖不再出現在 `pendingRecognitionIDs`，而是排進分類佇列，最後放進未分類。
  - `dismissFeatureTag` 之後，重新分類也不會再加回那個標籤。
  - `Scope.processing` 和 `.unsorted` 不會重疊。
  - `importSummary` 的數字正確。
  - 內建資料夾的初始建立和解碼後補建都正確。
- **`SignalExtractor` 和 `FeatureDetector`**
  - 網址、電話、台灣地址、日期都能偵測到。
  - 左右交錯的文字區塊會判定為對話版面。
  - 符號密度的門檻正確。
- **手動測試（模擬器）**：首次匯入、截圖後回到 App、改名、刪除內建資料夾、有限存取。

## 風險與未決問題

- ⚠️ **還沒有真實截圖的評估集**：`labeled-ocr.json` 是合成的資料，只能防止規則被改壞，無法衡量真實的準確率。建議在第 5 步完成後，從自己的相簿標註 100–200 張截圖，用來調整 `minScore` 和 `minMargin`。
- ⚠️ **第一版的分類率可能偏低**：只有規則層，而且規則刻意設得保守，可能有相當比例的截圖會留在「未分類」。這是有意的取捨（錯放比不放更糟），等加上 kNN 和 LLM 再提高分類率。
- ⚠️ **開發中裝置的舊 `library.json` 會無法解碼**：程式會改用空的 `Library`，所有截圖重新匯入，舊的手動資料夾和標籤會消失。App 還沒上架，可以接受（Q3）。
- ⚠️ **「含日期」可能太常出現**：依 Q14，等有評估集後再決定要不要拿掉。
- ❓ **`RuleClassifier` 的初始門檻**：0.7 和 0.2 是推測值，要靠評估集決定。
- ❓ **使用者自建資料夾和內建類別同名時**：例如使用者刪掉內建的「收據」，又自己建了一個「收據」。依 D5，App 不會把內建類別建回來，自建的「收據」也不會被自動分類，要等 kNN 才會。這個行為要不要在 UI 上說明？

## 實作與計畫的差異

| 項目 | 計畫 | 實作 | 原因 |
|------|------|------|------|
| 規則層門檻 | `RuleClassifier.Configuration` 有 `minScore` 和 `minMargin` | `RuleClassifier` 只保留 `minMargin`；最低分數門檻是 `ClassificationPipeline.Layer.threshold`（`.standard` 為 0.7） | 避免同一個門檻設定在兩個地方 |
| `FeatureDetector.detect` | 參數為 `(signals, text:)` | 參數只有 `signals` | 所需資訊都已經在 signals 裡 |
| 日期偵測 | 用 `NSDataDetector` 加上 regex | 只用明確日期格式的 regex，例如 `2026/10/12`、`10 月 12 日` | `NSDataDetector` 會把「今天」和單獨的時間也算成日期，「含日期」會太常出現（呼應 Q14） |
| `ScreenshotProcessor` 介面 | `onProgress` | 改成 `onRecognized`、`onIdle` 兩個 callback | 匯入進度需要分別知道「辨識了一張」和「佇列跑完」 |
| 刪除資料夾 | View 呼叫 `store.mutate { $0.deleteFolder }` | 新增 `LibraryStore.deleteFolder(_:)`，同時重新啟動佇列 | 被重新排入佇列的截圖要立刻開始處理 |
| 歡迎頁文案 | 未列入計畫 | 第 3 點改成「自動分類：依截圖內容自動放進資料夾，隨時可以改。」 | 原文案描述的是已經拿掉的建議機制 |
| 有限存取提示 | 只放在資料夾頁 | 資料夾頁和「截圖」分頁都顯示（`LimitedAccessBanner`） | App 預設開在「截圖」分頁 |
| 條碼偵測 | 和文字辨識放在同一次 `perform` | 分開執行，條碼偵測失敗時只略過條碼 | 模擬器上條碼請求會失敗（Could not create inference context），連帶讓文字辨識全部失敗 |
| 電話偵測 | 用 `NSDataDetector` 加上 regex | 只用台灣電話格式的 regex（含 `+886`） | `NSDataDetector` 會把「統一編號 12345678」這類 8 位數字當成電話 |
| 程式碼規則 | 沿用 `TagSuggester` 的關鍵字 | 加上 `struct `、`enum `、`interface ` | 模擬器測試中，SwiftUI 程式碼截圖被分到未分類 |
| `ClassificationPipeline.version` | 1 | 3 | 模擬器驗證時修改了兩次規則，也藉此驗證版本更新後會重新分類 |
| SwiftFormat | 第 9 步要執行 | 沒有執行 | repo 沒有 `.swiftformat` 設定，原本的程式碼也不符合預設規則，套用會改到無關的程式碼 |

## 修訂紀錄

| 版本 | 日期 | 變更 |
|------|------|------|
| v1 | 2026-10-07 | 初版 |
| v2 | 2026-10-07 | 實作完成，記錄與計畫的差異 |
| v3 | 2026-10-07 | 模擬器驗證後的修正 |
