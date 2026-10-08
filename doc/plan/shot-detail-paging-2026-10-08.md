# Feature Plan：ShotDetailScreen 左右滑動切換截圖

| 項目 | 內容 |
|------|------|
| 規劃日期 | 2026-10-08 |
| 規劃方式 | 直接規劃 |
| 目前分支 | `main`（實作時另開 branch） |
| 狀態 | 已確認（實作中，branch `feature/shot-detail-paging`） |

## 需求摘要

在詳細頁左右滑動，就能切到上一張／下一張截圖，不用先返回 grid 再點下一張。翻頁的順序和範圍跟「從哪裡點進來」一致：從 grid 進來就照那個 grid 的順序（所有截圖、某個資料夾、某個標籤、目前選的 chip），從搜尋進來就照搜尋結果的順序。

成功的樣子：滑動有分頁吸附，相鄰的圖會先載好；header、資料夾／標籤列、分享、移動和標籤 sheet 都作用在目前這一頁；從左邊緣滑動返回的手勢照舊可用。

### 範圍

- **In scope**
  - 用水平分頁的 ScrollView 取代單張圖片區
  - 開啟詳細頁時帶入一份「可翻頁的 id 清單」（`ShotGridScreen`、`SearchScreen` 兩個入口）
  - header、infoBar、selectionPanel、sheet 目標跟著目前頁更新
  - 文字選取模式下停用翻頁；翻頁時清除選取狀態
  - 目前這張在詳細頁開著時被刪除（Photos 端刪除）：改成跳到相鄰頁，沒有剩下的頁才關閉
  - 左邊緣返回手勢和水平分頁不互相干擾
- **Out of scope**
  - 頁碼指示（例如「3 / 24」）、縮圖列
  - 雙指縮放／拖曳圖片（zoom）
  - 預先載入全解析度圖片（相鄰頁由 LazyHStack 自然建立，只載入 fit 尺寸）
  - 下滑關閉詳細頁

## 決策紀錄

| # | 決策 | 選擇 | 理由 / 被放棄的選項 |
|---|------|------|------|
| D1 | 翻頁範圍 | 開啟時的來源清單（grid 的 scope、搜尋結果） | 和使用者剛才看到的順序一致。放棄「永遠翻全部截圖」：從資料夾點進來卻翻到別的資料夾的圖，會讓人搞不清楚在哪 — 預設值（可推翻） |
| D2 | 清單是快照還是即時 | 開啟時拍快照，渲染時濾掉已刪除的 id | 在詳細頁把圖移到別的資料夾後，即時清單會讓目前這頁從 folder scope 消失、畫面跳走。快照讓「移走後還能繼續翻」 — 預設值 |
| D3 | 分頁元件 | `ScrollView(.horizontal)` + `LazyHStack` + `.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)` | 部署目標 iOS 26，API 都有；能用 `.scrollDisabled` 控制、目前頁 id 可雙向綁定。放棄 `TabView(.page)`：跟著 selection 換頁時常會重建頁面，左邊緣手勢也較難處理 |
| D4 | 目前頁的狀態放哪 | `UIState.detail: DetailSession?`（ids + currentID） | `sheetTargets` 已經靠 `detailID` 決定 sheet 的作用對象，目前頁本來就是共享導航狀態，留在 `UIState` |
| D5 | 選取模式與翻頁 | 選取中 `.scrollDisabled(true)`；`currentID` 改變時清空 `selecting` / `selected` | 選取狀態是針對單張圖的 text block id，帶到下一張沒有意義 |
| D6 | `expanded`（資訊列展開） | 翻頁時保留 | 使用者展開來看 metadata，翻頁時多半想繼續看下一張的 — 預設值 |
| D7 | 左邊緣返回 | 在左側 24pt 疊一條透明的 hit area，用 `.highPriorityGesture` 接 edge-swipe | 目前用 `.simultaneousGesture`，加上水平 ScrollView 後同一次拖曳會同時翻到上一頁又觸發返回。用一條獨立 hit area 讓分頁收不到這段拖曳 |
| D8 | 目前這張被刪除 | 移到同位置的下一張，沒有下一張就前一張，全部不見才 `closeDetail()` | 比原本直接關閉更符合翻頁情境 |

## 現況分析

- **詳細頁**：`Views/Detail/ShotDetailScreen.swift` 只接受單一 `shotID`，`header`、`imageArea`、`selectionPanel`、`infoBar` 都是吃 `Shot` 的 private func — 拆成「容器 + 單頁」時，`header` / `selectionPanel` / `infoBar` 留在容器，`imageArea`（含 `fittedSize`、`TextBlockOverlay`、`recognitionButton`）移到單頁 view。
- **開啟入口**：
  - `Views/Library/ShotGridScreen.swift:145` `ui.openDetail(shot.id)`；`body` 裡已經算好 `ids`（第 47 行），可以直接傳。
  - `Views/Library/SearchScreen.swift:51` `ui.openDetail(shot.id)`；`hits.map(\.shotID)` 就是清單。
