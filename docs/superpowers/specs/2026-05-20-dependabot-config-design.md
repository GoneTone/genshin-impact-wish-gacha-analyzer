# Dependabot 設定

## 目的

替 repo 啟用 GitHub Dependabot 自動相依套件升級 PR，覆蓋 Flutter (`pub`) 與 Rust (`cargo`) 兩個 ecosystem，並降低 PR 噪音、避開會破 build 的危險升級。

## 範圍

只建立 `.github/dependabot.yml` 一個檔案。不動 workflows、不動套件本身。

## 設計

### 監看的 ecosystem

| ecosystem | directory | 目標 manifest |
|---|---|---|
| `pub` | `/` | `pubspec.yaml` |
| `cargo` | `/rust` | `Cargo.toml` |

**不納入**：

- `github-actions`：`.github/workflows/` 不存在，沒可掃對象。將來加 workflow 時再補。
- `rust_builder/pubspec.yaml`、`build/**/pubspec.yaml`：cargokit / flutter build artifact，不該被 dependabot 動到。dependabot 預設只看設定中指定的 directory，不會誤觸。

### 排程

- `interval: weekly`
- `day: monday`
- `time: "09:00"`
- `timezone: "Asia/Taipei"`

理由：每日太吵；每月太慢（會錯過 security patch）；週一早上正好對齊新的開發週。

### 分組策略

每個 ecosystem 各一組 `dependencies`，**把所有 minor + patch 合併成單一 PR**：

```yaml
groups:
  dependencies:
    update-types:
      - "minor"
      - "patch"
```

**major** 不放進 group → dependabot 自動拆成個別 PR，讓 breaking change 顯眼、好獨立 review。

### Ignore 清單

`flutter_rust_bridge` 在 `pub` 與 `cargo` 兩邊都 ignore（含所有升級類型）。

**Why**：`pubspec.yaml` 寫 `^2.12.0`、`rust/Cargo.toml` 寫 `=2.12.0`，兩邊必須同版才能 build。Dependabot 各 ecosystem 獨立 bump，必然破壞同步。手動協調升級。

```yaml
ignore:
  - dependency-name: "flutter_rust_bridge"
```

### Commit message 對齊現有風格

```yaml
commit-message:
  prefix: "chore(deps)"
  prefix-development: "chore(deps-dev)"
  include: "scope"
```

產生的 commit 會長成 `chore(deps): bump foo from 1.2.3 to 1.2.4`，符合既有 `chore(comments):`、`chore(lint):` 的 conventional commits 風格。

### Target branch

不設 `target-branch` → 跟隨 GitHub repo 的 default branch。

（目前 default branch 是 `master`；活躍開發在 `flutter-rewrite`，但這個由使用者決定 Dependabot 該打哪。將 PR 開向 default branch 是 Dependabot 的標準假設。）

### PR 上限

`open-pull-requests-limit: 30`（每 ecosystem）。預設 5 太緊，30 給長假累積空間。

## 完整檔案內容

```yaml
version: 2
updates:
  - package-ecosystem: "pub"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
      timezone: "Asia/Taipei"
    open-pull-requests-limit: 30
    commit-message:
      prefix: "chore(deps)"
      prefix-development: "chore(deps-dev)"
      include: "scope"
    groups:
      dependencies:
        update-types:
          - "minor"
          - "patch"
    ignore:
      - dependency-name: "flutter_rust_bridge"

  - package-ecosystem: "cargo"
    directory: "/rust"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
      timezone: "Asia/Taipei"
    open-pull-requests-limit: 30
    commit-message:
      prefix: "chore(deps)"
      prefix-development: "chore(deps-dev)"
      include: "scope"
    groups:
      dependencies:
        update-types:
          - "minor"
          - "patch"
    ignore:
      - dependency-name: "flutter_rust_bridge"
```

## 驗收條件

1. `.github/dependabot.yml` 存在且通過 GitHub 的設定 lint（push 後在 repo Insights → Dependency graph → Dependabot 不出現 parse error）
2. 第一次排程後（或手動觸發 "Check for updates"）能看到兩個 ecosystem 各自的 PR / 報告
3. 升 `flutter_rust_bridge` 的 PR 不應該出現

## 後續維護備忘（不在此 spec 範圍）

- 之後新增 `.github/workflows/*.yml` 時補上 `github-actions` ecosystem
- `flutter_rust_bridge` 升級需手動同步 `pubspec.yaml` 與 `rust/Cargo.toml`
- `flutter-rewrite` merge 回 `master` 後不需要動這份設定（target 跟 default branch 走）
