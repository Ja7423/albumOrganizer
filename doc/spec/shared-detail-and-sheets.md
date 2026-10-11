# Spec：共用元件（詳細頁、Sheet、對話框、批次列）

四個 tab 都會打開這些元件，所以規格寫在這裡，各 tab 的 spec 只寫「從哪裡、帶什麼參數」打開。

| 元件 | 檔案 | 掛載位置 |
|------|------|------|
| 詳細頁 | `Views/Detail/ShotDetailScreen.swift`、`ShotPage.swift` | `AppShell` 的 ZStack，zIndex 20，從右側滑入 |
| Sheet（移到資料夾／標籤） | `Views/Shell/Sheets.swift` → `SheetHost` | `AppShell`，zIndex 30，從下方滑入 |
| 命名對話框 | `Sheets.swift` → `NameDialog` | `AppShell`，zIndex 45，淡入 |
| 批次列 | `Views/Shell/AppShell.swift` → `BatchBar` | 選取模式時取代 TabBar |
| Toast | `AppShell.swift` → `ToastView` | `RootView`，zIndex 50 |
| 部分權限提示 | `Views/Common/LimitedAccessBanner.swift` | 截圖 tab（根 grid）、資料夾 tab |

---

## 1. 詳細頁（ShotDetailScreen）

### 1.1 開啟與關閉

- 開啟：`ui.openDetail(id, in: ids)`。`ids` 是來源畫面的順序（grid 的 scope、搜尋結果），會被拍成 `DetailSession` 快照。
  - `ids` 不含 `id` 時，session 只有這一張。
- 關閉：左上「返回」、或從圖片區左邊 24pt 往右拖（拖超過 110pt，或預測終點超過 240pt）。沒達到就彈回原位。
- 動畫：`UIState.pushAnimation`（0.34 秒 timing curve）。
- 打開時與每次翻頁時，`store.prioritize(id)` 把這張插到處理佇列最前面（只對處理中的截圖有效）。

### 1.2 版面（由上到下）

| 區塊 | 內容 |
|------|------|
| Header | 「‹ 返回」、分享按鈕 |
| 圖片區（pager） | 水平分頁 ScrollView，一頁一張，圖片 fit 進頁面並留 20pt 邊距；左下角浮著「辨識文字」按鈕 |
| 底部 | 非選取模式：資訊列；文字選取模式：選取面板 |

### 1.3 翻頁

- 範圍是 session 的 id 清單，渲染時濾掉已不在 library 的 id（`visibleShots(in:)`）。
- 快照的意義：在詳細頁把這張移到別的資料夾，它仍留在可翻頁清單裡，不會突然跳走。
- 翻頁會清掉文字選取狀態；資訊列的展開狀態保留。
- 文字選取模式下停用翻頁。
- 目前這張在開啟中被刪除（Photos 端刪除、同步後消失）：跳到清單裡的下一張，沒有就上一張，都沒有才關閉詳細頁。

### 1.4 分享

`ShareLink` 分享原圖（`ShotImage`），以 PNG 輸出：原檔是 PNG 直接用，否則轉檔。取不到原圖時拋錯，系統分享面板處理。

### 1.5 文字辨識按鈕與文字選取

按鈕狀態：

| 狀況 | 顯示 | 可按 |
|------|------|------|
| `recognition == .pending` | 轉圈 +「辨識文字中…」 | 否 |
| `.failed` | 「無法辨識文字」 | 否 |
| `.done` 但沒有文字 | 「沒有辨識到文字」 | 否 |
| `.done` 有文字 | 「選取圖中文字」 | 是 |
| 選取模式中 | 「結束選取」（primary 樣式） | 是 |

選取模式：

- 圖上每一行文字疊一個可點的框（未選 8% 透明 accent、已選 30%），點一下切換選取。
- 底部選取面板：「已選 N 段」＋提示「點圖上的區塊加入選取」、「全選／清除選取」、「複製已選」（N=0 時停用）。
- 複製時以換行串接，toast「已複製 N 段文字」。
- 結束選取時清空已選。

### 1.6 資訊列

| 元素 | 行為 |
|------|------|
| 資料夾按鈕 | 顯示資料夾名稱（處理中時顯示「處理中」）。自動分類且有來源時圖示為 ✦（sparkles），否則為資料夾圖示。點擊開「移到資料夾」sheet（detail context） |
| 標籤列（水平捲動） | 自動標籤（outline 樣式，依宣告順序）→ 我的標籤（`#tag`，accent 樣式）→「＋」開「標籤」sheet |
| 展開按鈕（⌃/⌄） | 展開後顯示下列 metadata 與「複製全部文字」 |

展開內容：

