# Dependabot 設定 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `.github/dependabot.yml`，啟用 GitHub Dependabot 監看 `pub` 與 `cargo` 兩個 ecosystem，並避開 `flutter_rust_bridge` 因雙邊版本綁定造成的破 build 風險。

**Architecture:** 純設定檔。內容直接照 spec 的「完整檔案內容」區塊寫入；不動任何 Dart / Rust 程式碼，不動 CI / workflows。

**Tech Stack:** GitHub Dependabot v2 schema (YAML)

**Spec reference:** `docs/superpowers/specs/2026-05-20-dependabot-config-design.md`

---

## File Structure

- **Create**: `.github/dependabot.yml`（唯一變更）

不動其他檔案。`.github/FUNDING.yml` 維持原樣。

---

## Task 1: 建立 .github/dependabot.yml

**Files:**
- Create: `.github/dependabot.yml`

- [ ] **Step 1: 確認父目錄存在**

Run:

```powershell
Test-Path .github
```

Expected: `True`（`.github/FUNDING.yml` 已存在，目錄一定在）

- [ ] **Step 2: 寫入檔案（內容逐字對齊 spec）**

用 Write 工具建立 `.github/dependabot.yml`，內容如下（與 spec `2026-05-20-dependabot-config-design.md` 的「完整檔案內容」一字不差）：

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

- [ ] **Step 3: YAML 語法 parse 驗證**

Run（PowerShell）:

```powershell
python -c "import yaml; d=yaml.safe_load(open('.github/dependabot.yml',encoding='utf-8')); print('OK version=', d['version'], 'updates=', len(d['updates']))"
```

Expected: `OK version= 2 updates= 2`

如果系統沒裝 Python，可改用任一可用的 YAML lint；最差情況跳過此步驟，依賴 Step 7 的 GitHub 後驗。

- [ ] **Step 4: 結構合規快檢（grep 關鍵 token）**

確認兩個 ecosystem、ignore、commit prefix、PR limit 都存在。

Run（用 Grep 工具，不用 PowerShell）:

```
pattern: package-ecosystem: "pub"
path: .github/dependabot.yml
```

Expected: 命中 1 次

```
pattern: package-ecosystem: "cargo"
path: .github/dependabot.yml
```

Expected: 命中 1 次

```
pattern: dependency-name: "flutter_rust_bridge"
path: .github/dependabot.yml
```

Expected: 命中 2 次（pub + cargo 各一）

```
pattern: open-pull-requests-limit: 30
path: .github/dependabot.yml
```

Expected: 命中 2 次

- [ ] **Step 5: 提交前品質檢查（依 CLAUDE.md 規範）**

雖然此變更不碰 Dart/Rust 程式碼，CLAUDE.md 明文要求 commit 前跑三項；照做維持規範一致。

Run:

```powershell
dart format lib/ test/
```

Expected: `Formatted N files (0 changed)` — 不應有任何檔案被改動。如果出現 changed 數 > 0，停下檢查為什麼，**不可** commit。

Run:

```powershell
flutter analyze
```

Expected: `No issues found!`

Run:

```powershell
flutter test
```

Expected: `All tests passed!`

> **Flaky 提醒**：依 memory `project_flaky_parallel_test_suite.md`，`log_service` / `app_release_checker` 在平行下偶發失敗。若只見這兩個 test failing，重跑一次或單獨跑該檔；綠了即非回歸，繼續。

- [ ] **Step 6: Commit**

Run:

```powershell
git add .github/dependabot.yml
git status
```

Expected: 只列出 `.github/dependabot.yml` 一個 staged file。**不要 add `docs/superpowers/`**（memory `feedback_docs_superpowers_gitignored.md`：spec / plan 不進版控）。

Commit（沿用既有 conventional commits 風格；參考最近 `chore(comments):`、`chore(lint):` commit）:

```powershell
git commit -m @'
chore(ci): add Dependabot config for pub and cargo

Weekly monitoring (Mon 09:00 Asia/Taipei). Minor + patch grouped per ecosystem; major split. flutter_rust_bridge ignored in both ecosystems since pubspec/Cargo versions must stay locked together.
'@
```

Run:

```powershell
git log --oneline -1
```

Expected: 看到新 commit `chore(ci): add Dependabot config for pub and cargo`。

- [ ] **Step 7: 後驗（push 之後，可選）**

push 之後（**等使用者明確指示再 push**），在 GitHub repo 開啟：

`Insights → Dependency graph → Dependabot`

Expected:
- 看到兩個 ecosystem entries（`pub /`、`cargo /rust`），不應出現 parse error
- 可手動點 "Check for updates" 觸發第一次掃描

---

## Self-Review

**1. Spec coverage:**
- 「監看的 ecosystem」 → Step 2 file content（pub + cargo） ✓
- 「排程 weekly Mon 09:00 Asia/Taipei」 → Step 2 兩個 ecosystem 各設 ✓
- 「分組策略 minor+patch 合併」 → Step 2 `groups.dependencies.update-types` ✓
- 「ignore flutter_rust_bridge 兩邊」 → Step 2 + Step 4 grep 驗證命中 2 次 ✓
- 「Commit message 對齊 chore(deps)」 → Step 2 `commit-message` 區塊 ✓
- 「Target branch 不設」 → Step 2 file 內不含 `target-branch` 鍵 ✓
- 「PR 上限 30」 → Step 4 grep 驗證命中 2 次 ✓
- 「驗收條件 1 (parse 無錯)」 → Step 3（local）+ Step 7（GitHub） ✓
- 「驗收條件 2 (第一次排程能跑)」 → Step 7 ✓
- 「驗收條件 3 (flutter_rust_bridge PR 不出現)」 → 設定上由 ignore 保證；無法在 commit 階段驗證，需排程觸發後觀察

**2. Placeholder scan:** 無 TBD / TODO；所有 step 都有具體指令與期望輸出 ✓

**3. Type consistency:** 設定檔，無類型 / 函式簽名問題 ✓

---

## 備註

- **不 push**：除非使用者明確指示，否則只 commit 不 push。
- **不 commit spec / plan**：`docs/superpowers/` 整個目錄不進版控（local-only 設計紀錄）。
- **單 task 規模**：此計畫只有 1 個 task。subagent-driven 對此規模 overhead 大於價值；inline execution 是合理選擇。
