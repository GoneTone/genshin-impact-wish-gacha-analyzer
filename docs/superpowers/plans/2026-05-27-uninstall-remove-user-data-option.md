# 解除安裝時可選擇移除使用者資料 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inno Setup uninstaller 在解除安裝流程中跳出 `MsgBox` 詢問是否同時移除使用者資料（預設選 No），若使用者選 Yes 則於主程式檔案被卸載後 `DelTree` 整個 `%APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer\` 目錄。

**Architecture:** 採 Inno Setup 官方範例風格（spec 第 12.1 節說明為何不用 Wizard 自訂頁）：在 `[Code]` 段加 `ShouldRemoveUserData: Boolean` 模組變數、加 `CurUninstallStepChanged(usUninstall)` 階段彈 MsgBox 存 flag、加 `CurUninstallStepChanged(usPostUninstall)` 階段依 flag 執行 `DelTree`。文案完整翻譯繁/簡/英三組，其他語系走英文 fallback。

**Tech Stack:** Inno Setup 6.x Pascal Script、`[CustomMessages]` 多語系機制、`MsgBox(..., mbConfirmation, MB_YESNO or MB_DEFBUTTON2)`、`DelTree`、`ExpandConstant('{userappdata}\...')`、`FmtMessage`。

**Spec：** `docs/superpowers/specs/2026-05-27-uninstall-remove-user-data-option-design.md`

**測試策略：** Inno Setup script 沒有單元測試框架，採「修改 → 編譯 → 人工驗收」流程。每個 Task 修改完先用 `ISCC.exe` 編譯確認沒有 syntax error，再執行該 Task 對應的 spec checklist 子集；最後 Task 4 跑完整 8 項驗收 checklist。

---

## File Structure

修改 3 個檔案，**不新增任何檔案**：

| 檔案 | 動作 | 範圍 |
|---|---|---|
| `scripts/build_installer/installer.iss` | 修改 | 新增 `[CustomMessages]` 段（英文 fallback）、`[Code]` 段擴充 `ShouldRemoveUserData` 變數與 `CurUninstallStepChanged` procedure |
| `scripts/build_installer/ChineseTraditional.isl` | 修改 | 在既有 `[CustomMessages]` 段（從第 406 行起）末尾 append `UninstallRemoveDataBody` 一行 |
| `scripts/build_installer/ChineseSimplified.isl` | 修改 | 在既有 `[CustomMessages]` 段（從第 405 行起）末尾 append `UninstallRemoveDataBody` 一行 |

**檔案編碼備註（執行前必看）：**
- 三個檔案都是 **UTF-8 無 BOM**。
- `installer.iss` 為 **CRLF**、檔尾**有** trailing CRLF。
- 兩個 `.isl` 檔為 **CRLF**、檔尾**無** trailing newline（最後一行 `AddonHostProgramNotFound=...` 後直接 EOF）。append 新行時需以「最後一行 + CRLF + 新行」形式做 Edit 替換，避免兩行黏在一起。

---

## 編譯與驗收環境前置

執行任何 Task 前確認本機有 Inno Setup 編譯器（`ISCC.exe`）：

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /?
```

預期：印出 Inno Setup 編譯器 usage 與版本資訊（6.x）。若指令找不到，請先安裝 Inno Setup 6 並把 `ISCC.exe` 加入 PATH，或 plan 中所有 `ISCC.exe` 指令改為完整路徑。

需要先建一份 Release build 給 installer 打包：

```powershell
flutter build windows --release
```

預期：`build/windows/x64/runner/Release/genshin_impact_wish_gacha_analyzer.exe` 存在。

---

## Task 1：installer.iss 加英文 [CustomMessages] + Pascal Script 解除安裝 hook

**Files:**
- Modify: `scripts/build_installer/installer.iss`（第 91-93 行 [Run] 之後、第 95 行 [Code] 之前插入 [CustomMessages]；第 213 行 InitializeSetup 之後 append 新 procedure；同檔 [Code] 段 const 區塊之後新增 var 區塊）

### Step 1.1：在 [Run] 段之後、[Code] 段之前插入 [CustomMessages] 段

- [ ] 用 Edit 工具替換以下精確字串。

`old_string`（包含 `[Run]` 段尾兩行與接續的 `[Code]` 段首行）：
```
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Flags: nowait postinstall skipifsilent

