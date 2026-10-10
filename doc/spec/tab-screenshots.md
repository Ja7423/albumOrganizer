# Spec：「截圖」tab

| 項目 | 內容 |
|------|------|
| Tab 位置 | 第 1 個（預設 tab），圖示 `photo.on.rectangle`，標籤「截圖」 |
| 畫面 | `Views/Library/ShotGridScreen.swift`，`ShotGridScreen(route: nil)` |
| 導航 | 沒有 NavigationStack，只有一層 |
| 相關狀態 | `UIState.chip`、`UIState.selecting`、`UIState.selection` |
| 共用元件 | 詳細頁、批次列、sheet → [shared-detail-and-sheets.md](shared-detail-and-sheets.md) |

## 1. 目的

一次看到 App 裡所有截圖（最新在前），用 chip 快速縮小範圍，並且是批次整理（移資料夾、加標籤、移除）的主要入口。

## 2. 版面

```
┌──────────────────────────────┐
│ N 張                  [選取] │  ← ScreenHeader：kicker + 標題「所有截圖」+ 右側動作
│ 所有截圖                     │
│ ┌ 部分權限提示（有限存取時）┐ │
│ [全部][未分類][含連結]…[#x] │  ← 水平捲動的 chip 列
│ ┌──┐┌──┐┌──┐                 │
│ │  ││  ││  │                 │  ← 3 欄正方形 grid
│ └──┘└──┘└──┘                 │
├──────────────────────────────┤
│ 截圖 │ 資料夾 │ 標籤 │ 搜尋   │  ← TabBar（選取模式時換成 BatchBar）
└──────────────────────────────┘
```

### 2.1 Header

| 狀態 | Kicker | 右側動作 |
|------|------|------|
| 一般 | `N 張`（目前 chip 篩選後的張數） | 「選取」（secondary）；沒有截圖時停用 |
| 選取模式 | `已選 N 張` | 「全選」（ghost）＋「完成」（secondary） |

- 「全選」：目前範圍內的截圖**全部已選**時改成全部取消，否則全選目前範圍。
- 「完成」：結束選取模式並清空選取。

### 2.2 Chip 列

依序：

1. `全部` → `Scope.all`
2. `未分類` → `Scope.unsorted`（已處理完、沒有資料夾的截圖；不含處理中）
3. 自動標籤：只列出**至少一張截圖帶有**的，依宣告順序：含連結、QR code、含電話、含日期、含地址 → `Scope.feature`
4. 我的標籤：全部列出（即使 0 張），依建立順序，顯示為 `#名稱` → `Scope.tag`

行為：

- 目前 chip 以 accent 樣式顯示，其餘 neutral。
- 點 chip：切換 `ui.chip`，**並結束選取模式**。
- chip 選擇保存在 `UIState`，切到別的 tab 再回來仍保留（`selectTab` 不重設 chip）。App 重啟會回到「全部」。
- 在標籤 tab 刪除目前選中的標籤時，chip 會重設為「全部」。
- 資料夾與「處理中」不在 chip 列裡，要從資料夾 tab 進入。

### 2.3 Grid

- 3 欄、間距 `Space.s1`（4.6pt），每格正方形，縮圖以 aspect-fill **靠上對齊**（截圖上方通常是重點）。
- 縮圖要求 124×124pt × 螢幕倍率；先顯示 opportunistic 低畫質，再換成高畫質。
- 順序：`createdAt` 新到舊。
- VoiceOver：每格讀出 `shot.title`，選中時加上 selected trait。

### 2.4 點擊截圖

| 模式 | 行為 |
|------|------|
| 一般 | `ui.openDetail(id, in: 目前範圍的 id 清單)`：打開詳細頁，左右可翻目前 chip 範圍內的截圖 |
| 選取 | 切換這張的選取狀態 |

選取中的格子：選中時疊 14% accent 底色 + 3pt accent 邊框，右上角實心 ✓ 方塊；未選中時右上角是半透明空方塊。

### 2.5 下拉更新

- 在 grid 頂端往下拉會出現系統的更新指示器，呼叫 `store.refresh()`：在背景重新讀取 Photos 的螢幕截圖相簿，再與 Library 同步（新增新截圖、移除已從相簿刪除的截圖），並啟動處理佇列。
- 使用者在 App 內移除的截圖不會因下拉更新而加回。
- 資料夾、標籤推入的 grid（同一個 `ShotGridScreen`）也支援下拉更新。
- 平時 Photos 變動仍會由 change observer 自動同步；下拉更新是讓使用者主動確認的入口。

### 2.6 空狀態

| 條件 | 文案 |
|------|------|
| Library 完全沒有截圖，且仍在處理 | 「正在整理截圖…」 |
| Library 完全沒有截圖 | 「相簿裡還沒有螢幕截圖。截圖後會自動出現在這裡。」 |
| 有截圖但目前 chip 範圍是空的 | 「這裡還沒有截圖。到「截圖」選取後，用「移到資料夾」或「標籤」整理進來。」 |

## 3. 選取模式與批次操作

1. 按「選取」→ `ui.selecting = true`，選取清空，底部 TabBar 換成 BatchBar。
2. 點格子勾選，或按「全選」。
3. BatchBar：
   - 「移到資料夾」→ 移到資料夾 sheet（batch）→ 選資料夾後所有選取的截圖被移入並**鎖定為使用者放入**，結束選取。
   - 「標籤」→ 標籤 sheet（batch）→ 切換／新增標籤，sheet 關閉後**仍在選取模式**。
   - 垃圾桶 → 立即從 App 移除，結束選取。
4. 以下操作會結束選取模式：按「完成」、切換 chip、切換 tab、批次移動、批次移除。

詳細規則見 [shared-detail-and-sheets.md §2–§5](shared-detail-and-sheets.md)。

## 4. 資料來源

| 顯示 | 來源 |
|------|------|
| 截圖清單 | `store.library.shots(in: ui.chip)` |
| 自動標籤 chip | `library.presentFeatureTags` |
| 我的標籤 chip | `library.tags` |
| 空狀態判斷 | `library.shots.isEmpty`、`store.processingCount` |

Library 一有變動（同步新增、處理完成、移動、移除）畫面就會即時更新；處理中的截圖也會出現在「全部」裡。

## 5. 驗收清單

- [ ] 首次進入預設在此 tab、chip 為「全部」，截圖新到舊排列。
- [ ] 沒有任何截圖帶「含電話」時，不顯示「含電話」chip；有一張帶上後即出現。
- [ ] 新建 0 張的標籤，也會出現在 chip 列。
- [ ] 選「未分類」時不包含處理中的截圖。
- [ ] 點 chip 會結束選取模式；切 tab 後回來 chip 保留、選取模式已結束。
- [ ] 選取模式「全選」在已全選時改成全部取消。
- [ ] 從「#發票」chip 點進詳細頁，左右只能翻到帶 #發票 的截圖。
- [ ] 批次移除後 toast 顯示張數，Photos 相簿內原檔仍在，重新同步不會加回。
- [ ] 部分照片權限時顯示提示；完整權限時不顯示。
- [ ] 下拉 grid 會出現更新指示器，結束後新截圖出現、相簿已刪除的截圖消失；App 內移除過的截圖不會回來。
