# 介面隱私模式：遮蔽 UID 設計

**日期**：2026-05-27
**狀態**：待實作（spec 已通過 brainstorming，等待 plan 撰寫）

## 動機

實況主或螢幕分享情境下，App 主畫面的 AppBar 與帳號管理清單會直接顯示完整 UID，鏡頭意外帶到時會曝光帳號識別碼。提供一個可手動切換的「介面隱私模式」，將 UI 上的 UID 顯示為前 3 碼加 `x` 遮蔽（例如 `123xxxxx`），不影響資料檔與分享圖的獨立隱私設定。

## 範圍與決策

| 項目 | 決策 |
|---|---|
| 遮蔽欄位 | 僅 UID。Alias、暱稱、伺服器等不在範圍 |
| 遮蔽樣式 | 前 3 碼 + `x` 遮蔽其餘，**沿用既有 `maskUidForShare()`** |
| 切換入口 | 僅設定頁 Switch（不做 AppBar 快捷鈕、不做鍵盤快捷鍵）|
| 預設值 | OFF（關閉）|
| 未來擴充 | 設定欄位先 `bool`，未來真要加其他欄位再升 `enum`（bool → enum 是 trivial migration，依 CLAUDE.md YAGNI）|

### 套用範圍

| 顯示點 | 套用 | 原因 |
|---|---|---|
| AppBar 帳號鈕（`uid_indicator.dart:151,153`）| ✅ | 主畫面常駐，最易曝光 |
| AppBar 帳號菜單副標籤（`uid_indicator.dart:253`）| ✅ | 常駐 UI 的延伸 |
| 設定頁帳號管理清單（`account_management.dart:65-77`）| ✅ | 使用者要求：直播時不慎開到設定頁也安全 |
| 刪除帳號確認框（`settings_page.dart:631`）| ❌ | 要使用者打 UID 確認刪除，遮蔽會增加刪錯風險 |
| 分享卡（`share_card.dart:247`）| ❌ | 已有獨立 `showFullUid` 設定，互不干擾 |
| 分享圖 dialog（`share_image_dialog.dart`）| ❌ | 同上 |
| 匯出帳號 JSON（`accounts_export.dart`）| ❌ | 資料檔不能壞 |
| Log 匯出檔 | ❌ | log 已用 `sanitizeUid` 自有遮蔽策略 |

## 架構

```
SettingsStorage (SharedPreferences)
   └── key: maskUidInUi (bool, default false)
SettingsNotifier (Riverpod)
   ├── bool maskUidInUi
   └── setMaskUidInUi(bool)
         ↓ ref.watch(settingsProvider)
UI 顯示點
   └── displayUid(uid, mask: s.maskUidInUi)
         ├── true  → maskUidForShare(uid)    // 既有 helper
         └── false → uid                     // 原樣
```

## 新增 / 變更檔案

### 新增

#### `lib/utils/uid_display.dart`

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/share_uid_mask.dart';

/// UID 顯示工具：依介面隱私設定，回傳遮蔽後或原樣的 UID。
///
/// [mask] 由 [SettingsNotifier.maskUidInUi] 提供。遮蔽邏輯沿用
/// [maskUidForShare]（前 3 碼 + `x` 遮蔽其餘），與分享圖政策一致。
String displayUid(String uid, {required bool mask}) =>
    mask ? maskUidForShare(uid) : uid;
