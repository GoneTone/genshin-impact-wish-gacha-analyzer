# Windows Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `scripts/build_installer/installer.iss` 與 `scripts/build_installer/build_release.ps1`,讓開發者一指令產出 Windows 安裝檔,安裝時自動偵測並卸載舊版 Electron 版。

**Architecture:** PowerShell 腳本負責 build pipeline(讀版本號 → 偵測 Inno Setup → `flutter build` → 呼叫 `ISCC.exe`)。Inno Setup 腳本 perMachine 安裝到 `C:\Program Files\Genshin_Impact_Wish_Gacha_Analyzer\`,`[Code]` 區段在 `InitializeSetup()` 掃描 Uninstall 註冊表,以 DisplayName 模糊比對找出舊版,用 `ShellExec('', ...)` 直接執行(新版已 admin)。

**Tech Stack:** Inno Setup 6.3+(Pascal Script),PowerShell 7+,Flutter 3.x Windows,flutter_rust_bridge。

**Spec:** `docs/superpowers/specs/2026-05-12-windows-installer-design.md`

---

## 前置條件(實作開始前必須完成)

- [ ] 安裝 Inno Setup 6.3 或以上版本:https://jrsoftware.org/isdl.php
- [ ] 安裝完成後執行 `ISCC.exe` 確認可用(預設路徑:`C:\Program Files (x86)\Inno Setup 6\ISCC.exe`)
- [ ] 確認 `flutter build windows --release` 在本機可成功跑完一次(產生 `build/windows/x64/runner/Release/genshin_impact_wish_gacha_analyzer.exe`)

> **註**:`docs/superpowers/` 與 `/build/` 已在 `.gitignore`,本實作不需修改 `.gitignore`。

---

## Task 1: 建立 `scripts/build_installer/build_release.ps1`(版本號讀取)

**Files:**
- Create: `scripts/build_installer/build_release.ps1`

- [ ] **Step 1: 建立 `scripts/` 目錄**

```powershell
New-Item -ItemType Directory -Force scripts
```

- [ ] **Step 2: 寫入 `scripts/build_installer/build_release.ps1` 第一版(只做版本號讀取)**

```powershell
# scripts/build_installer/build_release.ps1
#
# Genshin Impact Wish Gacha Analyzer — Windows 一鍵打包腳本
#
# 流程：
#   1. 從 pubspec.yaml 讀版本號
#   2. 偵測 Inno Setup 6 是否安裝
#   3. flutter pub get + flutter build windows --release
#   4. 呼叫 ISCC.exe 編譯 installer.iss
#   5. 報告產物路徑
#
# 用法：
#   .\scripts\build_installer\build_release.ps1

$ErrorActionPreference = 'Stop'

# 切到專案根目錄（以本腳本為基準往上一層）
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $ProjectRoot

# --- 1. 讀版本號 -------------------------------------------------------------
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
if (-not (Test-Path $PubspecPath)) {
    throw "找不到 pubspec.yaml：$PubspecPath"
}

$VersionLine = Select-String -Path $PubspecPath -Pattern '^version:\s*([^\s+]+)' | Select-Object -First 1
if (-not $VersionLine) {
    throw "無法從 pubspec.yaml 抓到 version"
}
$Version = $VersionLine.Matches[0].Groups[1].Value
Write-Host "版本號：$Version" -ForegroundColor Cyan
```

- [ ] **Step 3: 跑腳本驗證版本號讀取**

```powershell
.\scripts\build_installer\build_release.ps1
```

Expected:
```
版本號:1.0.0
```

- [ ] **Step 4: Commit**

```powershell
git add scripts/build_installer/build_release.ps1
git commit -m "feat(scripts): add build_release.ps1 with pubspec version parsing"
```

---

## Task 2: `scripts/build_installer/build_release.ps1` 加入 Inno Setup 偵測

**Files:**
- Modify: `scripts/build_installer/build_release.ps1`

- [ ] **Step 1: 在版本號讀取之後追加 ISCC 偵測函式與呼叫**

在 Task 1 寫的內容後面(`Write-Host "版本號:..."` 之後)追加:

```powershell

# --- 2. 偵測 ISCC.exe ---------------------------------------------------------
function Find-ISCC {
    # 註冊表
    $RegKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1'
    )
    foreach ($key in $RegKeys) {
        if (Test-Path $key) {
            $loc = (Get-ItemProperty $key -ErrorAction SilentlyContinue).InstallLocation
            if ($loc) {
                $iscc = Join-Path $loc 'ISCC.exe'
                if (Test-Path $iscc) { return $iscc }
            }
        }
    }

    # 預設安裝路徑
    $FallbackPaths = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    )
    foreach ($p in $FallbackPaths) {
        if (Test-Path $p) { return $p }
    }

    return $null
}