[Code]
```

`new_string`：
```
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Flags: nowait postinstall skipifsilent

[CustomMessages]
UninstallRemoveDataBody=Also remove user data?%n%nThis will permanently delete the contents of:%n%1%n%nincluding banner records, settings, caches and logs. This cannot be undone.

[Code]
```

### Step 1.2：在 [Code] 段現有 `const` 區塊之後加 `var` 區塊

- [ ] 用 Edit 工具替換以下精確字串。

`old_string`：
```
[Code]
const
  UninstallPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';
  DisplayNameNeedle = 'Genshin Impact Wish Gacha Analyzer';
  // 新版自己的 Inno Setup 卸載 key 名稱（用於排除），格式固定為 "{AppId}_is1"
  SelfUninstKey = '{#MyAppId}_is1';
```

`new_string`：
```
[Code]
const
  UninstallPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';
  DisplayNameNeedle = 'Genshin Impact Wish Gacha Analyzer';
  // 新版自己的 Inno Setup 卸載 key 名稱（用於排除），格式固定為 "{AppId}_is1"
  SelfUninstKey = '{#MyAppId}_is1';

var
  // 解除安裝期間記錄使用者是否選擇連同移除 %APPDATA% 內的使用者資料。
  // usUninstall 階段由 MsgBox 設定，usPostUninstall 階段讀取以決定是否 DelTree。
  // Inno Setup 啟動 uninstaller process 時 Pascal Boolean 預設為 False，符合「預設不刪」語意。
  ShouldRemoveUserData: Boolean;
```

### Step 1.3：在 [Code] 段最末（`InitializeSetup` 後）append `CurUninstallStepChanged`

- [ ] 用 Edit 工具替換以下精確字串。

`old_string`（installer.iss 末尾的 `InitializeSetup` 整個 function）：
```
function InitializeSetup(): Boolean;
var
  Olds: TStringList;
  i: Integer;
  Msg: String;
begin
  Result := True;
  Olds := GetOldUninstallers();
  try
    if Olds.Count = 0 then
      Exit;

    if ActiveLanguage() = 'tradchinese' then
      Msg := '偵測到已安裝的舊版本 (Electron 版)，是否要先移除舊版本再繼續安裝新版本？' + #13#10#13#10 +
             '按「否」將取消安裝。'
    else if ActiveLanguage() = 'simpchinese' then
      Msg := '检测到已安装的旧版本 (Electron 版)，是否要先卸载旧版本再继续安装新版本？' + #13#10#13#10 +
             '单击“否”将取消安装。'
    else
      Msg := 'An older version (Electron-based) was detected. Uninstall it before continuing?' + #13#10#13#10 +
             'Selecting No will cancel the installation.';

    if MsgBox(Msg, mbConfirmation, MB_YESNO) <> IDYES then
    begin
      Result := False;
      Exit;
    end;

    for i := 0 to Olds.Count - 1 do
      RunOldUninstaller(Olds[i]);
    // 不檢查每個 RunOldUninstaller 的回傳：
    // 若 uninstaller 不存在（殘留註冊表項）→ ShellExec 失敗，但舊版已壞，讓新版蓋過去
  finally
    Olds.Free;
  end;
end;
```

`new_string`（在原 `InitializeSetup` 後 append 新 procedure）：
```
function InitializeSetup(): Boolean;
var
  Olds: TStringList;
  i: Integer;
  Msg: String;
