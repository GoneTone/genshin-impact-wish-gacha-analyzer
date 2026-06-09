# 匯入／匯出失敗原因在地化設計

## 背景與目標

使用者回報「匯入資料失敗」時跳出的訊息是英文。追根究柢：外層「匯入失敗：{reason}」（`settingsImportFailed`）本身有在地化，但 `{reason}` 是由底層硬編碼英文 `FormatException` 的 `.message`／平台 IO 例外的 `.toString()` 直接帶入的，所以前綴是使用者語言、原因卻是英文。匯出失敗（`settingsExportFailed(e.toString())`）同樣中招。

涉及的英文來源：

- `lib/services/accounts_import.dart`：`'Invalid JSON'`、`'Top-level value must be an object'`、`'Failed to parse: $e'`
- `lib/models/accounts_bundle.dart`：`'Missing or invalid "schema_version"'`、`'Unsupported schema version: $version...'`、`'Missing or invalid "accounts" array'`、`'accounts[$i] must be an object'`、`'accounts[$i]: $e'`、`'Duplicate UID in accounts: ...'`
- `lib/pages/settings_page.dart`：匯入檔案讀取失敗與匯出失敗時直接把平台例外的 `toString()` 當原因顯示（英文 `FileSystemException` 等）

本設計把這些**會顯示給使用者的失敗原因**改為在地化，採**分桶**策略。

**成功條件**

- 匯入／匯出失敗時，SnackBar／結果 dialog 顯示的原因為使用者語言，無殘留英文。
- 可行動的特例（檔案由較新版本匯出）給出明確指引（請更新 App），與「格式不正確」一般失敗區隔。
- 英文技術細節不丟失：保留在 log（既有 `_log.warning`／`Logger.severe`，並補上目前缺漏的匯入讀檔失敗那條 log）。
- `fvm flutter analyze` 全綠、`fvm flutter test` 全綠。

## 決策摘要

| 面向 | 決策 |
|------|------|
| 呈現策略 | 分桶：可行動原因獨立成有意義訊息，其餘解析錯誤收斂成一桶「格式不正確或已損毀」，IO 讀／寫失敗各一桶 |
| 在地化層級 | 在 **UI 層**依「捕捉到的例外型別」挑在地化文案；底層 `FormatException` 的英文訊息保留，從此**只供 log 與測試**，不再進 UI |
| 特例辨識 | 只為「版本過新」加一個專屬例外型別 `UnsupportedSchemaVersionException`，讓 UI 能與一般 malformed 區隔；不引入錯誤分類 enum（YAGNI） |
| wrapper 重用 | 重用既有 `settingsImportFailed(reason)`／`settingsExportFailed(error)`，只替換帶入的原因字串；不新造外層 key |
| 版本訊息 | 版本過新訊息**不帶版本號 placeholder**（可行動指引不需數字，少一個翻譯欄位） |
| 新增 ARB key | 4 個 reason key（見下表） |
| 翻譯範圍 | 先寫 `app_zh.arb`（來源），翻 `app_en.arb` 及已有實體翻譯的語系；空殼 ARB 留給 Crowdin pipeline；用詞對齊 `docs/術語表.md` |

## 設計

### 1. `lib/models/accounts_bundle.dart`：新增可辨識的版本例外

新增 top-level 例外型別（附一行 `///` dartdoc）：

```dart
/// 匯入檔的 schema 版本高於目前 App 支援版本時拋出，供 UI 給出「請更新 App」指引。
class UnsupportedSchemaVersionException implements Exception {
  /// 建立 [UnsupportedSchemaVersionException]。
  const UnsupportedSchemaVersionException(this.version);

  /// 匯入檔宣告的 schema 版本（高於 [AccountsBundle.currentSchemaVersion]）。
  final int version;
}
```

把原本的「版本過新」分支：

```dart
if (version > currentSchemaVersion) {
  throw FormatException('Unsupported schema version: $version. Please update the app.');
}
```

換成：

```dart
if (version > currentSchemaVersion) {
  throw UnsupportedSchemaVersionException(version);
}
```

其餘 `FormatException`（schema_version 缺漏、accounts 非陣列、accounts[i] 非物件、Duplicate UID 等）**全部不動**——它們歸到「格式不正確」這一桶，英文訊息續供 log／測試。

### 2. `lib/services/accounts_import.dart`：讓版本例外原樣上拋