- **導航狀態**：`Store/UIState.swift` 的 `detailID`、`openDetail`、`closeDetail`、`sheetTargets`（`.detail` 時回傳 `[detailID]`）。
- **掛載點**：`Views/Shell/AppShell.swift:41-46` 用 `.id(id)` 掛 `ShotDetailScreen`。**翻頁後這個 `.id` 會讓整個畫面重建、ScrollView 位置重置，必須改**。
- **Sheet**：`Views/Shell/Sheets.swift` 只透過 `ui.sheetTargets` / `ui.sheetContext` 取得目標，只要 `sheetTargets` 回傳目前頁就不必改。
- **可重用**：`AssetImage`（已會用 `PhotoLibraryService` 的 NSCache 先畫出縮圖，相鄰頁出現時不會是灰色框）、`LibraryStore.prioritize(_:)`、`Library.shot(_:)`。
- **測試**：App target 沒有 test target；`ScreenshotKit` 有 `Tests/ScreenshotKitTests`。

## 架構設計

```
AppShell
  └─ ShotDetailScreen (容器：header / pager / selectionPanel|infoBar / edge swipe)
       ├─ reads  UIState.detail (DetailSession: ids, currentID)
       ├─ reads  LibraryStore.library
       └─ ShotPage × N  (LazyHStack 內每頁：fit 圖片 + TextBlockOverlay + recognitionButton)

DetailSession (pure value, Store/)
  - visibleIDs(in: Library) / replacingMissingCurrent(in:) / moving(to:)
```

- **`DetailSession`**：純值型別，只管「有哪些頁、目前在哪一頁、目前這頁不見時要去哪」。沒有 I/O，沒有動畫。
- **`UIState`**：持有 `detail: DetailSession?`，提供 `openDetail(_:in:)`、`showDetailPage(_:)`、`closeDetail()`；`detailID` 改為 computed `detail?.currentID`，`sheetTargets` 不動。
- **`ShotDetailScreen`**：容器。持有選取／展開等暫時狀態、edge-swipe offset；把 `ScrollView` 的 `scrollPosition` 綁到 `ui.detail.currentID`；`.task(id: currentID)` 做 `store.prioritize`；`.onChange(of: currentID)` 清選取。
- **`ShotPage`**：單頁呈現，只吃 `Shot`、`selecting`、`selected` 和 toggle callback；不碰 `UIState` / `LibraryStore`。

### 替代方案

| 方案 | 優點 | 缺點 | 結論 |
|------|------|------|------|
| A. ScrollView paging（推薦） | 可停用捲動、`scrollPosition(id:)` 雙向綁定、Lazy 載入 | 需要自己處理左邊緣手勢 | 採用 |
| B. `TabView` `.page` style | 寫法最短 | selection 改變時易重建頁面；選取模式要停用滑動較麻煩；邊緣手勢一樣衝突 | 不採用 |

## 檔案變更清單

| 動作 | 檔案 | 層 | 職責 |
|------|------|----|------|
| 新增 | `albumOrganizer/ScreenshotOrganizer/Store/DetailSession.swift` | State（pure） | 翻頁清單與目前頁的純值邏輯 |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Store/UIState.swift` | State | `detailID` → `detail: DetailSession?`；`openDetail(_:in:)`、`showDetailPage(_:)` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Detail/ShotDetailScreen.swift` | UI | 拆成容器 + pager；edge swipe 改成獨立 hit area；刪除處理改呼叫 `DetailSession` |
| 新增 | `albumOrganizer/ScreenshotOrganizer/Views/Detail/ShotPage.swift` | UI | 單頁圖片、`TextBlockOverlay`、`recognitionButton`（從 ShotDetailScreen 搬出） |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Shell/AppShell.swift` | UI | 掛載條件改 `ui.detail != nil`，拿掉 `.id(id)` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Library/ShotGridScreen.swift` | UI | `ui.openDetail(shot.id, in: ids)` |
| 修改 | `albumOrganizer/ScreenshotOrganizer/Views/Library/SearchScreen.swift` | UI | `ui.openDetail(shot.id, in: hits.map(\.shotID))` |
| 修改 | `albumOrganizer.xcodeproj/project.pbxproj` | Build | 若專案不是 folder-synced group，加入兩個新檔 |

## 介面草案

