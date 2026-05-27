# 解除安裝時可選擇移除使用者資料 — Design

- **日期：** 2026-05-27
- **狀態：** 已實作（含 debug 發現修正後的最終設計）
- **改動範圍：** `scripts/build_installer/installer.iss` 唯一檔（`.isl` 不動 — 見第 12.3 節決策記錄）

---

## 1. 動機

目前 Inno Setup 解除安裝流程只會清掉 `{app}` 安裝目錄的檔案，**完全不會碰** `%APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer\` 內的使用者資料。對絕大多數使用者這是合理預設（重裝可保留卡池記錄與設定），但缺少「徹底移除」的選項，使用者需要手動找到 `%APPDATA%` 目錄手動刪除。

本設計在解除安裝流程中插入一個 **預設選 No** 的 `MsgBox`，讓使用者明確選擇是否一併清除使用者資料；文案內列出將被刪除的目錄並警告不可復原。

## 2. 範圍與非目標

**範圍內：**
- Inno Setup uninstaller 的 `CurUninstallStepChanged(usUninstall)` 階段加一個 `MsgBox` 提供選項。
- 一個 Yes/No 選擇包覆全部使用者資料（卡池記錄、設定、HoYoWiki 快取、log）—— 不細分多個選項。
- 繁體中文、簡體中文、英文（fallback）三組文案，全部寫在 `installer.iss` 內 `[CustomMessages]` 段（**不放 `.isl`** — 見第 12.3 節）。

**非目標：**
- 不提供細分（祈願 / 設定 / 快取 各自獨立選擇）—— 多數使用者看不懂差異，UI 變雜。
- 不提供 `/REMOVEDATA` silent 開關 —— 個人桌面 app 沒有 CI / IT 部署用例，YAGNI。
- 不改 app 內任何 Dart / Rust 程式。
- 不改既有「新版 installer 偵測舊 Electron 版」的升級流程。
- 不補齊其他 30 種語系翻譯（走英文 fallback，與目前 installer 多語系覆蓋策略一致）。
- 不嘗試在 uninstaller 端建立自訂 Wizard 頁（見第 12 節決策記錄）。

## 3. 使用者資料位置

由 `lib/main.dart` 與 plugin 預設可知，所有本地累積的使用者資料都在 `getApplicationSupportDirectory()`：

```
%APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer\
  ├── gacha_data\             # 卡池記錄（SQLite / JSON）
  ├── hoyowiki_cache\         # HoYoWiki 圖像快取
  ├── shared_preferences.json # 主題、語言、UID 別名、隱私設定、視窗 state
  └── logs\                   # LogService 寫的 log 檔
```

`tw.reh` 來自 `windows/runner/Runner.rc` 的 `CompanyName`；`genshin_impact_wish_gacha_analyzer` 來自 `ProductName`。一次 `DelTree` 整個目錄就完整移除所有使用者資料。

註冊表：app 本身不寫使用者資料到註冊表；Inno Setup 自身 uninstall registry key 由內建流程清掉，本設計不需介入。

## 4. UI 流程

```
[使用者按下「解除安裝」]
   ↓
解除安裝確認 MsgBox（Inno Setup 內建：「您確定要完全移除...？」）
   ↓ Yes
[新] CurUninstallStepChanged(usUninstall) 階段彈出 MsgBox：
       ┌───────────────────────────────────────────────────────────┐
       │ 確認移除使用者資料                                          │
       ├───────────────────────────────────────────────────────────┤
       │ 是否要同時移除使用者資料？                                   │
       │                                                           │
       │ 將永久刪除位於以下目錄的所有內容：                            │
       │ C:\Users\<user>\AppData\Roaming\tw.reh\genshin_impact_...  │
       │                                                           │
       │ 包含卡池記錄、設定、快取與 log。此操作無法復原。              │
       │                                                           │
       │              [是]    [否(預設)]                              │
       └───────────────────────────────────────────────────────────┘
   ↓
解除安裝進度頁（Inno Setup 內建）開始
   ↓ (主程式檔案被卸載)
[新] CurUninstallStepChanged(usPostUninstall) 階段：
       若上一步使用者選 [是] → DelTree(%userappdata%\tw.reh\genshin_impact_wish_gacha_analyzer)
   ↓