begin
  Result := True;
  Olds := GetOldUninstallers();
  try
    if Olds.Count = 0 then
      Exit;

    if ActiveLanguage() = 'tradchinese' then
      Msg := '偵測到已安裝的舊版本 (Electron 版)，是否要先移除舊版本再繼續安裝新版本？' + #13#10#13#10 +
             '按「否」將取消安裝。'
    else if ActiveLanguage() = 'simpchinese' then
      Msg := '检测到已安装的旧版本 (Electron 版)，是否要先卸载旧版本再继续安装新版本？' + #13#10#13#10 +
             '单击“否”将取消安装。'
    else
      Msg := 'An older version (Electron-based) was detected. Uninstall it before continuing?' + #13#10#13#10 +
             'Selecting No will cancel the installation.';

    if MsgBox(Msg, mbConfirmation, MB_YESNO) <> IDYES then
    begin
      Result := False;
      Exit;
    end;

    for i := 0 to Olds.Count - 1 do
      RunOldUninstaller(Olds[i]);
    // 不檢查每個 RunOldUninstaller 的回傳：
    // 若 uninstaller 不存在（殘留註冊表項）→ ShellExec 失敗，但舊版已壞，讓新版蓋過去
  finally
    Olds.Free;
  end;
end;

// 解除安裝流程：usUninstall 階段詢問使用者是否同時移除使用者資料，
// usPostUninstall 階段依旗標執行 DelTree（主程式檔已被卸載，避免 file lock）。
// silent 模式（/VERYSILENT、/SILENT）下 MsgBox 自動回傳預設按鈕值 = IDNO，
// 結果與「預設不勾」一致。
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  UserDataDir: String;
begin
  UserDataDir := ExpandConstant('{userappdata}\tw.reh\genshin_impact_wish_gacha_analyzer');
  case CurUninstallStep of
    usUninstall:
      begin
        ShouldRemoveUserData :=
          MsgBox(
            FmtMessage(CustomMessage('UninstallRemoveDataBody'), [UserDataDir]),
            mbConfirmation,
            MB_YESNO or MB_DEFBUTTON2
          ) = IDYES;
      end;
    usPostUninstall:
      begin
        if ShouldRemoveUserData then
        begin
          if not DelTree(UserDataDir, True, True, True) then
            Log('uninstall: DelTree failed for ' + UserDataDir);
        end;
      end;
  end;
end;
```

### Step 1.4：編譯 installer 驗證 syntax

- [ ] 執行：

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DMyAppVersion=99.0.0 scripts\build_installer\installer.iss
```

預期輸出：`Successful compile (size: ... bytes)`。錯誤訊息如 `Unknown identifier "ShouldRemoveUserData"` 或 `Type mismatch` → 回到 Step 1.2 / 1.3 對照修正。

輸出檔位置：`build/installer/Genshin_Impact_Wish_Gacha_Analyzer-Setup-99.0.0.exe`。

### Step 1.5：smoke test — 不勾的 happy path（資料保留）

- [ ] 安裝、跑 app、解除安裝走預設不刪：

```powershell
# 安裝（互動式即可，預設按 Next 走完）
& "build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-99.0.0.exe"

# 安裝完成後從開始選單啟動一次 app，按一次祈願抓取或讓 app 寫入任何資料；關閉。
# 確認資料目錄已存在且有內容：
ls "$env:APPDATA\tw.reh\genshin_impact_wish_gacha_analyzer"
```

預期 `ls` 列出至少一個檔案/目錄（例如 `shared_preferences.json`、`logs\`）。

```powershell
# 從開始選單或控制台執行「解除安裝」
# 看到第一個確認 MsgBox 按 Yes；
# 看到新的英文 MsgBox "Also remove user data?..." 時按 No；
# 等解除安裝完成 MsgBox 跳出按 OK；
ls "$env:APPDATA\tw.reh\genshin_impact_wish_gacha_analyzer"
```

預期：資料目錄與內容仍在（未被 DelTree）。

### Step 1.6：smoke test — 勾 Yes 的 happy path（資料移除）

- [ ] 重裝 + 解除安裝勾 Yes：

```powershell
# 重新安裝（直接覆蓋現有安裝）
& "build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-99.0.0.exe"
# 跑 app 一次確認資料目錄又有內容
# 解除安裝，這次 "Also remove user data?" 選 Yes
ls "$env:APPDATA\tw.reh\genshin_impact_wish_gacha_analyzer" 2>&1
```

預期：`ls` 回 `Cannot find path ...` / `ItemNotFoundException`（目錄已不存在）。

### Step 1.7：Commit

- [ ] 執行格式檢查與分析（CLAUDE.md 提交前品質檢查的 1-3 步只限 Dart/Flutter，本 task 沒動 lib/ 與 test/，跳過 `dart format`、`flutter analyze`、`flutter test`）。

- [ ] 執行 commit：

```powershell
git add scripts/build_installer/installer.iss
git commit -m @'
feat(installer): ask whether to remove user data on uninstall