```swift
/// The screenshots the detail page can page through, and which one is showing.
/// A snapshot taken when the page opens, so moving the current shot elsewhere doesn't yank it away.
struct DetailSession: Equatable {
    private(set) var ids: [String]
    private(set) var currentID: String

    /// `ids` must contain `currentID`; if it doesn't, the session is just that one shot.
    init(currentID: String, ids: [String])

    /// `ids` minus the ones no longer in the library, in order.
    func visibleIDs(in library: Library) -> [String]

    /// Same session pointed at `id`; ignores ids that aren't in the session.
    func moving(to id: String) -> DetailSession

    /// When the current shot is gone from `library`: the session on its next neighbour,
    /// else the previous one, else `nil` (nothing left to show).
    func replacingMissingCurrent(in library: Library) -> DetailSession?
}
```

```swift
// UIState
private(set) var detail: DetailSession?
var detailID: String? { detail?.currentID }

func openDetail(_ id: String, in ids: [String])   // with pushAnimation
func showDetailPage(_ id: String)                 // no animation; driven by the pager
func closeDetail()                                // unchanged behaviour
```

```swift
// ShotDetailScreen (container)
struct ShotDetailScreen: View {
    @Environment(LibraryStore.self) private var store
    @Environment(UIState.self) private var ui

    @State private var selecting = false
    @State private var selected: Set<Int> = []
    @State private var expanded = false
    @State private var dragOffset: CGFloat = 0

    // body: header(current) / pager / selectionPanel|infoBar
    // pager: ScrollView(.horizontal) { LazyHStack(spacing: 0) { ForEach(visibleIDs) { ShotPage(...).containerRelativeFrame(.horizontal) } }.scrollTargetLayout() }
    //        .scrollTargetBehavior(.paging)
    //        .scrollPosition(id: <binding to ui.detail.currentID via showDetailPage>)
    //        .scrollDisabled(selecting)
    //        .scrollIndicators(.hidden)
    // .overlay(alignment: .leading) { edgeSwipeStrip }   // 24pt, highPriorityGesture(edgeSwipe)
    // .task(id: ui.detailID) { store.prioritize(id) }
    // .onChange(of: ui.detailID) { selecting = false; selected = [] }
    // .onChange(of: store.library) { handle missing current via replacingMissingCurrent }
}

// ShotPage
struct ShotPage: View {
    let shot: Shot
    let selecting: Bool
    let selected: Set<Int>
    let onToggleSelecting: () -> Void
    let onToggleBlock: (Int) -> Void
}
```

## 規則檢核（pre-review）

| 規則 | 設計對策 | 殘留風險 |
|------|----------|----------|
| 1. 框架慣例 | 照現有寫法：導航狀態在 `@Observable UIState`、畫面取 `@Environment`；詳細頁相關 view 都放 `Views/Detail/`；分頁用 iOS 17+ 原生 `scrollTargetBehavior(.paging)` / `scrollPosition(id:)`，不引入第三方 | 無 |
| 2. 架構可擴充性 | 入口只需要傳一份 `[String]`，之後新增入口（例如 TagsScreen 直接開圖）一行就能接；頁碼指示、zoom 之後只會動 `ShotPage` 或容器的 header，不必改 `DetailSession`。不另做 protocol 抽象 | 無 |
| 3. 副作用 / Pure Function | 「濾掉已刪除」「目前頁不見時跳哪」都放在 `DetailSession` 的純函式；`UIState` 只做賦值與動畫；`prioritize` I/O 集中在 `.task(id:)` | App target 沒有 test target，`DetailSession` 暫時無法寫 unit test（見風險） |
| 4. 重複程式碼 | 重用 `AssetImage`、`fittedSize`、`TextBlockOverlay`（直接搬到 `ShotPage.swift`，不複製）；header / infoBar / selectionPanel 只在容器有一份 | 無 |
| 5. 命名 | `DetailSession`（一次開啟詳細頁的翻頁範圍）、`ShotPage`（pager 的一頁）、`openDetail(_:in:)`、`showDetailPage(_:)`、`visibleIDs(in:)`、`replacingMissingCurrent(in:)`；`detailID` 名稱保留，Sheets 不必改 | 無 |
| 6. 巢狀與複雜度 | `ShotDetailScreen.body` 只組合 `header` / `pager` / bottom bar；pager 與 edge strip 各自是 computed property；刪除後的跳頁分支放在 `DetailSession`（一個 `firstIndex` + 兩個 guard） | 無 |
| 7. SOLID | S：`DetailSession` 管翻頁範圍、`UIState` 管導航與動畫、容器管工具列與暫時狀態、`ShotPage` 只畫一頁。O：新入口只加呼叫端。I：`ShotPage` 只拿需要的值與 callback，不依賴 environment。D：`ShotPage` 不碰全域狀態；容器沿用 `@Environment` 注入 | 無 |

