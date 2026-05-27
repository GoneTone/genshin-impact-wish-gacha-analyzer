# package_info_plus 10.1.0 升級 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將 `package_info_plus` 從 `^9.0.1` 升至 `^10.1.0`，且不破壞既有功能。

**Architecture:** 此套件全專案僅 `lib/main.dart` 一處使用，9 → 10 無 API 變更，故程式碼零修改。實質工作是改一行 pubspec 約束、重新解析依賴、跑完整品質門檻驗證。唯一風險是 win32 transitive 從 5.15.0 被拉到 6.0.0 可能造成依賴衝突。

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.x、Windows-only 桌面 App。

---

## File Structure

- Modify: `pubspec.yaml`（依賴約束一行）
- Auto-modified: `pubspec.lock`（由 `flutter pub get` 重新產生）
- 不新增、不刪除任何 Dart 檔；`lib/main.dart` 不動。

---

### Task 1: 升級依賴約束並解析

**Files:**
- Modify: `pubspec.yaml`（`dependencies:` 區塊內的 `package_info_plus` 行）
- Auto-modified: `pubspec.lock`

- [ ] **Step 1: 確認改動前的基準狀態**

Run: `flutter pub deps --style=compact | Select-String "win32|package_info"`
Expected（改動前）：
```
- package_info_plus 9.0.1 [...win32 clock]
- device_info_plus 11.5.0 [...win32 win32_registry]
- win32 5.15.0 [ffi]
- win32_registry 2.1.0 [ffi meta win32]
```
記住目前 win32 = 5.15.0，作為後續比對基準。

- [ ] **Step 2: 修改 pubspec.yaml 約束**

把 `pubspec.yaml` 中這一行：
```yaml
  package_info_plus: ^9.0.1
```
改為：
```yaml
  package_info_plus: ^10.1.0
```

- [ ] **Step 3: 重新解析依賴**

Run: `flutter pub get`

**判斷分支：**
- **若成功解出**（輸出 `Got dependencies!` / `Changed N dependencies!`，無 error）→ 進入 Step 4。
- **若失敗**（`version solving failed` 或依賴衝突，通常因 `device_info_plus` / `win32_registry` 不接受 win32 6.x）→ **停止後續所有步驟**。把以下資訊整理回報給使用者，等其拍板再繼續（使用者決策：「先回報再決定」）：
  - 完整的 `version solving failed` 訊息。
  - 哪個套件卡住 win32 升級。
  - 為解出依賴需要連帶升級的套件與目標版本（可參考各套件 pub.dev changelog 確認無破壞性變更）。
  - **不要**自行升級其他套件。

- [ ] **Step 4: 確認解析結果符合預期**

Run: `flutter pub deps --style=compact | Select-String "win32|package_info"`
Expected：
```
- package_info_plus 10.1.0 [...]
- win32 6.0.0 [ffi]   # 已升至 6.x
```
確認 `package_info_plus` = 10.1.0、`win32` = 6.0.0（或更高）。

---

### Task 2: 品質門檻驗證

**Files:** 無（純驗證，依 CLAUDE.md「提交前品質檢查」）

- [ ] **Step 1: 格式化**

Run: `dart format lib/ test/`
Expected：`Formatted N files (0 changed)` 或僅必要變更；**不要**對 `.` 跑（會動到 `rust_builder/` vendored 程式碼）。

- [ ] **Step 2: 靜態分析**

Run: `flutter analyze`
Expected：`No issues found!`

- [ ] **Step 3: 測試**

Run: `flutter test`
Expected：`All tests passed!`

---

### Task 3: 實機啟動驗證

**Files:** 無（手動驗證 runtime 行為）

- [ ] **Step 1: 啟動 Windows App**

Run: `flutter run -d windows`
（建置含 Rust cargokit 流程，首次較久。）

- [ ] **Step 2: 確認版本號 log 正常**

在啟動 log 中找到 `app.startup` 的這行：
```
app start v1.0.0+1 on windows ...
```
Expected：版本號 `v1.0.0+1` 與 build number 正確印出（對應 `pubspec.yaml` 的 `version: 1.0.0+1`），無 exception。這證明 `PackageInfo.fromPlatform()` 在新版下行為不變。

- [ ] **Step 3: 基本功能煙霧測試**

App 正常開啟主畫面、無啟動崩潰即可關閉。

---

### Task 4: 提交

**Files:**
- Commit: `pubspec.yaml`、`pubspec.lock`
- **不要** commit `docs/superpowers/`（spec / plan 留本地）

- [ ] **Step 1: 確認待提交檔案**

Run: `git status`
Expected：僅 `pubspec.yaml`、`pubspec.lock` 有變更（`lib/` 應無變更）。

- [ ] **Step 2: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): bump package_info_plus from 9.0.1 to 10.1.0"
```

- [ ] **Step 3: 不主動 push**

依 CLAUDE.md，**不要**主動 `git push`。是否 push / 開 PR 交由使用者決定（機械性 dep bump 屬小型 fixup，傾向直推不開 PR）。

---

## 不做的事（YAGNI）

- 不順手升級其他無關套件（除非 Task 1 Step 3 衝突且使用者核可）。
- 不修改 `lib/main.dart` 或為未使用的 PackageInfo 欄位加程式碼。
- 不主動 git push。
