# Dependabot GitHub Actions Ecosystem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `.github/dependabot.yml` 加入 `github-actions` ecosystem entry，讓 Dependabot 接管 `.github/workflows/` 內 actions 的版本升級 PR。

**Architecture:** 純設定檔變更。於現有 `.github/dependabot.yml` 的 `updates:` 列表末尾追加第三個 ecosystem entry，欄位（schedule / commit-message / groups / open-pull-requests-limit）與既有 `pub` / `cargo` entry 完全對齊，以維持週期、提交訊息、PR 分組行為一致。

**Tech Stack:** GitHub Dependabot v2 config（YAML）。

**Spec:** `docs/superpowers/specs/2026-05-27-dependabot-github-actions-design.md`

**TDD note:** 本任務只動 yaml 設定，沒有 unit/integration test target，不套用「先寫紅測再實作」流程。改用驗證式檢查：(a) yaml 語法可 parse；(b) 行為驗證在 GitHub UI 的 Dependabot tab 觀察（commit 後 1~2 分鐘內可見）。

---

## File Structure

- **Modify:** `.github/dependabot.yml` — 在現有 `updates:` 列表（含 `pub`、`cargo` 兩個 entry）末尾追加 `github-actions` entry。

不新建任何檔案。不動 workflows、不動 actions 版本。

---

## Task 1: 加入 github-actions ecosystem entry

**Files:**
- Modify: `.github/dependabot.yml`（在現有檔尾追加一個 entry，現檔 42 行）

- [ ] **Step 1：讀現有 `.github/dependabot.yml` 確認尾端格式**

Run:
```powershell
Get-Content .github/dependabot.yml -Tail 5
```

Expected output（末尾應為 `cargo` ecosystem 的 `ignore` 區塊）:
```yaml
        update-types:
          - "minor"
          - "patch"
    ignore:
      - dependency-name: "flutter_rust_bridge"
```

確認檔案結尾沒有空行、沒有額外空白，行尾為 LF（與既有 entry 風格一致）。

- [ ] **Step 2：在檔尾追加 github-actions entry**

使用 Edit 工具在 `.github/dependabot.yml` 的 `flutter_rust_bridge` 結尾 ignore 區塊之後追加（注意：新 entry 與既有 entry 之間保留一個空行，且不加 `ignore` 區塊）：

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

要點：
- `directory: "/"` 不是 `/.github/workflows`。GitHub Actions ecosystem 慣例就是 repo root，Dependabot 會自動掃 `.github/workflows/*.yml`。
- 不加 `ignore` 區塊（與 pub/cargo 不同；actions 沒有要鎖定的對象）。
- 縮排 2 spaces 與既有 entry 對齊（YAML 對縮排敏感）。

- [ ] **Step 3：驗證 yaml 語法可 parse**

Run:
```powershell
python -c "import yaml; yaml.safe_load(open('.github/dependabot.yml', encoding='utf-8'))"
```

Expected: 無輸出、exit code 0。

如果環境沒有 Python，改用：
```powershell
flutter pub global activate yaml 2>$null; dart -e "import 'dart:io'; import 'package:yaml/yaml.dart'; void main() { final c = File('.github/dependabot.yml').readAsStringSync(); loadYaml(c); print('OK'); }"
```

或最簡：用 GitHub 的 web UI 在 push 後檢查 Dependabot tab（這個在 Step 6 做）。

- [ ] **Step 4：跑 git diff 確認 diff 乾淨**

Run:
```powershell
git diff .github/dependabot.yml
```

Expected：純粹 addition，僅在檔尾新增一個 entry 區塊。不該有任何既有行被修改、刪除、重新縮排。若 diff 顯示既有行有 whitespace 變動，回去調整縮排或行尾。

- [ ] **Step 5：確認三個 ecosystem 都存在**

Run:
```powershell
Select-String -Path .github/dependabot.yml -Pattern 'package-ecosystem'
```

Expected：恰好 3 行，依序為 `pub`、`cargo`、`github-actions`。

- [ ] **Step 6：commit**

Run:
```powershell
git add .github/dependabot.yml
git commit -m "chore(deps): track GitHub Actions versions via Dependabot"
```

Expected：commit 成功。push 到 master 後 `ci.yml` 會被觸發（format / analyze / test），由於本變更只動設定檔，不影響 Dart 程式碼，CI 應全綠。

**注意：不要主動 git push。** 本 repo CLAUDE.md 明確規定不主動 push，由使用者自行決定何時 push。

- [ ] **Step 7：（push 後）GitHub UI 行為驗證**

使用者 push 後 1~2 分鐘內，至 GitHub repo → Insights → Dependency graph → Dependabot tab 確認：

Expected：
- 看到 3 個 ecosystem entry：`pub` / `cargo` / `github-actions`。
- `github-actions` 顯示為 "Last checked: <剛剛>"，且無 "Error parsing config" 警告。
- 若已有可升級的 action，下一個週一 09:00 Asia/Taipei 會看到 PR；可以手動於該頁面點「Check for updates」立即觸發第一次掃描。

如 GitHub UI 顯示 parse error，回 Step 2 檢查縮排與引號。

---

## Success Criteria（對應 spec 驗收標準）

1. ✅ `.github/dependabot.yml` 含三個 ecosystem entry：`pub` / `cargo` / `github-actions`（Step 5 驗證）。
2. ✅ 新 entry 的 schedule、commit-message、groups、open-pull-requests-limit 與 `pub` / `cargo` 完全對齊（依 Step 2 模板直接複製對齊欄位）。
3. ✅ yaml 語法正確（Step 3 本機驗證 + Step 7 GitHub UI 驗證）。

---

## Out of Scope（spec「不做」清單）

- 不升級任何 action 到新版（升級交由後續 Dependabot PR）。
- 不改 workflow 邏輯。
- 不把 `dtolnay/rust-toolchain@stable` pin 到 SHA。
- 不為 actions 設定 reviewer / assignee。
- 不主動 git push。