## 實作步驟

1. **`DetailSession`** — 新增 `Store/DetailSession.swift`；驗證：Xcode build。
2. **`UIState` 換成 session** — `detail`、computed `detailID`、`openDetail(_:in:)`、`showDetailPage(_:)`；同步改 `ShotGridScreen`、`SearchScreen` 的呼叫端、`AppShell` 的掛載（拿掉 `.id(id)`）。此時詳細頁仍是單張，行為不變；驗證：build、點 grid／搜尋都能開詳細頁、sheet 作用在正確的圖。
3. **抽出 `ShotPage`** — 把 `imageArea`、`fittedSize`、`recognitionButton`、`recognitionLabel`、`TextBlockOverlay` 搬到 `Views/Detail/ShotPage.swift`；容器暫時只放一頁；驗證：build、文字選取／複製正常。
4. **加上 pager** — `ScrollView` + `LazyHStack` + paging + `scrollPosition`，`.scrollDisabled(selecting)`，`.onChange(of: ui.detailID)` 清選取，`.task(id: ui.detailID)` prioritize；驗證：在模擬器左右滑動、header／資料夾／標籤跟著換、從資料夾開啟只在該資料夾內翻。
5. **左邊緣返回** — edge strip + `highPriorityGesture`，拿掉原本的 `.simultaneousGesture`；驗證：左邊緣拉動能返回，不會同時翻到上一頁；從畫面中間往右滑只翻頁。
6. **刪除處理** — 原本 `else { ... closeDetail() }` 改成 `replacingMissingCurrent`；驗證：開著詳細頁時從 Photos 刪掉目前這張，會跳到下一張。
7. **收尾** — `swift-format-runner`、`swift-code-review`。

## 測試計畫

- `DetailSession`（純函式，若加 test target 或決定搬進 package）：
  - `init` 時 `ids` 不含 `currentID` → 只剩那一張
  - `visibleIDs` 濾掉已刪除的 id、保持順序
  - `moving(to:)` 不在清單內的 id 會被忽略
  - `replacingMissingCurrent`：中間被刪 → 下一張；最後一張被刪 → 前一張；全部被刪 → `nil`；目前頁還在 → 原樣回傳
- 手動（模擬器）：
  - 所有截圖／chip／資料夾／標籤／搜尋 五個入口各自的翻頁範圍
  - 翻頁後開「移到資料夾」「標籤」sheet，作用在目前頁
  - 在資料夾內把目前這張移出 → 頁面留著、可繼續翻（D2）
  - 選取模式下不能翻頁；結束選取後可翻
  - 左邊緣返回、push 動畫時第一頁有縮圖（`AssetImage` cache）
  - VoiceOver：三指左右滑能翻頁

## 風險與未決問題

- ⚠️ **App target 沒有 test target**，`DetailSession` 的純邏輯無法用 XCTest 覆蓋（規則 3）。處理方式二擇一：(a) 新增 app unit test target；(b) 接受只做手動測試。`DetailSession` 依賴 `Library`，若要放進 `ScreenshotKit` 測試，等於把畫面導航邏輯放進 domain package，不建議。
- ⚠️ `scrollPosition(id:)` 在 push 動畫期間的初始定位：首次出現時需確保直接定在 `currentID`，不要從第 0 頁捲過去。實作第 4 步要在模擬器上確認，必要時用 `.defaultScrollAnchor` 或在 `onAppear` 設定初始位置（不帶動畫）。
- ⚠️ 清單很大（上千張）時 `ForEach` 的 id 陣列成本：`LazyHStack` 只建立可見頁，`visibleIDs` 每次 library 變動是 O(n) 查詢 —— 若 `Library.shot(_:)` 是線性搜尋，會變成 O(n²)。實作時改用 `Set(library.shots.map(\.id))` 一次查完。
- ❓ 要不要在 header 顯示頁碼（「3 / 24」）？目前列為 out of scope。

## 修訂紀錄

| 版本 | 日期 | 變更 |
|------|------|------|
| v1 | 2026-10-08 | 初版 |
| v2 | 2026-10-08 | 使用者確認：只做手動測試、不加頁碼。實作時調整：`visibleIDs(in:)` 改成 `visibleShots(in:)`（一次建 dictionary，避免 O(n²)）；`recognitionButton` 留在容器、疊在 pager 上，不放進 `ShotPage`（避免被左邊緣手勢區域蓋住，也不會跟著頁面滑走）；`UIState` 新增 `replaceMissingDetail(in:)` |
