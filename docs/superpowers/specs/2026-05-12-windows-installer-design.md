# Windows Installer 打包設計

- **日期**:2026-05-12
- **狀態**:已批准,待實作
- **作用範圍**:flutter-rewrite 分支,Windows 桌面打包

## 背景

舊版 master 分支基於 Electron + electron-builder,在 `vue.config.js` 設定後一鍵產出 NSIS 安裝檔、portable、zip 三件套,並支援 GitHub Releases 自動更新。

flutter-rewrite 分支重寫為 Flutter Windows + Rust (flutter_rust_bridge)。`flutter build windows --release` 只會產出 `build/windows/x64/runner/Release/` 資料夾(`.exe` + 多個 `.dll` + `data/`),沒有打包成安裝檔的官方流程。

本設計補上等價於 electron-builder 的 Windows 打包流程,目標讓開發者可以一指令產出可發佈的安裝檔,使用者點兩下就能安裝、並會自動覆蓋舊版 Electron 版。

## 目標與非目標

### 目標

- 一鍵產出 Windows 安裝檔(`.exe`,Inno Setup 製作)
- 新版安裝檔安裝時自動偵測並卸載舊版 Electron 版(若有)
- 版本號自動從 `pubspec.yaml` 讀取,不需手動同步
- 安裝精靈支援英文與繁體中文
- 沒裝舊版的使用者不會看到偵測舊版訊息(Setup 啟動時會跳一次 UAC,因為改為 perMachine)

### 非目標(YAGNI)

- portable / zip 產物(交給使用者自己從安裝檔取得,或日後有需求再加)
- GitHub Actions 自動發佈
- 自動更新機制(`auto_updater` 套件等)
- 舊版 `certificates/` 搬移(Flutter 版已不用 MITM proxy,確認過 `lib/` 無相關 import)
- 舊版資料遷移(`%APPDATA%` 路徑不同,需另外設計)

## 整體架構

新增兩個檔案,不動專案其他結構:

```
scripts/build_installer/
├── installer.iss              # Inno Setup 設定 + 偵測舊版邏輯
├── build_release.ps1          # 一鍵腳本
├── ChineseTraditional.isl     # 繁體中文 Inno Setup 翻譯(vendored)
└── ChineseSimplified.isl      # 簡體中文 Inno Setup 翻譯(vendored)
```

產物:

```
build/installer/Genshin_Impact_Wish_Gacha_Analyzer-Setup-{version}.exe
```

`build/installer/` 加進 `.gitignore`。

## 元件設計

### 1. `scripts/build_installer/installer.iss`

Inno Setup 6 腳本。核心設定如下表,對齊舊版 `vue.config.js` 的精神,維持 perMachine 全機器安裝:

