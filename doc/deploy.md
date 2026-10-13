# 部署（TestFlight）

App 名稱為 **Scapio**（`INFOPLIST_KEY_CFBundleDisplayName`），bundle id `com.chiawei.albumOrganizer`，Team ID `7RMCG6LBC4`。目前只發佈到 TestFlight。

| 項目 | 內容 |
|------|------|
| 簽章 | fastlane `match`，憑證與 profile 加密後放在 `git@github.com:Ja7423/app-certificates.git` 的 `albumOrganizer` branch |
| 編譯 | fastlane `gym`，輸出 `build/albumOrganizer.ipa` |
| 上傳 | [asc CLI](https://github.com/rorkai/App-Store-Connect-CLI)（`asc builds upload`），不是 fastlane 的 `pilot` |
| 驗證 | App Store Connect API Key（不需要 Apple ID 帳密、不會遇到 2FA），fastlane 與 asc 共用 |
| 指令入口 | `Makefile`（全部透過 `bundle exec fastlane ios <lane>`，版本鎖在 `Gemfile.lock`） |
| CI | `.github/workflows/testflight.yml`：push 到 `beta` branch 自動上傳，成功後打 tag |
| 文件更新日期 | 2026-10-13（對應 `feature/deploy-flow`） |

---

## 1. 整體流程

```
             ┌─────────── 本機：make beta ───────────┐      ┌──── CI：push 到 beta branch ────┐
             │                                       │      │  （或 Actions 頁面手動執行）        │
             └───────────────────┬───────────────────┘      └────────────────┬────────────────┘
                                 ▼                                           ▼
                     fastlane ios beta ◀─────────────────────────────────────┘
                       ├─ asc_api_key            載入 App Store Connect API Key
                       ├─ match(appstore, 唯讀)   從 cert repo 下載 Apple Distribution 憑證與 profile
                       ├─ build number           有指定就用；沒指定則 asc builds next-build-number 查下一號
                       ├─ gym                    Release、app-store 匯出 → build/albumOrganizer.ipa
                       ├─ asc builds upload      上傳到 App Store Connect（預設只等 60 秒驗證）
                       └─ 寫 GITHUB_OUTPUT        version / build_number（只在 CI）
                                 │
                                 ▼（只在 CI）
                       git tag beta/<版本號>-<build number> 並 push
                       上傳 ipa 與 dSYM 為 Actions artifact（保留 14 天）
```

版本號（`MARKETING_VERSION`）寫在 `project.pbxproj`，要手動用 `make version` 改並 commit；build number 不寫回專案，只在編譯時用 `CURRENT_PROJECT_VERSION=<n>` 覆蓋，所以專案裡的 `CURRENT_PROJECT_VERSION` 一直是 1。

---

## 2. 第一次設定（本機）

```bash
make install
```

1. Ruby 版本見 `.ruby-version`（3.3），`make install` 會用 bundler 裝 `Gemfile.lock` 裡的 fastlane。
2. 安裝 asc：`brew install asc`。
3. 從範本建立 `fastlane/.env`（已在 `.gitignore`）並填值。fastlane 執行時會自動載入，asc 由 fastlane 呼叫所以也拿得到：

```bash
cp fastlane/.env.example fastlane/.env
```


| 變數 | 說明 |
|------|------|
| `ASC_KEY_ID` | App Store Connect API Key ID（App Store Connect → 使用者與存取權限 → 整合 → App Store Connect API）。權限需要「App 管理」以上，match 才能建立憑證與 profile |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_PRIVATE_KEY_PATH` | 本機用：`.p8` 檔路徑（`*.p8` 已在 `.gitignore`） |
| `ASC_PRIVATE_KEY_B64` | CI 用：`base64 -i AuthKey_XXX.p8` 的輸出。兩者擇一，`ASC_PRIVATE_KEY_PATH` 優先 |
| `MATCH_PASSWORD` | match 加密 cert repo 的密碼 |

4. 下載憑證與 profile（唯讀，不會改動 cert repo）：

```bash
make certs-fetch
```

本機需要能用 SSH 讀 `Ja7423/app-certificates`。

### 2.1 專案的簽章設定

App target 是 **Manual signing**，只對 `iphoneos` SDK 指定 match 的 profile：

| Configuration | Identity | Profile |
|------|------|------|
| Debug | iPhone Developer | `match Development com.chiawei.albumOrganizer` |
| Release | iPhone Distribution | `match AppStore com.chiawei.albumOrganizer` |

所以在 Xcode 跑實機前要先 `make certs`。`build_appstore` 編譯期間會再用 `update_code_signing_settings` 把 Release 設成 match 的 profile，結束後還原 `project.pbxproj`（不會留下 diff，也不會蓋掉尚未 commit 的修改）。

---

## 3. 指令

全部在 repo 根目錄執行，`make` 或 `make help` 列出所有指令。

| 指令 | 對應 lane | 用途 |
|------|------|------|
| `make install` | — | `bundle install` |
| `make version VERSION=1.0.1:12` | `set_version` | 改所有 target 的 `MARKETING_VERSION`（與 `CURRENT_PROJECT_VERSION`，可省略 `:12`），直接改 `project.pbxproj` 文字 |
| `make certs` | `certs` | 下載 development 憑證與 profile（唯讀） |
| `make certs-appstore` | `certs_appstore` | 下載 appstore 憑證與 profile（唯讀） |
| `make certs-fetch` | `certs` + `certs_appstore` | 兩者都下載 |
| `make certs-init` | `certs_init` | 建立憑證與 profile 並推到 cert repo；新增測試裝置、憑證過期時也用這個 |
| `make build [BUILD_NUMBER=42]` | `build_appstore` | 只編譯 ipa 到 `build/` |
| `make beta [BUILD_NUMBER=42] [WAIT=true]` | `beta` | 編譯並上傳到 TestFlight |
| `make upload [IPA=path] [WAIT=true]` | `upload` | 只上傳已編譯好的 ipa（預設 `build/albumOrganizer.ipa`） |
| `make lanes` | — | 列出 Fastfile 所有 lane |

- `BUILD_NUMBER` 沒給時向 App Store Connect 查下一號（包含處理中的上傳），一般不需要指定。
- `WAIT=true` 會等 Apple 處理完才結束（`asc --wait`）；沒給則只等 60 秒的上傳驗證（`--verify-timeout 60s`），之後到 App Store Connect 看處理狀態。

---

## 4. 發一版 TestFlight

### 4.1 透過 CI（建議）

```bash
make version VERSION=0.0.2
git commit -am "Bump version to 0.0.2"
git push origin main
git push origin main:beta
```

1. 需要時先改版本號並 commit（同一個版本號可以上傳多個 build，只改程式就不用動）。
2. 把要發佈的 commit push 到 `beta` branch，就會觸發 `TestFlight` workflow。
3. 成功後 repo 會多一個 tag `beta/<版本號>-<build number>`，指向這次上傳的 commit；ipa 與 dSYM 在該次 run 的 artifact `albumOrganizer-ipa`。

也可以在 GitHub Actions 頁面手動執行 `TestFlight`，可填：

| 輸入 | 說明 |
|------|------|
| `build_number` | 留空則由 asc 查下一號 |
| `wait` | 等 App Store Connect 處理完成 |

同一時間只會跑一個 TestFlight job（`concurrency: testflight`，不取消進行中的）。

### 4.2 本機

```bash
make beta
```

本機上傳不會打 tag，也不會寫 `GITHUB_OUTPUT`；需要的話自己 `git tag beta/<版本號>-<build number>`。

---

## 5. CI 設定

Workflow：`.github/workflows/testflight.yml`

| 項目 | 內容 |
|------|------|
| 觸發 | `push` 到 `beta`、`workflow_dispatch` |
| Runner | `macos-26`，timeout 60 分鐘 |
| Xcode | 26.5（`maxim-lobanov/setup-xcode`） |
| Ruby | 3.3，`bundler-cache: true` |
| 權限 | `contents: write`（要 push tag） |
| 簽章 keychain | `before_all` 的 `setup_ci`：只在 `CI=true` 時建立暫存 keychain，並讓 match 用唯讀模式；本機不做事 |

步驟：checkout → 設定 Xcode → 載入 SSH deploy key（Matchfile 的 `git_url` 是 SSH）→ 裝 Ruby 與 gem → `brew install asc` → `make beta` → 打 tag 並 push → 上傳 artifact。

需要在 repo Settings → Secrets and variables → Actions 設定：

| Secret | 說明 |
|------|------|
| `ASC_KEY_ID` | 同本機 |
| `ASC_ISSUER_ID` | 同本機 |
| `ASC_PRIVATE_KEY_B64` | `base64 -i AuthKey_XXX.p8` 的輸出 |
| `MATCH_PASSWORD` | 與本機相同 |
| `MATCH_DEPLOY_KEY` | 能讀 `Ja7423/app-certificates` 的 SSH 私鑰；公鑰加到該 repo 的 Deploy keys（唯讀） |

---

## 6. 常見狀況

| 狀況 | 處理 |
|------|------|
| 新增測試裝置（development profile 要包含它） | 在 Developer Portal 註冊裝置後 `make certs-init`，其他機器再 `make certs` |
| 憑證或 profile 過期 | `make certs-init` 重新產生並推到 cert repo；CI 是唯讀，一定要在本機做 |
| CI 在 match 失敗 | 檢查 `MATCH_DEPLOY_KEY` 是否能讀 cert repo、`MATCH_PASSWORD` 是否正確 |
| 上傳後 TestFlight 還看不到 | Apple 還在處理；下次可加 `WAIT=true`，或到 App Store Connect 看狀態 |
| build number 衝突 | 不要指定 `BUILD_NUMBER`，讓 asc 查下一號 |
| 只想重傳同一個 ipa | `make upload`（或 `IPA=` 指定其他檔案） |

---

## 7. 相關檔案

| 檔案 | 內容 |
|------|------|
| `Makefile` | 指令捷徑 |
| `Gemfile` / `Gemfile.lock` / `.ruby-version` | fastlane 版本與 Ruby 3.3 |
| `fastlane/Appfile` | bundle id、Team ID |
| `fastlane/Matchfile` | cert repo 位置與 branch、storage mode |
| `fastlane/Fastfile` | 所有 lane（簽章、版本、編譯、上傳） |
| `fastlane/.env.example` | `.env` 的範本 |
| `fastlane/.env` | 本機的 API Key 與 match 密碼（不進版控） |
| `fastlane/README.md` | fastlane 自動產生的 lane 列表（不進版控） |
| `.github/workflows/testflight.yml` | CI |