| 欄位 | 值 |
|------|------|
| 分類方式 | `處理中…` / `手動放入` / `自動分類 · 規則`（或 相似截圖、Apple Intelligence）/ `自動分類 · 無法判斷` |
| 截圖時間 | `y年M月d日 HH:mm` |
| 尺寸 | `寬 × 高`（像素） |
| 文字辨識 | `辨識中…` / `辨識失敗，稍後重試`（還能重試）/ `無法辨識` / `沒有文字` / `N 段 · 繁體中文 / 英文` |

「複製全部文字」：沒有文字時停用；toast「已複製全部文字（N 段）」。

---

## 2. 「移到資料夾」sheet

- 開啟：`ui.present(.move, for: .detail | .batch)`。作用對象由 `ui.sheetTargets` 決定（批次 = 已選的 id；詳細頁 = 目前這張）。
- 標題「移到資料夾」，副標：批次時「套用到 N 張截圖」，詳細頁時「一張截圖只會在一個資料夾」。右上「完成」關閉；點背景遮罩也會關閉。
- 列表：`未分類` → 所有資料夾（**儲存順序**，不是空的排最後）→「新增資料夾」。每列顯示目前張數。
- 詳細頁 context 時，目前所在資料夾打勾（處理中的截圖沒有任何一列打勾）。
- 點某列：`Library.move(ids, to:)`，**placement 改成 `.user` 鎖定**，關閉 sheet；批次時同時結束選取模式。toast：詳細頁「已移到「X」」、批次「N 張已移到「X」」。
- 「新增資料夾」：開命名對話框 `.newFolder(moveAfter: true)`，建立後直接把目標移進去（見 §4）。
- sheet 高度依內容自動調整，最高為畫面高度 72%，超過可捲動。

## 3. 「標籤」sheet

- 開啟：`ui.present(.tags, for: .detail | .batch)`。
- 副標：批次時「套用到 N 張截圖」，詳細頁時「可以加上多個標籤」。
- **自動偵測區（只有詳細頁 context 且這張有自動標籤時）**：標題「自動偵測 · 點一下移除」，每個自動標籤一個 ✕ chip。點擊 → `dismissFeatureTag`：從這張移除並記住，之後重新分類也不會再加回。toast「已移除「含連結」」。
- **所有標籤**：列出全部我的標籤。目標**全部**都有這個標籤時顯示為選中（✓ + accent）。點擊 → `toggleTag`：全部都有就從全部移除，否則加到全部。不顯示 toast。
- **建立新標籤**：輸入框 +「新增」。名稱會去掉前後空白與開頭的 `#`，空字串時停用按鈕。送出 → `addTag`：沒有就建立，並加到所有目標上；toast「已建立並加上 #X」。
- sheet 不會因為點選標籤而關閉。

## 4. 命名對話框（NameDialog）

| 種類 | 標題 | 確認鍵 | 送出後 |
|------|------|------|------|
| `.newFolder(moveAfter: false)` | 新增資料夾 | 建立 | `createFolder`；toast「已建立資料夾「X」」 |
| `.newFolder(moveAfter: true)` | 新增資料夾 | 建立 | 建立後把 `sheetTargets` 移進去、關 sheet、批次時結束選取；toast 同 §2 |
| `.renameFolder(id)` | 重新命名資料夾 | 儲存 | `renameFolder`；同名時保留對話框並 toast「已經有同名的資料夾」；成功 toast「已重新命名為「X」」 |
| `.newTag` | 新增標籤 | 建立 | `createTag`；toast「已建立 #X」 |

共同規則：

- 開啟時自動 focus；改名時預填目前名稱。
- 名稱去掉前後空白後為空時，確認鍵停用。
- 取消、或點背景遮罩關閉，不做任何修改。
- 新增資料夾時若已有同名資料夾，不會新建，而是回傳既有的那個（toast 一樣顯示「已建立」）。
- 新增標籤時若已存在，同樣不重複建立。

## 5. 批次列（BatchBar）

- 在 grid 按「選取」後，取代畫面底部的 TabBar。
- 按鈕：「移到資料夾」（開 §2 batch context）、「標籤」（開 §3 batch context）、垃圾桶「移除」。
- 一張都沒選時三個按鈕都停用。
- 「移除」：`Library.hide(ids)`，從 App 移除（加入 `hiddenShotIDs`，之後同步不會加回），Photos 原檔保留。**沒有確認步驟**。結束選取模式，toast「已從 App 移除 N 張（相簿原檔保留）」。

## 6. Toast

- `ui.showToast(message)`：畫面底部（距底 70pt）深色條，1.8 秒後淡出；新的 toast 會取代舊的並重新計時。
- 不攔截點擊。

## 7. 部分權限提示（LimitedAccessBanner）

- 只在 `store.isLimitedAccess`（使用者只允許部分照片）時顯示。
- 文案：「只整理你選取的截圖」＋說明。
- 「選取更多截圖」：開系統的有限照片選擇器；選完後 Photos 變更通知會觸發同步。
- 「前往設定」：開 App 的系統設定頁。