| 區段 / 項目 | 值 | 說明 |
|---|---|---|
| `AppId` | `{{` + 預先生成的固定 GUID + `}}` | 與舊版 electron-builder 的 GUID 完全獨立 |
| `AppName` | `Genshin Impact Wish Gacha Analyzer` | 同舊版 `productName` |
| `AppVersion` | 由 ISCC `/DMyAppVersion=...` 從外面傳入 | 從 `pubspec.yaml` 抓 |
| `AppPublisher` | `原神資訊站 Genshin Impact Info` | 同舊版 |
| `AppPublisherURL` | `https://genshininfo.reh.tw/` | 同舊版 author URL |
| `AppCopyright` | `Copyright (C) 2020-{當年} 原神資訊站 Genshin Impact Info` | 同舊版 |
| `DefaultDirName` | `{commonpf}\Genshin_Impact_Wish_Gacha_Analyzer` | perMachine:`C:\Program Files\Genshin_Impact_Wish_Gacha_Analyzer\` |
| `DefaultGroupName` | `Genshin Impact Wish Gacha Analyzer` | 開始選單分類,與 AppName 一致 |
| `PrivilegesRequired` | `admin` | perMachine 強制提權(同舊版 vue.config.js `perMachine: true`) |
| `DisableDirPage` | `no` | 允許使用者改安裝目錄(對應舊版 `allowToChangeInstallationDirectory: true`) |
| `SetupIconFile` | `..\windows\runner\resources\app_icon.ico` | 安裝檔本身的 icon |
| `UninstallDisplayIcon` | `{app}\genshin_impact_wish_gacha_analyzer.exe` | 「應用程式與功能」清單顯示的 icon |
| `Compression` | `lzma2/ultra` | 壓縮率最佳 |
| `SolidCompression` | `yes` | 同上 |
| `WizardStyle` | `modern` | 較新的 UI |
| `OutputDir` | `..\build\installer` | 相對於 `installer.iss` 位置 |
| `OutputBaseFilename` | `Genshin_Impact_Wish_Gacha_Analyzer-Setup-{#MyAppVersion}` | 含版本號 |
| `ArchitecturesInstallIn64BitMode` | `x64compatible` | 64-bit only |
| `VersionInfoVersion` / `VersionInfoProductVersion` | `{#MyAppVersion}` | 寫入 Setup.exe 二進位的 VersionInfo resource(FileVersion / ProductVersion);不設時 Windows 顯示 0.0.0.0 |

**`[Languages]` 區段**:
- English(`compiler:Default.isl`,Inno Setup 預設)
- Inno Setup 6 內建的 29 個官方語系(Arabic、Armenian、BrazilianPortuguese、Bulgarian、Catalan、Corsican、Czech、Danish、Dutch、Finnish、French、German、Hebrew、Hungarian、Italian、Japanese、Korean、Norwegian、Polish、Portuguese、Russian、Slovak、Slovenian、Spanish、Swedish、Tamil、Thai、Turkish、Ukrainian),透過 `compiler:Languages\*.isl` 引用
- 繁體中文(`ChineseTraditional.isl`,非官方,vendor 在 `scripts/build_installer/` 下)
- 簡體中文(`ChineseSimplified.isl`,非官方,vendor 在 `scripts/build_installer/` 下)

`[Code]` 內客製訊息(MsgBox)只翻譯 English / 繁中 / 簡中,其他語系 fallback 為英文。

**`[Tasks]` 區段**:
- `desktopicon` — 桌面捷徑(預設勾選)
- 開始選單捷徑為 Inno Setup 預設行為,無需額外宣告

**`[Files]` 區段**:
- 把 `..\build\windows\x64\runner\Release\*` 全部複製到 `{app}`,`recursesubdirs createallsubdirs ignoreversion`

**`[Icons]` 區段**:
- `{group}\Genshin Impact Wish Gacha Analyzer` → 主程式
- `{commondesktop}\Genshin Impact Wish Gacha Analyzer` → 主程式(僅在 desktopicon task 勾選時)

**`[Run]` 區段**:
- 安裝完成提供「立即啟動」勾選(`postinstall skipifsilent`)

#### 1.1 偵測並卸載舊版(`[Code]` 區段)

不需要使用者提供 PSChildName。改用自動掃描:

```
1. 列出 Uninstall 註冊表四個位置的所有子 key:
   - HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
   - HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall
   - HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
   - HKCU\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall

2. 每個 key 讀 DisplayName + UninstallString

3. 判定為「舊版」的條件(同時滿足):
   - DisplayName 含 'Genshin Impact Wish Gacha Analyzer'
   - 該 key 名稱不是新版自己的 AppId
   - UninstallString 不為空

4. 在 InitializeSetup() 內:
   - 若有命中 → 跳 MsgBox(MB_YESNO):
     「偵測到已安裝的舊版本 (Electron 版)，是否要先移除舊版本再繼續安裝新版本？」
     - 按是 → 逐一 ShellExec 呼叫舊版 uninstaller:
       - Verb: `''`(新版 Setup 本身已 admin,不需再提權)
       - 參數:'/S /allusers'(NSIS 靜默卸載 + 全機器)
       - 等待結束(SW_HIDE + ewWaitUntilTerminated)
     - 按否 → Result := False(中止新版安裝,不允許並存)

5. 沒命中 → Result := True,正常安裝
```

UninstallString 通常會包含引號路徑,呼叫前需要 `RemoveQuotes`。

### 2. `scripts/build_installer/build_release.ps1`

PowerShell 腳本,流程:

```
1. $ErrorActionPreference = 'Stop'

2. 讀 pubspec.yaml,regex 抓 version:
   - Pattern: ^version:\s*([^\s+]+)
   - 取第一組(去掉 build number,例如 1.0.0+1 → 1.0.0)
   - 抓不到 → 印錯誤、exit 1

3. 找 ISCC.exe(順序):
   a. HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1\InstallLocation
   b. HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1\InstallLocation
   c. ${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe
   d. $env:ProgramFiles\Inno Setup 6\ISCC.exe
   - 都找不到 → 印下載連結 https://jrsoftware.org/isdl.php + exit 1

4. flutter pub get
5. flutter build windows --release
6. New-Item build/installer -ItemType Directory -Force(若不存在)
7. & $isccPath /DMyAppVersion=$version scripts/build_installer/installer.iss
8. 印出產物完整絕對路徑

不做的事:
- flutter clean(讓 Flutter 自己處理增量)
- 跳過 hooks 或測試(commit 時 hook 會跑;這支腳本只負責打包)
- 任何 CLI 參數(完全自動)
```

## 資料流

```
[pubspec.yaml] ──版本號──┐
                          ↓
[build_release.ps1] ──┬─→ flutter build windows --release
                      │         ↓
                      │   build/windows/x64/runner/Release/
                      │         ↓
                      └─→ ISCC.exe /DMyAppVersion=... installer.iss
                                ↓
              build/installer/Genshin_Impact_Wish_Gacha_Analyzer-Setup-{version}.exe
```

執行期(使用者安裝):

```
使用者執行 Setup.exe
    ↓
Windows 跳 UAC(perMachine 強制提權)
    ↓ 按是
InitializeSetup() 掃描 Uninstall 註冊表
    ↓
有舊版? ──否──→ 正常安裝流程
    ↓ 是
    跳 MsgBox 詢問
    ↓
    按否 ──→ 中止
    按是 ──→ ShellExec()呼叫舊版 NSIS uninstaller /S /allusers
              (新版已 admin,不再跳 UAC)
              ↓
              卸載完成
              ↓
              繼續新版安裝流程
```

## 錯誤處理

| 情境 | 行為 |
|---|---|
| `pubspec.yaml` 抓不到 version | PowerShell 印錯誤、exit 1 |
| 沒裝 Inno Setup 6 | PowerShell 印下載連結、exit 1 |
| `flutter build` 失敗 | `$ErrorActionPreference = 'Stop'` 自動中止 |
| ISCC 編譯失敗 | 同上,PowerShell 退出非零 |
| 舊版 uninstaller 不存在(註冊表項殘留但檔案被刪) | ShellExec 失敗 → 繼續新版安裝(舊版已壞,讓新版蓋過去) |
| 使用者在 Setup 啟動的 UAC 按「否」 | Setup 整個被 Windows 終止,不會進入偵測舊版流程(由 Windows 處理,不在 Inno Setup 範圍) |

## 測試策略

無自動化測試,因為:
- 此設計純為 build 與 install 流程
- Inno Setup 與 PowerShell 沒有適合的單元測試框架
- 行為驗證需要實際在 Windows 上跑安裝

**手動驗證 checklist**(實作完成後跑一次):

1. **基本打包**
   - [ ] `.\scripts\build_installer\build_release.ps1` 一氣呵成,產出 `build/installer/Genshin_Impact_Wish_Gacha_Analyzer-Setup-1.0.0.exe`
   - [ ] 版本號跟 `pubspec.yaml` 一致

2. **乾淨安裝(沒裝過舊版的機器)**
   - [ ] 雙擊 Setup → 跳一次 UAC(perMachine 必跳) → 不跳偵測舊版訊息
   - [ ] 安裝目錄預設是 `C:\Program Files\Genshin_Impact_Wish_Gacha_Analyzer`
   - [ ] 桌面 + 開始選單捷徑都建立(全電腦,所有使用者可見)
   - [ ] 啟動 app 正常運作(flutter_rust_bridge DLL 正常載入)
   - [ ] 「應用程式與功能」清單顯示正確 DisplayName 與 icon

3. **有舊版的機器**
   - [ ] 雙擊 Setup → 跳 UAC → 跳出偵測訊息
   - [ ] 按「是」→ 舊版被靜默移除(不再跳第二次 UAC)→ 新版繼續安裝
   - [ ] 按「否」→ 安裝中止,舊版完整保留

4. **卸載新版**
   - [ ] 從「應用程式與功能」卸載乾淨
   - [ ] 安裝目錄被刪除
   - [ ] 桌面/開始選單捷徑被刪除

## 風險與已知限制

1. **舊版偵測仰賴 DisplayName 字串**:若有其他第三方工具 DisplayName 恰好包含 `Genshin Impact Wish Gacha Analyzer`,會被誤判。實務上極不可能,接受此風險。

2. **舊版 NSIS uninstaller 損壞**:若使用者手動刪除過安裝目錄,uninstaller `.exe` 也會跟著消失;ShellExec 會失敗,設計上「繼續安裝」是合理的(舊版已壞,讓新版蓋過去)。

3. **資料遷移未涵蓋**:舊版 `%APPDATA%\Genshin Impact Wish Gacha Analyzer\` 的祈願紀錄、設定不會自動搬到新版的 `path_provider` 路徑。日後若要做,屬於另一個 spec。

4. **AppId GUID 一旦發佈不能再改**:GUID 寫死於 `installer.iss`,變更會導致使用者無法升級(會被視為兩個應用程式)。實作時生成的 GUID 視為永久公開值。

## 開放議題

無。所有關鍵問題已在 brainstorming 階段釐清。