完成 MsgBox（Inno Setup 內建：「My Program 已成功移除」）
```

**設計要點：**
- 預設按鈕為 [否]（`MB_DEFBUTTON2`），按 Enter 或關閉視窗 = 不刪資料 = 等同使用者原需求「預設不勾選」。
- MsgBox 內顯示 **expanded 絕對路徑**（透過 `ExpandConstant('{userappdata}\tw.reh\genshin_impact_wish_gacha_analyzer')`），讓使用者可直接複製貼到檔案總管核對，而非只看 `%APPDATA%\...` 字面。
- 選擇與執行分離：`usUninstall` 階段問、存 flag 到 module 變數；`usPostUninstall` 階段依 flag 執行 `DelTree`。中間穿插主程式檔案的解除安裝，確保 `DelTree` 時不會與主程式檔案的 file lock 衝突。
- silent 解除安裝（`/VERYSILENT`、`/SILENT`）：`MsgBox` 在 silent 模式自動回傳預設按鈕值，亦即 `IDNO`，flag = False，不刪資料。

## 5. 文案

### 5.1 [CustomMessages] keys

| Key | 用途 |
|---|---|
| `UninstallRemoveDataBody` | MsgBox 本文，`%1` 替換為 expanded 絕對路徑 |

> MsgBox 標題：使用 Inno Setup `MsgBox(..., mbConfirmation, ...)` 內建的系統 locale 標題（繁中 Windows 為「確認」、英文 Windows 為「Confirm」），不額外定義 key。

### 5.2 全部文案集中在 `installer.iss` 內 `[CustomMessages]` 段

採 Inno Setup 多語系標準 `langname.Key=` 寫法（見第 12.3 節決策記錄為何不放 `.isl`）：

```
[CustomMessages]
UninstallRemoveDataBody=Also remove user data?%n%nThis will permanently delete the contents of:%n%1%n%nincluding banner records, settings, caches and logs. This cannot be undone.
tradchinese.UninstallRemoveDataBody=是否要同時移除使用者資料？%n%n將永久刪除位於以下目錄的所有內容：%n%1%n%n包含卡池記錄、設定、快取與 log。此操作無法復原。
simpchinese.UninstallRemoveDataBody=是否要同时移除用户数据？%n%n将永久删除位于以下目录的所有内容：%n%1%n%n包含卡池记录、设定、缓存与 log。此操作无法复原。
```

第一行（無 prefix）= 所有其他語系的 default fallback；後兩行 = 該語系專屬翻譯，覆寫 default。`.isl` 檔**不動**。

> 用詞約定：提到使用者本地累積的抽卡資料時用「卡池記錄」（非「祈願記錄」），記憶見 [[feedback_terminology_gacha_records_naming]]。

## 6. 刪除清單與機制

- **目標路徑：** `{userappdata}\tw.reh\genshin_impact_wish_gacha_analyzer\`（含所有子檔案、子目錄）。
- **指令：**
  ```pascal
  DelTree(ExpandConstant('{userappdata}\tw.reh\genshin_impact_wish_gacha_analyzer'), True, True, True);
  ```
  三個 `True` 參數：刪除目錄本身、刪除其下檔案、刪除其下子目錄。
- **時機分工：**
  - `CurUninstallStepChanged(usUninstall)` 階段：彈 `MsgBox` 並把使用者選擇存入 module 變數 `ShouldRemoveUserData`。
  - `CurUninstallStepChanged(usPostUninstall)` 階段：若 `ShouldRemoveUserData = True` 則執行 `DelTree`。
- **不動：** 註冊表、其他使用者目錄（例如 Documents、Pictures —— app 不會寫到那裡）。

## 7. Pascal Script 結構

```pascal
[Code]
var
  ShouldRemoveUserData: Boolean;

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

實作備註：
- `MsgBox` 的視窗標題由 Inno Setup 依 `mbConfirmation` 自動帶系統 locale 對應文字（繁中 Windows 為「確認」、英文 Windows 為「Confirm」等），不額外設定。
- `ShouldRemoveUserData` 是 unit-level 變數，依 Inno Setup 慣例會在 uninstaller process 啟動時初始化為 `False`（Pascal Boolean 預設值），符合「預設不刪」語意。
- `Log` 是 Inno Setup 內建函式，會把訊息寫入 uninstall log（透過 `/LOG=...` 參數產生，或 `unins000.dat` 同目錄的 setup log）。

## 8. 邊界處理