Adds a "Also remove user data?" MsgBox during uninstall (defaults to No,
MB_DEFBUTTON2). When the user opts in, %APPDATA%\tw.reh\... is DelTree'd
during usPostUninstall after the main app files have been removed.

English fallback text lives in installer.iss [CustomMessages]; localized
strings will be added in follow-up commits.

Spec: docs/superpowers/specs/2026-05-27-uninstall-remove-user-data-option-design.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

預期：commit 成功，git status 顯示 clean。

---

## Task 2：繁體中文翻譯

**Files:**
- Modify: `scripts/build_installer/ChineseTraditional.isl`（在第 406 行 `[CustomMessages]` 段的最末 append 一行）

### Step 2.1：append `UninstallRemoveDataBody` 翻譯到既有 [CustomMessages] 段

- [ ] 用 Edit 工具替換最末一行（注意該檔檔尾**沒有** trailing newline，所以替換時手動加 CRLF）：

`old_string`（檔案最末一行原文，無 trailing newline）：
```
AddonHostProgramNotFound=%1 無法在您所選的資料夾中找到。%n%n您是否還要繼續？
```

`new_string`（原行 + CRLF + 新行）：
```
AddonHostProgramNotFound=%1 無法在您所選的資料夾中找到。%n%n您是否還要繼續？
UninstallRemoveDataBody=是否要同時移除使用者資料？%n%n將永久刪除位於以下目錄的所有內容：%n%1%n%n包含卡池記錄、設定、快取與 log。此操作無法復原。
```

> 用詞約定：用「卡池記錄」（非「祈願記錄」），「記錄」不是「紀錄」。見 memory `feedback_terminology_gacha_records_naming`。

### Step 2.2：編譯驗證

- [ ] 執行：

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DMyAppVersion=99.0.0 scripts\build_installer\installer.iss
```

預期：`Successful compile`。

### Step 2.3：繁中 locale 驗收

- [ ] 把 Windows 系統顯示語言切到繁體中文（控制台 → 地區 → 系統地區設定），重啟系統後安裝、解除安裝。

或更輕量：執行 installer 時把語言下拉選 `繁體中文`：

```powershell
& "build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-99.0.0.exe" /LANG=tradchinese
```

裝完後跑解除安裝，預期：
- MsgBox 標題：「確認」（由 Windows 系統提供的 `mbConfirmation` 標題）
- MsgBox body 為繁中：「是否要同時移除使用者資料？...將永久刪除位於以下目錄的所有內容：[展開的絕對路徑]...包含卡池記錄、設定、快取與 log。此操作無法復原。」
- 路徑顯示為 expanded 絕對路徑（如 `C:\Users\foo\AppData\Roaming\tw.reh\genshin_impact_wish_gacha_analyzer`），**不含** `{userappdata}` 或 `%APPDATA%` 字面。

### Step 2.4：Commit

- [ ] 執行：

```powershell
git add scripts/build_installer/ChineseTraditional.isl
git commit -m @'
feat(installer): add Traditional Chinese translation for uninstall data removal prompt

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 3：簡體中文翻譯

**Files:**
- Modify: `scripts/build_installer/ChineseSimplified.isl`（在第 405 行 `[CustomMessages]` 段的最末 append 一行）

### Step 3.1：append `UninstallRemoveDataBody` 翻譯

- [ ] 用 Edit 工具替換最末一行（檔尾**沒有** trailing newline）：

`old_string`：
```
AddonHostProgramNotFound=您选择的文件夹中无法找到 %1。%n%n您要继续吗？
```