$ISCC = Find-ISCC
if (-not $ISCC) {
    Write-Host ""
    Write-Host "找不到 Inno Setup 6。請下載並安裝：" -ForegroundColor Red
    Write-Host "  https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
    Write-Host "  (需要 6.3 或以上版本)" -ForegroundColor Yellow
    exit 1
}
Write-Host "Inno Setup:$ISCC" -ForegroundColor Cyan
```

- [ ] **Step 2: 跑腳本驗證偵測成功**

```powershell
.\scripts\build_installer\build_release.ps1
```

Expected(已安裝 Inno Setup 的情況):
```
版本號:1.0.0
Inno Setup:C:\Program Files (x86)\Inno Setup 6\ISCC.exe
```

如未安裝 Inno Setup,應該看到紅字錯誤訊息與下載連結,並以 exit code 1 結束。

- [ ] **Step 3: Commit**

```powershell
git add scripts/build_installer/build_release.ps1
git commit -m "feat(scripts): detect Inno Setup installation in build_release.ps1"
```

---

## Task 3: 建立 `scripts/build_installer/installer.iss` 基本骨架(無 `[Code]`)

**Files:**
- Create: `scripts/build_installer/installer.iss`

- [ ] **Step 1: 寫入 `scripts/build_installer/installer.iss`**

```ini
; scripts/build_installer/installer.iss
;
; Genshin Impact Wish Gacha Analyzer — Inno Setup 安裝檔
;
; 編譯方式：
;   ISCC.exe /DMyAppVersion=1.0.0 scripts\build_installer\installer.iss
;
; AppId 為固定 GUID，任何情況下不得變更（會破壞升級路徑）。

#define MyAppId       "{50C50DF7-CB14-4D51-9618-0E5116DDA065}"
#define MyAppName     "Genshin Impact Wish Gacha Analyzer"
#define MyAppExeName  "genshin_impact_wish_gacha_analyzer.exe"
#define MyAppPublisher "原神資訊站 Genshin Impact Info"
#define MyAppURL      "https://genshininfo.reh.tw/"

; MyAppVersion 透過 ISCC /DMyAppVersion=... 從外面傳入
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

