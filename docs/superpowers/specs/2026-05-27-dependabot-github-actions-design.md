# Dependabot：新增 GitHub Actions Ecosystem

## 目的

替 repo 的 GitHub Actions workflows 啟用 Dependabot 自動相依升級 PR，把目前手動追蹤的 `actions/*`、`subosito/flutter-action`、`Swatinem/rust-cache` 等版本接管給 Dependabot。

## 背景

`2026-05-20-dependabot-config-design.md` 當初決議「`github-actions` 暫不納入，因為 `.github/workflows/` 不存在」。如今 repo 已加入兩支 workflow：

- `.github/workflows/ci.yml`（lint / analyze / test）
- `.github/workflows/release-windows.yml`（Windows 安裝檔 release）

該延遲決策的前提已消失，現在補上 ecosystem。

## 範圍

只動 `.github/dependabot.yml` 一個檔案，新增第三個 ecosystem entry。不動 workflows 本身、不動 actions 版本（升級交由 dependabot PR 之後再評估）。

## 設計

### Ecosystem 設定

於現有 `.github/dependabot.yml` 的 `updates:` 列表末尾追加：

```yaml
- package-ecosystem: "github-actions"
  directory: "/"
  schedule:
    interval: "weekly"
    day: "monday"
    time: "09:00"
    timezone: "Asia/Taipei"
  open-pull-requests-limit: 30
  commit-message:
    prefix: "chore"
    prefix-development: "chore"
    include: "scope"
  groups:
    dependencies:
      update-types:
        - "minor"
        - "patch"
```

### 與 pub/cargo 對齊的欄位

| 欄位 | 值 | 為何對齊 |
|---|---|---|
| `schedule` | weekly / Monday / 09:00 Asia/Taipei | 與其他 ecosystem 同步觸發，使用者只需週一處理一波 PR |
| `commit-message` | prefix=`chore`、include scope | 與既有 commit 風格、release-please/changelog 規則相容 |
| `groups.dependencies` | 合併 minor + patch | 降低 PR 噪音；major 升級各自獨立 PR 以便逐個審查 |
| `open-pull-requests-limit` | 30 | 一致即可；actions 實際同時開啟的 PR 應遠低於此 |

### `directory: "/"` 的意義

GitHub Actions ecosystem 的 `directory` 指 repo root；Dependabot 會自動掃 `.github/workflows/` 所有 yml 與 composite action 的 `action.yml`。不需要列出個別檔案。

### 不納入 `ignore`

與 `pub`（排除 `flutter_rust_bridge`）/ `cargo`（同名排除）不同，actions 目前沒有需要鎖定的對象。Floating tags（如 `dtolnay/rust-toolchain@stable`）Dependabot 不會主動送 PR，無需明文排除。

### Floating tag 行為

| Action | 寫法 | Dependabot 行為 |
|---|---|---|
| `actions/checkout@v4` | major tag | 出 `v5` 時送 PR |
| `actions/upload-artifact@v4` | major tag | 同上 |
| `subosito/flutter-action@v2` | major tag | 同上 |
| `Swatinem/rust-cache@v2` | major tag | 同上 |
| `dtolnay/rust-toolchain@stable` | rolling tag | 不送 PR（rolling pointer，無「升級」語意） |

設計上接受 `@stable` 不受 Dependabot 追蹤的現狀；如要追蹤需 pin 到 SHA，但成本高於收益（rust-toolchain action 本身就是 rolling release，pin SHA 會反過來讓我們落後於 Rust stable）。

## 預期影響

- **首次觸發**：下一個週一 09:00 (Asia/Taipei) Dependabot 掃描；若任何 action 有 minor/patch 升級 → 1 個 grouped PR；若有 major 升級 → 每個 major 各 1 個 PR。
- **CI 影響**：Dependabot PR 走既有 `ci.yml`，需通過 format / analyze / test 才能合併。release-windows 是 workflow_dispatch only，不受 PR 觸發。
- **預期 PR 數**：第一波最多約 5 個 PR（每個 action 一個 major + 1 個 grouped minor/patch），常態下大多週為 0~1 個 PR。

## 不做

- **不**升級任何 action 到較新版本（升級走後續 Dependabot PR 個別審查）。
- **不**改 workflow 邏輯。
- **不**把 `dtolnay/rust-toolchain@stable` pin 到 SHA。
- **不**為 actions 設定 reviewer / assignee（沿用 repo 既有 review 流程，不為 dependabot 加特殊路由）。

## 驗收標準

1. `.github/dependabot.yml` 含三個 ecosystem entry：`pub` / `cargo` / `github-actions`。
2. 新 entry 的 schedule、commit-message、groups、open-pull-requests-limit 與 `pub` / `cargo` 完全對齊。
3. yaml 語法正確（可以用 `yq` 或 GitHub 的 dependabot tab 驗證；GitHub 會在 commit 後 1~2 分鐘內於 Insights → Dependency graph → Dependabot 顯示是否成功 parse）。
