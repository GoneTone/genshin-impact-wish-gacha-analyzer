# 升級 package_info_plus 9.0.1 → 10.1.0 設計

- 日期：2026-05-22
- 目標：在不破壞功能的前提下，將 `package_info_plus` 從 `^9.0.1` 升至 `^10.1.0`。

## 背景與現況

- 全專案僅 `lib/main.dart:68` 使用此套件，呼叫 `PackageInfo.fromPlatform()` 讀取
  `.version` / `.buildNumber`，用於 `app.startup` log 與 `app_info.dart` 的版本 override。
- pubspec 約束：`package_info_plus: ^9.0.1`，lock 鎖在 `9.0.1`。
- 本機環境：Flutter 3.41.9（stable）、Dart 3.11.x。
- 目標平台：僅 `windows/`（無 iOS/macOS/Android 目錄）。

## 變更範圍

### 程式碼：零變更

官方 changelog（pub.dev）確認 9.0.0 → 10.1.0 之間 **`PackageInfo.fromPlatform()`
與 `version`/`buildNumber` 欄位均無 API 變更**。使用端不需修改。

### pubspec.yaml：一行

```diff
- package_info_plus: ^9.0.1
+ package_info_plus: ^10.1.0
```

沿用專案既有 caret 風格。

## 相容性評估

| 項目 | v10.0.0 需求 | 本專案 | 結論 |
|------|-------------|--------|------|
| Dart SDK | 3.11.0 | 3.11.x | ✅ 滿足 |
| Flutter | 3.41.6 | 3.41.9 | ✅ 滿足 |
| iOS 最低 | 13.0 | 無 iOS 平台 | 無關 |
| macOS 最低 | 10.15 | 無 macOS 平台 | 無關 |
| win32 | 6.0.0 | 目前 5.15.0（transitive） | ⚠️ 見下 |

> v10.1.0 將 Dart 需求放寬至 3.10、Flutter 3.38.1，本專案皆已超過。

## 主要風險：win32 transitive 連鎖

`win32` 由三個套件相依：

- `package_info_plus`（本次升級對象，10.0.0 起要求 win32 **6.0.0**）
- `device_info_plus 11.5.0`
- `win32_registry 2.1.0`

win32 5.15.0 → 6.0.0 為 major bump。若 `device_info_plus` 或 `win32_registry`
不接受 win32 6.x，`flutter pub get` 將無法解出依賴。

### 處理原則

1. 先**只改 `package_info_plus` 一行**，跑 `flutter pub get`。
2. 若乾淨解出 → 直接進入驗證流程。
3. 若報依賴衝突 → **停下來，先把衝突細節與建議的連帶升級版本回報給使用者，
   等其拍板再動**（使用者決策：「先回報再決定」）。

## 驗證流程（對齊 CLAUDE.md 品質門檻）

1. `flutter pub get` — 須成功解出依賴。
2. `dart format lib/ test/`（不對 `.` 跑）。
3. `flutter analyze` — 須輸出 `No issues found!`。
4. `flutter test` — 須輸出 `All tests passed!`。
5. `flutter run`（Windows）啟動，從 log 確認
   `app start vX.Y.Z+N ...` 版本號正常印出，App 可正常運作。

## 不做的事（YAGNI）

- 不順手升級其他無關套件。
- 不為「未來可能用到」的 PackageInfo 欄位加程式碼。
- 不主動 git push。