`new_string`：
```
AddonHostProgramNotFound=您选择的文件夹中无法找到 %1。%n%n您要继续吗？
UninstallRemoveDataBody=是否要同时移除用户数据？%n%n将永久删除位于以下目录的所有内容：%n%1%n%n包含卡池记录、设定、缓存与 log。此操作无法复原。
```

### Step 3.2：編譯驗證

- [ ] 執行：

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DMyAppVersion=99.0.0 scripts\build_installer\installer.iss
```

預期：`Successful compile`。

### Step 3.3：簡中 locale 驗收

- [ ] 執行 installer 並選擇簡中：

```powershell
& "build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-99.0.0.exe" /LANG=simpchinese
```

裝完後解除安裝，預期 MsgBox body 為簡中：「是否要同时移除用户数据？...包含卡池记录、设定、缓存与 log。此操作无法复原。」

### Step 3.4：Commit

- [ ] 執行：

```powershell
git add scripts/build_installer/ChineseSimplified.isl
git commit -m @'
feat(installer): add Simplified Chinese translation for uninstall data removal prompt

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 4：完整人工驗收 checklist

**Files:** 無修改（純驗收）

跑完整 8 項 spec 第 10 節驗收 checklist。若任何一項失敗，回到對應 Task 找原因。**所有項目都通過才算 Task 4 完成**。

每一項都記錄通過/失敗，並把通過記錄寫進 PR 描述。

### Step 4.1：建乾淨環境

- [ ] 確保開始驗收前沒有殘留資料：

```powershell
Remove-Item -Recurse -Force "$env:APPDATA\tw.reh" -ErrorAction SilentlyContinue
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DMyAppVersion=99.0.0 scripts\build_installer\installer.iss
```

預期：`$env:APPDATA\tw.reh` 不存在；installer 編譯成功。

### Step 4.2：驗收 1 — 安裝後資料目錄存在

- [ ] 安裝、跑 app、產生資料：

```powershell
& "build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-99.0.0.exe"
# 從開始選單啟動 app，操作至少寫入一些設定（例如切換主題）後關閉。
Test-Path "$env:APPDATA\tw.reh\genshin_impact_wish_gacha_analyzer\shared_preferences.json"
```

預期：`True`。

### Step 4.3：驗收 2 — 解除安裝選 No 資料保留

- [ ] 從控制台或開始選單執行解除安裝，第一個 Inno 內建確認選 Yes，第二個 "Also remove user data?" 選 **No**。

預期：
- 解除安裝完成
- `Test-Path "$env:APPDATA\tw.reh\genshin_impact_wish_gacha_analyzer\shared_preferences.json"` 仍為 `True`

### Step 4.4：驗收 3 — 重裝後舊資料能讀回

- [ ] 重新安裝、啟動 app：

```powershell
& "build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-99.0.0.exe"
# 啟動 app，確認上一輪設定（主題、語言等）仍生效
```

預期：先前的設定仍在（例如 UID、主題、語言偏好）。

### Step 4.5：驗收 4 — 解除安裝選 Yes 資料目錄消失

- [ ] 解除安裝，"Also remove user data?" 選 **Yes**：

```powershell
Test-Path "$env:APPDATA\tw.reh\genshin_impact_wish_gacha_analyzer"
```

預期：`False`。

### Step 4.6：驗收 5 — Enter 走預設 No；Esc 無反應

- [ ] 重裝 + 跑 app 產生資料；
- [ ] 解除安裝到 "Also remove user data?" MsgBox 時：
  - 先**按 Esc**：MsgBox 應**無反應**不關閉（`MB_YESNO` 無 Cancel 按鈕）；
  - 再**按 Enter**：MsgBox 關閉，等同選 No。

```powershell
Test-Path "$env:APPDATA\tw.reh\genshin_impact_wish_gacha_analyzer"
```

預期：`True`（Enter 走預設 No，資料保留）。

### Step 4.7：驗收 6 — /VERYSILENT 走預設不刪資料

- [ ] 重裝、跑 app；
- [ ] 用 silent 模式解除安裝：