| 情境 | 行為 |
|---|---|
| 使用者選 No（或按 Enter 走預設 No） | flag = False；`usPostUninstall` 階段什麼都不做；`%APPDATA%` 完整保留 |
| 使用者按 Esc | `MB_YESNO` 無 Cancel 按鈕，Esc 不會關閉 MsgBox，使用者必須主動選 Yes 或 No |
| 使用者選 Yes | flag = True；`usPostUninstall` 階段執行 `DelTree` |
| 資料目錄不存在 | `DelTree` 對不存在路徑回傳 True（無害），靜默通過 |
| `/VERYSILENT` 或 `/SILENT` 解除安裝 | Inno Setup `MsgBox` 在 silent 模式自動回傳預設按鈕值 = IDNO → flag = False，不刪資料 |
| `DelTree` 失敗（殘留 file lock 等） | Inno `DelTree` 回 False 不擲例外；用 `Log()` 寫入 setup log 但不阻擋解除安裝完成 |
| 升級流程（新版蓋過舊版）| 不觸碰本設計 —— 升級走 `[Setup]` 流程，根本不執行 uninstaller |
| 解除安裝過程被使用者中途取消 | `CurUninstallStepChanged` 後續階段不會被呼叫 → `usPostUninstall` 不執行 → 不刪資料 |

## 9. i18n 範圍

- 完整翻譯：繁體中文、簡體中文、英文，**全部寫在 `installer.iss` 內 `[CustomMessages]` 段**（見第 5.2 節）。
- 其他 30 種語系：fallback 到 `installer.iss` 內無 prefix 的 default（英文）。
- 理由：installer 文案變動頻率低；Inno Setup uninstaller 階段的 `CustomMessage()` 只看得到 `installer.iss` 內的 `[CustomMessages]`，看不到 `.isl` 內的（見第 12.3 節決策記錄）。

## 10. 測試策略

無自動化測試（Inno Setup script 沒有 unit test framework）。**人工驗收 checklist**（搬到 plan 階段執行）：