`importAccounts` 內包住 `AccountsBundle.fromJson` 的 try/catch（現為 `on FormatException { rethrow }` + 泛用 `catch (e, st)` 包成 `FormatException('Failed to parse: $e')`）要先攔 `UnsupportedSchemaVersionException` 原樣 rethrow（先 log），避免被泛用 catch 吞成 `FormatException`：

```dart
try {
  return AccountsBundle.fromJson(raw);
} on UnsupportedSchemaVersionException catch (e) {
  _log.warning('import failed: unsupported schema version ${e.version}');
  rethrow;
} on FormatException catch (e) {
  _log.warning('import failed: ${e.message}');
  rethrow;
} catch (e, st) {
  _log.warning('import failed: parse error', e, st);
  throw FormatException('Failed to parse: $e');
}
```

`importAccounts` 對外契約變為：可能拋 `UnsupportedSchemaVersionException`（版本過新）或 `FormatException`（其餘 malformed）。

### 3. `lib/pages/settings_page.dart`：三個失敗點停止把英文丟進 UI

三處都不再把 `e.message`／`e.toString()` 當原因，改帶在地化字串：

**(a) 匯入檔案讀取失敗**（現 `catch (e)` → `l.settingsImportFailed(e.toString())`，且**目前無 log**）：

```dart
} catch (e, st) {
  Logger('accounts.io').warning('import: read file failed', e, st);
  if (!ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(content: Text(l.settingsImportFailed(l.importReasonUnreadable))),
  );
  return;
}
```

**(b) `importAccounts` 失敗**（現單一 `on FormatException` → `l.settingsImportFailed(e.message)`）改為依型別分桶：

```dart
final AccountsBundle bundle;
try {
  bundle = importAccounts(text);
} on UnsupportedSchemaVersionException {
  if (!ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(content: Text(l.settingsImportFailed(l.importReasonUnsupportedVersion))),
  );
  return;
} on FormatException {
  if (!ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(content: Text(l.settingsImportFailed(l.importReasonInvalidFormat))),
  );
  return;
}
```

（底層英文細節已於 `importAccounts` 內 `_log.warning`，不需在 UI 重複 log。）

**(c) 匯出失敗**（現 `l.settingsExportFailed(e.toString())`，已有 `Logger.severe`）：

```dart
message: l.settingsExportFailed(l.exportReasonWriteFailed),
```

### 4. ARB：4 個新 reason key（分桶）

| key | 繁中（`app_zh.arb`，來源） | 用途 |
|---|---|---|
| `importReasonInvalidFormat` | 檔案格式不正確或已損毀 | 所有解析／格式錯誤（含缺欄位、結構錯誤、重複 UID） |
| `importReasonUnsupportedVersion` | 此檔案由較新版本的 App 匯出，請先更新 App 後再匯入 | 版本過新（可行動） |
| `importReasonUnreadable` | 無法讀取檔案 | 匯入時讀檔 IO 失敗 |
| `exportReasonWriteFailed` | 無法寫入檔案，請確認儲存位置與權限 | 匯出 IO 失敗 |

- 每個 key 附 `@key` 的 `description`，說明使用情境（供翻譯者理解）。
- 先寫 `app_zh.arb`，再以中文為基準翻 `app_en.arb` 及其餘**已有實體翻譯**的語系；空殼 ARB 不碰（留給 Crowdin pipeline）。
- 用詞對齊 `docs/術語表.md`（匯入／匯出等）。

### 5. 測試

- `test/models/accounts_bundle_test.dart`：把「版本過新」那條從斷言 `FormatException`（含 `'Unsupported schema version'` 訊息）改為斷言 `UnsupportedSchemaVersionException`，並驗 `.version`。其餘 `FormatException` 案例不動。
- `test/services/accounts_import_test.dart`：若有版本相關案例，同步改為斷言 `UnsupportedSchemaVersionException`；malformed 案例維持斷言 `FormatException`（契約不變）。
- 新增涵蓋：`importAccounts` 對版本過新檔案拋 `UnsupportedSchemaVersionException(version)`（型別 + version 值）。

## 不在範圍

- `lib/pages/settings_page.dart` 的 `Text('Developed by ')`（英文）與 `semanticLabel: '旋風之音 GoneTone'`（中文）——使用者本次只要修匯入／匯出原因。
- 分頁 `/`、分隔符 `·`／`・`、括號等純符號。
- 只進 log 的技術性錯誤（`StateError('toByteData returned null')`、FFI `Exception('unexpected arr length...')`）——不該也不需在地化。
- 匯入部分成功的回報（`progressPartialImportFailed`、`settingsImportPartial`）——前綴已在地化，帶出的只有 UID 數字，不含英文。