```powershell
# 找到 uninstaller 路徑（依安裝時選的 DefaultDirName）
$uninst = "${env:ProgramFiles}\Genshin_Impact_Wish_Gacha_Analyzer\unins000.exe"
& $uninst /VERYSILENT
# 等幾秒讓 silent uninstall 完成
Test-Path "$env:APPDATA\tw.reh\genshin_impact_wish_gacha_analyzer"
```

預期：`True`（silent 模式 MsgBox 自動回 IDNO，不刪資料）。

### Step 4.8：驗收 7 — 三語系文案驗收

- [ ] **繁中**：清資料後重裝，installer 語言選繁中，解除安裝確認 MsgBox 為繁體中文，且 body 用「卡池記錄」、「設定、快取與 log」、「此操作無法復原」字眼。
- [ ] **簡中**：清資料後重裝，installer 語言選簡中，解除安裝確認 MsgBox 為簡體中文，且 body 用「卡池记录」、「设定、缓存与 log」、「此操作无法复原」字眼。
- [ ] **英文**：清資料後重裝，installer 語言選 English，解除安裝確認 MsgBox 為英文，且 body 包含 "banner records, settings, caches and logs"、"This cannot be undone"。
- [ ] **其他語系（abstract 驗一個）**：clean 重裝後 installer 語言選 Japanese 或 French，解除安裝 MsgBox body 應為英文 fallback（包含 "banner records, settings, caches and logs"），確認 fallback 路徑生效。

### Step 4.9：驗收 8 — 路徑為 expanded 絕對路徑

- [ ] 任一語系下解除安裝至 MsgBox，body 中顯示的路徑應為 expanded 絕對路徑（例如 `C:\Users\foo\AppData\Roaming\tw.reh\genshin_impact_wish_gacha_analyzer`），**不含** `{userappdata}` 或 `%APPDATA%` 字面。

### Step 4.10：（不 commit；把結果寫入 PR 描述）

- [ ] 8 項全部通過後，把通過紀錄整理成 markdown 加進 PR 描述：

```markdown
## Verification

Manual acceptance against spec § 10:

- [x] 1. 安裝 → 資料目錄存在
- [x] 2. 解除安裝選 No → 資料保留
- [x] 3. 重裝 → 舊資料讀回
- [x] 4. 解除安裝選 Yes → 資料目錄消失
- [x] 5. Enter 走預設 No / Esc 無反應
- [x] 6. /VERYSILENT → 資料保留
- [x] 7. 繁中 / 簡中 / 英文 / 其他語系（英文 fallback） 文案正確
- [x] 8. MsgBox 路徑為 expanded 絕對路徑
```

### Step 4.11：清理 99.0.0 測試 build

- [ ] 把測試用 99.0.0 build 從目錄移除（不入 git）：

```powershell
Remove-Item "build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-99.0.0.exe" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:APPDATA\tw.reh" -ErrorAction SilentlyContinue
```

預期：兩個路徑都不存在。

---

## 完成後

整批改動 = Task 1、Task 2、Task 3 三個 commit（皆已包含 `Co-Authored-By` trailer）。

依 memory `feedback_small_fixups_no_pr` 規則：本 plan 含 Pascal 邏輯（非機械改動或翻譯 fixup），**走 PR 流程**而非直 push。PR 描述模板：

```markdown
## Summary
- 解除安裝時新增 "Also remove user data?" MsgBox（預設 No）。
- 勾 Yes 時 DelTree 整個 %APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer\。
- 翻譯：繁/簡完整、英文 fallback；其他語系走英文 fallback。

## Spec / Plan
- Spec: docs/superpowers/specs/2026-05-27-uninstall-remove-user-data-option-design.md (本地)
- Plan: docs/superpowers/plans/2026-05-27-uninstall-remove-user-data-option.md (本地)

## Verification
[Task 4.10 產出的 8 項勾選清單]

## Risks / Notes
- Inno Setup MsgBox 標題由系統 locale 自帶 ("Confirm" / "確認")。
- silent 解除安裝走預設 IDNO，不刪資料。
- DelTree 失敗只記 Log()，不阻擋解除安裝完成。
```

不 push 到 remote、不 `gh pr create`（依 CLAUDE.md 規則：不主動 git push）— 等使用者下指令。
