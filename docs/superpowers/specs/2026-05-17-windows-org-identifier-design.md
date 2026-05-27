# Windows 組織識別改名 (com.example → tw.reh)

日期：2026-05-17
狀態：設計已核可，待實作

## 背景

專案由 `flutter create` 建立時未指定 `--org`，Windows runner 沿用 Flutter 預設佔位
組織名 `com.example`。`path_provider_windows` 的 `getApplicationSupportDirectory()`
會以 exe version-info 資源中的 `CompanyName` 組出資料目錄
`%APPDATA%\<CompanyName>\<ProductName>\`，因此目前 logs / 帳號 / 設定都落在
`…\Roaming\com.example\genshin_impact_wish_gacha_analyzer\`。

本專案目前**僅有 `windows/` 一個平台**（無 android/ios/macos/linux），
app 尚未發布，舊目錄資料為測試用、可捨棄。

## 目標

把 Windows app 的組織識別改為 `tw.reh`，並更新版權顯示字串為 `GoneTone`。

## 變更範圍

僅修改 `windows/runner/Runner.rc`：

| 行 | 欄位 | 改前 | 改後 |
|---|---|---|---|
| L92 | `CompanyName` | `"com.example"` | `"tw.reh"` |
| L96 | `LegalCopyright` | `Copyright (C) 2026 com.example. All rights reserved.` | `Copyright (C) 2026 GoneTone. All rights reserved.` |

## 連帶影響（預期內、已確認可接受）

- 資料目錄路徑改為 `%APPDATA%\Roaming\tw.reh\genshin_impact_wish_gacha_analyzer\`，
  logs / 帳號 / 設定從空目錄重新開始。**不需要遷移邏輯**（決策：app 未發布，
  舊資料為測試垃圾）。
- `Runner.rc` 為 build 時編入 exe 的資源，須 **rebuild Windows app** 才會生效，
  hot reload / hot restart 無效。

## 不在範圍

- 無 android/ios/macos/linux 平台，無其他 organization 設定。
- `rust/src/ca.rs:73` 的 `OrganizationName, "GIWA PoC"` 為自簽憑證 O 欄位，
  與 app 組織識別無關，不變更。
- 不加任何資料遷移程式碼（YAGNI；app 未發布）。

## 驗證

1. 修改 `Runner.rc` 兩行。
2. Rebuild 並啟動 Windows app。
3. 透過設定頁「開啟 logs 資料夾」按鈕（或檔案總管）確認新路徑
   `%APPDATA%\Roaming\tw.reh\genshin_impact_wish_gacha_analyzer\logs\` 被建立。
4. 提交前品質檢查照常跑（無 Dart 變更，預期不受影響）：
   `dart format lib/ test/` → `flutter analyze`（No issues found!）→
   `flutter test`（All tests passed!）。