1. 編譯 installer → 安裝 → 跑 app 至少一次 → 確認 `%APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer\` 內有資料。
2. 解除安裝 → MsgBox 出現後選「否」（或直接 Enter 走預設）→ 完成 → 確認 `%APPDATA%` 目錄與內容仍在。
3. 重新安裝 → 確認舊資料能被讀回（卡池記錄、設定）。
4. 解除安裝 → MsgBox 選「是」→ 完成 → 確認 `%APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer\` 目錄已不存在。
5. 解除安裝 → MsgBox 出現後直接按 Enter（不主動選按鈕，走預設 No）→ 確認資料仍在。
   - 同時驗證：按 Esc 鍵應**無反應**（`MB_YESNO` 沒有 Cancel，Esc 不會關閉視窗）。
6. `unins000.exe /VERYSILENT` → 確認資料仍在（silent 走預設不刪）。
7. 語系驗收：分別在繁中、簡中、英文系統 locale 下執行步驟 4，確認 MsgBox body 文案為對應語系（標題由系統 locale 自動提供 `Confirm` / `確認` 等）。
8. 路徑顯示驗收：MsgBox body 內顯示的路徑為 expanded 絕對路徑（如 `C:\Users\foo\AppData\Roaming\tw.reh\genshin_impact_wish_gacha_analyzer`），不含未 expand 的 `{userappdata}` 或 `%APPDATA%` 字面。

## 11. 風險

- **多語系 fallback 體驗：** 其他語系（日文、韓文、俄文…）使用者會看到英文文案。可接受 — Inno Setup 本身 `Default.isl` 對某些 key 也是英文 fallback。
- **MsgBox title 是否完全本地化：** Inno Setup `mbConfirmation` MsgBox 的 title 由 Windows 系統提供（依系統 locale），不直接吃 Inno Setup 的 `[Languages]` 設定。在繁中 Windows 上會顯示「確認」、英文 Windows 顯示「Confirm」，已足夠語意明確；body 文案則完全由 `[CustomMessages]` 控制。
- **DelTree 失敗無 UI 反饋：** 解除安裝完成 MsgBox 不會告訴使用者「資料其實沒清乾淨」。可接受 — 此情境罕見（需檔案 lock 且 Inno Setup 自身 uninstall 也未失敗），使用者可手動清掉殘留目錄。若實作後發現此情境頻繁，再加 MsgBox 警告。
- **無自動化驗證：** 解除安裝行為只能人工點。Plan 階段把 checklist 寫進 PR template，必要時附實測截圖。

## 12. 決策記錄

### 12.1 為何不用 Wizard 自訂頁

初版設計嘗試用 Wizard 自訂頁（checkbox + 二次確認 MsgBox），spec self-review 階段查 Inno Setup 官方文件（`/jrsoftware/issrc`）確認：

- Inno Setup 提供 `CreateInputOptionPage` 等 wizard 頁 API **僅限 installer 端的 `InitializeWizard`**，uninstaller 沒有對應 API。
- Uninstaller 的 lifecycle hook 只有 `InitializeUninstall` / `CurUninstallStepChanged` / `DeinitializeUninstall`，這三個都只能跳 `MsgBox` 或執行命令。
- 官方文件對「解除安裝時詢問是否刪除使用者資料」這個完全相同的需求，直接示範用 `CurUninstallStepChanged(usPostUninstall)` 跳 `MsgBox`。

若要強行加 wizard 頁，需重寫 `UninstallProgressForm` 並注入自訂 `TPanel` + `TCheckBox`，屬於 hack 性質，與未來 Inno Setup 版本升級的相容性差，為 yak shaving。改採 MsgBox 形式（即官方推薦作法）。

### 12.2 為何單 MsgBox 而非雙 MsgBox 二次確認

最終 MsgBox 設計：
- 單一 MsgBox 同時問「是否移除？」+ 列出將刪除路徑 + 警告不可復原 + `MB_DEFBUTTON2` 預設 No。
- 仍滿足使用者原需求「預設不勾選」（透過預設按鈕 = No 達成）。
- 文案內明示路徑與「無法復原」，符合知情同意。
- 比雙 MsgBox（先問選項、Yes 再二次確認）少一個點擊，對有意刪資料的使用者較友善；同時 `MB_DEFBUTTON2` + 文案警告對怕誤刪的使用者已提供足夠防呆。

### 12.3 為何翻譯全放 `installer.iss` 而非 `.isl`

實作後 debug 發現：把 `UninstallRemoveDataBody=...` 翻譯寫在 `ChineseTraditional.isl` / `ChineseSimplified.isl` 的 `[CustomMessages]` 段內，**對 uninstaller 無效**。雖然 ISCC compile 成功、`ActiveLanguage()` 在 install 階段正確、wizard 是繁中，但解除安裝時 `CustomMessage('UninstallRemoveDataBody')` 不論安裝時選什麼語言都只回傳 `installer.iss` 內無 prefix 的英文 default。沒有 exception，代表 key 存在但語言版本沒被打包進 `unins000.dat`。

把翻譯改用 `tradchinese.UninstallRemoveDataBody=...` / `simpchinese.UninstallRemoveDataBody=...` 寫在 `installer.iss` 後立刻生效。

結論：**Inno Setup 不把 `.isl` 內的 `[CustomMessages]` 條目打包到 uninstaller**。所有 uninstaller 階段要呼叫 `CustomMessage()` 的 keys 都必須在 `installer.iss` 用 `langname.Key=` 寫齊。`.isl` 內的 `[CustomMessages]` 仍對 installer 階段有效（如 `[Icons]` `{cm:UninstallProgram,...}`、`[Run]` `{cm:LaunchProgram,...}` 等 Inno 自帶 keys），所以 `.isl` 內**既有**條目不要動，只是不要把 uninstaller-facing 的新 keys 加進去。

此限制與本 repo `installer.iss` 既有的 `InitializeSetup()` 用 `ActiveLanguage()` + hardcoded 字串而非 `CustomMessage()` 的設計一致 —— 原作者已避開此限制。

記憶見 [[feedback_inno_setup_uninstaller_custommessages_in_iss]]。

## 13. 不在本 spec 範圍

- App 內部的「在程式裡提供清除資料按鈕」—— 與本設計獨立，未來想做可另開 spec。
- 主動把既有 `app_zh.arb` 內混用的「祈願記錄/紀錄」統一成「卡池記錄」—— 屬 i18n 一致性整理任務，與本設計獨立。

---

**參考檔案：**
- `scripts/build_installer/installer.iss`
- `scripts/build_installer/ChineseTraditional.isl`
- `scripts/build_installer/ChineseSimplified.isl`
- `windows/runner/Runner.rc`（`CompanyName=tw.reh`、`ProductName=genshin_impact_wish_gacha_analyzer`）
- `lib/main.dart`（`getApplicationSupportDirectory()` 使用位置）

**外部文件：**
- Inno Setup 6.6 文件 / `/jrsoftware/issrc` Pascal Script lifecycle 事件範例
