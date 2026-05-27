# Windows 組織識別改名實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將 Windows app 組織識別由 `com.example` 改為 `tw.reh`，版權人改為 `GoneTone`，並驗證新 `%APPDATA%` 資料目錄生效。

**Architecture:** 僅修改 `windows/runner/Runner.rc` 兩行字串資源（`CompanyName`、`LegalCopyright`）。`CompanyName` 由 `path_provider_windows` 用於組出 `getApplicationSupportDirectory()` 路徑，須 rebuild Windows app 後才生效。無 Dart 變更、無自動化測試可涵蓋（Windows 資源字串無法單元測試），改用實機 build + 檔案路徑驗證。

**Tech Stack:** Flutter (Windows desktop)、Win32 resource script (`.rc`)、`path_provider_windows`。

---

### Task 1: 修改 Runner.rc 的組織字串

**Files:**
- Modify: `windows/runner/Runner.rc:92`、`windows/runner/Runner.rc:96`

- [ ] **Step 1: 改 `CompanyName`（L92）**

將：

```
            VALUE "CompanyName", "com.example" "\0"
```

改為：

```
            VALUE "CompanyName", "tw.reh" "\0"
```

- [ ] **Step 2: 改 `LegalCopyright`（L96）**

將：

```
            VALUE "LegalCopyright", "Copyright (C) 2026 com.example. All rights reserved." "\0"
```

改為：

```
            VALUE "LegalCopyright", "Copyright (C) 2026 GoneTone. All rights reserved." "\0"
```

- [ ] **Step 3: 確認檔案內已無殘留 `com.example`**

Run: `Select-String -Path windows\runner\Runner.rc -Pattern "com\.example"`
Expected: 無任何輸出（exit，無 match）。

- [ ] **Step 4: Commit**

```bash
git add windows/runner/Runner.rc
git commit -m "chore(windows): rename org com.example -> tw.reh, copyright -> GoneTone"
```

（注意：`docs/superpowers/` 依專案慣例不進版控，本計畫與 spec 檔案**不要** `git add`。）

---

### Task 2: Rebuild 並驗證新資料目錄

**Files:** 無檔案變更，純驗證。

- [ ] **Step 1: 提交前品質檢查（無 Dart 變更，作為迴歸確認）**

Run:
```
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `flutter analyze` 輸出 `No issues found!`；`flutter test` 輸出 `All tests passed!`。

- [ ] **Step 2: Rebuild Windows app**

Run: `flutter run -d windows`
Expected: app 成功啟動（資源檔已重新編入 exe）。

- [ ] **Step 3: 驗證新資料目錄被建立**

app 啟動後，`main.dart` 會呼叫 `getApplicationSupportDirectory()` 並由 `LogService.bootstrap` 建立 `logs/`。驗證路徑：

Run: `Test-Path "$env:APPDATA\tw.reh\genshin_impact_wish_gacha_analyzer\logs"`
Expected: `True`。

- [ ] **Step 4: 確認舊路徑不再被寫入**

檢查舊目錄沒有本次啟動產生的新 log（若存在僅為先前測試殘留，不影響）：

Run: `Test-Path "$env:APPDATA\com.example\genshin_impact_wish_gacha_analyzer"`
Expected: 可為 `True`（舊測試殘留）或 `False`；重點是 Step 3 的 `tw.reh` 路徑為 `True` 且當次啟動的 log 落在新路徑。

- [ ] **Step 5: （可選）清掉舊測試目錄**

確認 `tw.reh` 路徑正常後，舊測試垃圾可清除：

Run: `Remove-Item -Recurse -Force "$env:APPDATA\com.example\genshin_impact_wish_gacha_analyzer" -ErrorAction SilentlyContinue`
Expected: 無錯誤輸出（目錄不存在亦可）。

---

## Self-Review

**Spec coverage:**
- spec「變更範圍」L92/L96 兩行 → Task 1 Step 1–2 ✅
- spec「連帶影響：須 rebuild」→ Task 2 Step 2 ✅
- spec「驗證：開啟 logs 資料夾 / 確認新路徑建立」→ Task 2 Step 3 ✅（以 `Test-Path` 取代手動點按鈕，等效且可自動驗證）
- spec「提交前品質檢查照常跑」→ Task 2 Step 1 ✅
- spec「不加遷移邏輯」→ 計畫無此任務 ✅
- spec「不動 ca.rs / 無其他平台」→ 範圍外，計畫未涉及 ✅

**Placeholder scan:** 無 TBD/TODO/「適當處理」等紅旗；每步皆有確切字串與指令。

**Type consistency:** 無型別/簽章；改動為固定字串字面值，前後一致（`tw.reh`、`Copyright (C) 2026 GoneTone. All rights reserved.`）。

通過。