[Setup]
AppId={{#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppCopyright=Copyright (C) 2020-{#GetDateTimeString('yyyy','','')} {#MyAppPublisher}
DefaultDirName={commonpf}\Genshin_Impact_Wish_Gacha_Analyzer
DefaultGroupName={#MyAppName}
DisableDirPage=no
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2/ultra
SolidCompression=yes
WizardStyle=modern
OutputDir=..\build\installer
OutputBaseFilename=Genshin_Impact_Wish_Gacha_Analyzer-Setup-{#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "tradchinese"; MessagesFile: "ChineseTraditional.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
    Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Flags: nowait postinstall skipifsilent
```

> **重點細節**:
> - `AppId={{#MyAppId}` — 開頭兩個 `{` 是 Inno Setup 對字面 `{` 的跳脫;展開後值為 `{50C50DF7-...}`,告訴 Inno Setup 這是 GUID 形式的 AppId。
> - `{commondesktop}` — perMachine 模式下桌面捷徑放共用桌面,所有使用者可見。
> - `..\` 是相對於 `installer.iss` 所在目錄(`scripts/`),所以指向專案根目錄。

- [ ] **Step 2: 先跑一次 `flutter build windows --release` 確保 Release 資料夾存在**

```powershell
flutter pub get
flutter build windows --release
```

Expected: `build\windows\x64\runner\Release\genshin_impact_wish_gacha_analyzer.exe` 存在。

- [ ] **Step 3: 用 ISCC 直接編譯 installer.iss 驗證語法**

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DMyAppVersion=1.0.0 scripts\build_installer\installer.iss
```

Expected:
- 沒有編譯錯誤
- 產生 `build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-1.0.0.exe`

若 ISCC 報「ArchitecturesInstallIn64BitMode unknown value 'x64compatible'」→ 你的 Inno Setup 版本低於 6.3。改成 `x64` 並升級 Inno Setup。

- [ ] **Step 4: Commit**

```powershell
git add scripts/build_installer/installer.iss
git commit -m "feat(scripts): add Inno Setup installer script (basic structure)"
```

---

## Task 4: `scripts/build_installer/installer.iss` 加入 `[Code]` 偵測舊版邏輯

**Files:**
- Modify: `scripts/build_installer/installer.iss`(在檔案最末追加 `[Code]` 區段)

- [ ] **Step 1: 在 `installer.iss` 最後追加 `[Code]` 區段**

```pascal

[Code]
const
  UninstallPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';
  DisplayNameNeedle = 'Genshin Impact Wish Gacha Analyzer';
  // 新版自己的 Inno Setup 卸載 key 名稱（用於排除），格式固定為 "{AppId}_is1"
  SelfUninstKey = '{#MyAppId}_is1';

// 收集所有判定為「舊版」的 UninstallString
procedure CollectOldUninstallers(RootKey: Integer; const SubPath: String; List: TStringList);
var
  SubKeys: TArrayOfString;
  i: Integer;
  KeyName, FullPath, DisplayName, UninstallString: String;
begin
  if not RegGetSubkeyNames(RootKey, SubPath, SubKeys) then
    Exit;
  for i := 0 to GetArrayLength(SubKeys) - 1 do
  begin
    KeyName := SubKeys[i];
    if SameText(KeyName, SelfUninstKey) then
      Continue;
    FullPath := SubPath + '\' + KeyName;
    if not RegQueryStringValue(RootKey, FullPath, 'DisplayName', DisplayName) then
      Continue;
    if Pos(DisplayNameNeedle, DisplayName) = 0 then
      Continue;
    if not RegQueryStringValue(RootKey, FullPath, 'UninstallString', UninstallString) then
      Continue;
    if Trim(UninstallString) = '' then
      Continue;
    List.Add(UninstallString);
  end;
end;

function GetOldUninstallers(): TStringList;
begin
  Result := TStringList.Create;
  Result.Duplicates := dupIgnore;
  Result.Sorted := True;
  CollectOldUninstallers(HKLM32, UninstallPath, Result);
  CollectOldUninstallers(HKLM64, UninstallPath, Result);
  CollectOldUninstallers(HKCU,   UninstallPath, Result);
end;

// 解析 UninstallString，拆出 exe 路徑與額外參數
procedure ParseUninstallCommand(const Cmd: String; var ExePath, ExtraArgs: String);
var
  Trimmed: String;
  EndQuote: Integer;
begin
  Trimmed := Trim(Cmd);
  ExtraArgs := '';
  if (Length(Trimmed) > 0) and (Trimmed[1] = '"') then
  begin
    EndQuote := Pos('"', Copy(Trimmed, 2, Length(Trimmed))) + 1;
    if EndQuote > 1 then
    begin
      ExePath := Copy(Trimmed, 2, EndQuote - 2);
      ExtraArgs := Trim(Copy(Trimmed, EndQuote + 1, Length(Trimmed)));
    end
    else
      ExePath := Trimmed;
  end
  else
  begin
    ExePath := Trimmed;
  end;
end;

function RunOldUninstaller(const UninstallString: String): Boolean;
var
  ExePath, ExtraArgs, Params: String;
  ResultCode: Integer;
begin
  ParseUninstallCommand(UninstallString, ExePath, ExtraArgs);
  // NSIS 靜默卸載 + 全機器；若舊版 uninstaller 不認得，參數會被忽略
  Params := '/S /allusers';
  if ExtraArgs <> '' then
    Params := ExtraArgs + ' ' + Params;
  // 新版本身已 admin，直接執行舊版 uninstaller 不需要再提權
  Result := ShellExec('', ExePath, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

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

- [ ] **Step 2: 用 ISCC 重新編譯驗證 `[Code]` 語法正確**

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DMyAppVersion=1.0.0 scripts\build_installer\installer.iss
```

Expected:
- 編譯成功(Pascal Script 語法檢查通過)
- 重新產生 `build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-1.0.0.exe`

若報「Type mismatch」或「Unknown identifier」→ 比對 Step 1 程式碼,常見錯字:`TStringList`、`TArrayOfString`、`ewWaitUntilTerminated`、`SW_HIDE` 大小寫敏感。

- [ ] **Step 3: 跑新生成的 Setup.exe(乾淨機器情境)驗證沒誤判**

```powershell
build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-1.0.0.exe
```

Expected(假設本機沒裝過舊版 Electron 版):
- 不跳出「偵測到舊版」訊息
- 直接進入安裝精靈
- 可正常安裝;桌面、開始選單都建立捷徑;啟動 app 正常

裝完後從「應用程式與功能」卸載乾淨。

- [ ] **Step 4: Commit**

```powershell
git add scripts/build_installer/installer.iss
git commit -m "feat(scripts): detect and uninstall legacy Electron version on install"
```

---

## Task 5: `scripts/build_installer/build_release.ps1` 串接呼叫 ISCC

**Files:**
- Modify: `scripts/build_installer/build_release.ps1`

- [ ] **Step 1: 在 ISCC 偵測之後追加 build pipeline**

在 Task 2 寫的 `Write-Host "Inno Setup:..."` 之後追加:

```powershell

# --- 3. Flutter build --------------------------------------------------------
Write-Host ""
Write-Host "==> flutter pub get" -ForegroundColor Green
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get 失敗" }

Write-Host ""
Write-Host "==> flutter build windows --release" -ForegroundColor Green
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build 失敗" }

# --- 4. 編譯安裝檔 ----------------------------------------------------------
$InstallerDir = Join-Path $ProjectRoot 'build\installer'
New-Item -ItemType Directory -Force $InstallerDir | Out-Null

$IssPath = Join-Path $ProjectRoot 'scripts\build_installer\installer.iss'

Write-Host ""
Write-Host "==> ISCC compile" -ForegroundColor Green
& $ISCC "/DMyAppVersion=$Version" $IssPath
if ($LASTEXITCODE -ne 0) { throw "ISCC 編譯失敗" }

# --- 5. 報告產物 -------------------------------------------------------------
$Output = Join-Path $InstallerDir "Genshin_Impact_Wish_Gacha_Analyzer-Setup-$Version.exe"
Write-Host ""
Write-Host "完成！產物：" -ForegroundColor Green
Write-Host "  $Output" -ForegroundColor Cyan
```

- [ ] **Step 2: end-to-end 驗證 — 從 clean 跑到產物**

```powershell
# 先清掉之前的產物
Remove-Item build\installer -Recurse -Force -ErrorAction SilentlyContinue

# 一鍵跑
.\scripts\build_installer\build_release.ps1
```

Expected 流程順序:
```
版本號:1.0.0
Inno Setup:C:\Program Files (x86)\Inno Setup 6\ISCC.exe

==> flutter pub get
(...flutter 輸出...)

==> flutter build windows --release
(...flutter 輸出...)
✓ Built build\windows\x64\runner\Release\genshin_impact_wish_gacha_analyzer.exe

==> ISCC compile
Inno Setup 6 Compiler
(...ISCC 輸出...)
Successful compile (xxx KiB)

完成!產物:
  E:\IdeaProjects\genshin_impact_wish_gacha_analyzer\build\installer\Genshin_Impact_Wish_Gacha_Analyzer-Setup-1.0.0.exe
```

- [ ] **Step 3: Commit**

```powershell
git add scripts/build_installer/build_release.ps1
git commit -m "feat(scripts): wire up full build pipeline in build_release.ps1"
```

---

## Task 6: 手動驗證(不 commit,僅人工跑過)

對應 spec 的「測試策略」清單。Task 1–5 完成後,逐項打勾。

- [ ] **基本打包**
  - [ ] `.\scripts\build_installer\build_release.ps1` 從零跑通,產出 `Genshin_Impact_Wish_Gacha_Analyzer-Setup-{version}.exe`
  - [ ] 檔名版本號跟 `pubspec.yaml` 一致(目前 `1.0.0`)

- [ ] **乾淨安裝(本機沒裝過任何版本的狀態)**
  - [ ] 雙擊 Setup → 跳一次 UAC(perMachine 必跳) → **不**跳偵測舊版訊息
  - [ ] 安裝精靈可切換英文 / 繁中
  - [ ] 預設安裝目錄:`C:\Program Files\Genshin_Impact_Wish_Gacha_Analyzer`
  - [ ] 可改安裝目錄
  - [ ] 桌面捷徑勾選 → 安裝後出現
  - [ ] 開始選單群組 `Genshin Impact Wish Gacha Analyzer` 出現
  - [ ] 「應用程式與功能」清單顯示 DisplayName + icon 正確
  - [ ] 啟動 app,UI 正常顯示(flutter_rust_bridge DLL 正常載入)

- [ ] **重複安裝新版**(已裝完新版的狀態下再跑 Setup)
  - [ ] 自己不會被誤判為「舊版」→ 不跳偵測訊息
  - [ ] 一般升級流程(或卸載重裝)

- [ ] **偵測舊版**(此項需要有舊版 Electron 版可測;若無 → 在發佈前用 VM 或測試機跑一次)
  - [ ] 跳出偵測訊息(語言依精靈當前語言)
  - [ ] 按「是」→ 舊版被靜默移除(不再跳第二次 UAC,新版已 admin)→ 新版繼續安裝
  - [ ] 按「否」→ 安裝中止,舊版完整保留(不留任何新版檔案)

- [ ] **卸載新版**
  - [ ] 從「應用程式與功能」卸載
  - [ ] 安裝目錄(`C:\Program Files\Genshin_Impact_Wish_Gacha_Analyzer`)被刪除
  - [ ] 桌面/開始選單捷徑被刪除
  - [ ] 註冊表 Uninstall key 移除

---

## 完成標準

- 所有 Task 1–5 都已 commit
- 手動驗證 checklist「基本打包」「乾淨安裝」「重複安裝新版」「卸載新版」全部 OK
- 「偵測舊版」標記為「等發佈前驗證」(若本機沒舊版)

## 不在本計畫範圍

- portable / zip 產物
- GitHub Actions 自動發佈
- auto_updater 套件
- 舊版資料遷移(`%APPDATA%` → `path_provider` 路徑)

以上若日後需要,各自開新 spec 與 plan。