```

### 變更

#### `lib/services/settings_storage.dart`

- 新增 SharedPreferences key 常數 `_kMaskUidInUi = 'mask_uid_in_ui'`
- `load()` 讀取，預設 `false`（缺 key 視為 false，向後相容）
- `save()` 寫入

#### `lib/state/settings.dart`

- `Settings` 加入 `final bool maskUidInUi;`（建構式預設 `false`）
- `copyWith` 加參數
- `SettingsNotifier` 加 `Future<void> setMaskUidInUi(bool value)`，內部呼叫 `SettingsStorage.save()` 後 `state = state.copyWith(...)`
- **Log 埋點**：`Logger('app.settings').info('maskUidInUi toggled', value)`

#### `lib/widgets/uid_indicator.dart`

- 行 151/153：AppBar 帳號鈕顯示處改用 `displayUid(uid, mask: settings.maskUidInUi)`
- 行 253：菜單副標籤同上
- Alias 混合場景：`'$alias ($uid)'` → `'$alias (${displayUid(uid, mask: ...)})'`

#### `lib/widgets/cards/account_management.dart`

- 行 65-77：清單 row 顯示 UID 處改用 `displayUid`

#### `lib/pages/settings_page.dart`

- 在 Appearance section 後、Language section 前，新增 **Privacy** section
- Section 用既有 `SettingsSection` 元件
- 內含一個 `SwitchListTile`：title = `L10n.of(context).settingsMaskUidInUi`，subtitle = `L10n.of(context).settingsMaskUidInUiHint`
- 行 631 刪除確認框維持原樣（不套用 `displayUid`）

#### i18n（**非空殼 ARB**：`zh`、`zh_Hans`、`en`、`es`、`fr`、`ja`、`pt_BR`、`th`、`vi` 共 9 個）

新增 3 個 key。翻譯流程依 memory `feedback_i18n_starts_from_zh.md`：先寫繁中 (`zh`)，以中文為基準翻其他 8 種；空殼 ARB 不動，留給 Crowdin pipeline。

| key | zh 範本 | en 範本 |
|---|---|---|
| `settingsPrivacySectionTitle` | 隱私 | Privacy |
| `settingsMaskUidInUi` | 遮蔽介面中的 UID | Mask UID in interface |
| `settingsMaskUidInUiHint` | 開啟後，畫面與帳號清單中的 UID 會以前 3 碼搭配 `x` 顯示（例如 `123xxxxx`），適合實況或螢幕分享時使用。分享圖、匯出檔案、刪除確認框不受影響。 | When on, UIDs in the interface and account list display the first 3 digits with the rest masked (e.g. `123xxxxx`). Useful for streaming or screen sharing. Share images, exported files, and delete confirmation dialogs are not affected. |

實作時依術語表 (`docs/術語表.md`)、既有翻譯風格與各 locale 慣用語完成其他 7 語。

## 不變更項目

- `lib/services/log_sanitize.dart` 的 `sanitizeUid`：log 場景維持「前 3 + 後 3 + 星號」格式。UI 與 log 策略不一致是預期的——log 是稽核情境，需要末碼幫忙交叉比對。
- `lib/services/share_uid_mask.dart`：純函式 helper，不動。
- `lib/services/accounts_export.dart`：匯出資料檔不受 UI 設定影響。
- `lib/models/share_image_options.dart` 的 `showFullUid`：分享圖獨立設定，不繫結 `maskUidInUi`。

## 測試策略

| 類型 | 檔案 | 涵蓋 |
|---|---|---|
| Unit | `test/utils/uid_display_test.dart` | `mask: true` 結果等於 `maskUidForShare(uid)`；`mask: false` 結果等於原 uid；邊界（空字串、短 UID < 3 碼）|
| Unit | `test/services/settings_storage_test.dart`（既有檔擴充）| `maskUidInUi` 預設 false；寫入讀出循環；缺 key 時讀為 false |
| Unit | `test/state/settings_test.dart`（既有檔擴充）| `setMaskUidInUi(true)` 後 state 更新、`SettingsStorage.save` 被呼叫一次 |
| Widget | `test/widgets/uid_indicator_test.dart`（既有檔擴充或新建）| mask 開啟時 AppBar 帳號鈕顯示 `123xxxxx`；關閉時顯示完整 UID；alias 混合場景顯示 `Alias (123xxxxx)` |
| Widget | `test/widgets/cards/account_management_test.dart`（既有檔擴充或新建）| mask 開啟時清單行顯示遮蔽 UID；點擊刪除按鈕仍能進入確認流程（確認框內顯示完整 UID）|
| Widget | `test/pages/settings_page_test.dart`（既有檔擴充）| Privacy section 存在；切換 Switch 時呼叫 `setMaskUidInUi`；Switch 顯示狀態正確反映 settings |

### Manual smoke（依 CLAUDE.md「UI 變更要實機驗證」）

依 memory `feedback_perf_check_release_first.md`，跑 **release build**：

1. 預設狀態：AppBar / 帳號清單顯示完整 UID。
2. 進入設定頁，切到 Privacy section，開啟 toggle。
3. AppBar 帳號鈕、菜單、帳號管理清單三處 UID 立即變成 `123xxxxx` 格式。
4. 進入分享圖 dialog，確認分享圖預覽 **不受影響**（仍依 `showFullUid` 設定）。
5. 點刪除帳號，確認對話框 **顯示完整 UID**（不遮蔽）。
6. 關閉 App 再開：toggle 狀態正確還原。

## 提交前品質檢查（依 CLAUDE.md）

實作完成後執行：

1. `dart format lib/ test/`
2. `flutter analyze` → 必須 `No issues found!`
3. `flutter test` → 必須 `All tests passed!`

## 不在此 spec 範圍

- AppBar 快捷鈕 / 全域鍵盤快捷鍵切換（已在 brainstorming 排除）
- 遮蔽 alias、暱稱、其他敏感欄位（未來擴充，需另開 spec）
- 匯出 JSON / log 內容遮蔽（不在此功能目標）
- 自訂遮蔽碼數（YAGNI）
- 升級 `bool maskUidInUi` 為 `PrivacyConfig` 物件（YAGNI）

## 風險與緩解

| 風險 | 緩解 |
|---|---|
| 既有的 share image `showFullUid` 與 `maskUidInUi` 名稱相近，使用者可能混淆 | i18n hint 明確標示「分享圖不受此設定影響」 |
| 設定頁加 section 可能影響首幀效能（依 memory 既有議題）| 新 section 只多一個 `SwitchListTile`，影響可忽略；release build smoke 確認 |
| `displayUid` 與既有 `sanitizeUid` 名稱相近 | docstring 清楚標示用途差異（UI 顯示 vs log 脫敏）|
