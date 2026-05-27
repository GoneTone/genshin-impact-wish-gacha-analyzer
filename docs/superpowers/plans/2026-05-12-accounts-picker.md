# Accounts Picker (Export & Import) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在「資料管理」匯出 / 匯入流程前面插入帳號挑選對話框，並把服務 / 模型 / l10n key 的 `All` 字眼移除。

**Architecture:** 新增單一共用 `AccountsPickerDialog` widget，匯出與匯入皆呼叫；過濾邏輯在 `settings_page.dart` UI 層完成，不變動 service 簽名。l10n key 改名 + 新增 7 個字串。所有 `AllAccountsBundle` / `exportAllAccounts` / `importAllAccounts` / `ImportAllResult` 改為 `AccountsBundle` / `exportAccounts` / `importAccounts` / `ImportResult`，並對應重新命名 6 個 lib / test 檔。

**Tech Stack:** Flutter, Dart, Riverpod, `flutter_localizations` (gen-l10n)

---

## 提交前品質檢查（每次 commit 前必跑）

CLAUDE.md 規定的順序：

```powershell
dart format lib/ test/         # 不對 . 跑，會動到 rust_builder/ 內 vendored 碼
flutter analyze                 # 必須輸出 No issues found!
flutter test                    # 必須輸出 All tests passed!
```

任一失敗就先修，不要 `--no-verify`。

---

## File Structure

### 新增

| 路徑 | 責任 |
|---|---|
| `lib/widgets/dialogs/accounts_picker_dialog.dart` | `AccountPickerEntry` 資料類 + `showAccountsPickerDialog()` helper + 私有 `_AccountsPickerDialog` widget |
| `test/widgets/dialogs/accounts_picker_dialog_test.dart` | dialog 行為測試 |

### 改名（git mv）

| 舊 | 新 |
|---|---|
| `lib/models/all_accounts_bundle.dart` | `lib/models/accounts_bundle.dart` |
| `lib/services/all_accounts_export.dart` | `lib/services/accounts_export.dart` |
| `lib/services/all_accounts_import.dart` | `lib/services/accounts_import.dart` |
| `test/models/all_accounts_bundle_test.dart` | `test/models/accounts_bundle_test.dart` |
| `test/services/all_accounts_export_test.dart` | `test/services/accounts_export_test.dart` |
| `test/services/all_accounts_import_test.dart` | `test/services/accounts_import_test.dart` |

### 修改

| 路徑 | 變更 |
|---|---|
| `lib/state/wish_repository.dart` | 改 import；`AllAccountsBundle` → `AccountsBundle`；`ImportAllResult` → `ImportResult`；`importAllAccounts` method → `importAccounts` |
| `lib/pages/settings_page.dart` | 改 imports；`_exportAll` → `_export`、`_importAll` → `_import`；插入 picker 流程；l10n key 改名 |
| `lib/l10n/app_zh_Hant.arb` | 改 / 加 / 改名 l10n key（template） |
| `lib/l10n/app_zh_Hans.arb` | 同上 |
| `lib/l10n/app_en.arb` | 同上 |
| `lib/l10n/generated/*.dart` | 由 `flutter gen-l10n` 自動再生 |
| `test/state/wish_repository_test.dart` | 改 import + 類名 + method 呼叫 |

---

## Task 1: 改名 model 層 — `AllAccountsBundle` → `AccountsBundle`

**Files:**
- Rename: `lib/models/all_accounts_bundle.dart` → `lib/models/accounts_bundle.dart`
- Rename: `test/models/all_accounts_bundle_test.dart` → `test/models/accounts_bundle_test.dart`
- Modify: 上述兩個檔案的類名與 self-reference
- Modify: `lib/state/wish_repository.dart`（import 路徑 + 類名）
- Modify: `lib/services/all_accounts_export.dart`（import 路徑 + 類名；本檔下個 Task 才會改名，先 in-place 修）
- Modify: `lib/services/all_accounts_import.dart`（import 路徑 + 類名；同上）
- Modify: `lib/pages/settings_page.dart`（import 路徑 + 類名）
- Modify: `test/state/wish_repository_test.dart`（import 路徑 + 類名）

- [ ] **Step 1: git mv 兩個檔案**

```powershell
git mv lib/models/all_accounts_bundle.dart lib/models/accounts_bundle.dart
git mv test/models/all_accounts_bundle_test.dart test/models/accounts_bundle_test.dart
```

- [ ] **Step 2: 改 `lib/models/accounts_bundle.dart` 內的類名**

把整個檔案的 `AllAccountsBundle` 一律改為 `AccountsBundle`（4 處：`class AllAccountsBundle`、構造子 `const AllAccountsBundle(...)`、factory `factory AllAccountsBundle.fromJson(...)`、`return AllAccountsBundle(...)`）。

驗證：

```powershell
grep -rn "AllAccountsBundle" lib/models/accounts_bundle.dart
# Expected: 沒有 match
```

- [ ] **Step 3: 改測試檔內的類名 + import**

`test/models/accounts_bundle_test.dart`：
- import 路徑：`'package:.../models/all_accounts_bundle.dart'` → `'package:.../models/accounts_bundle.dart'`
- 所有 `AllAccountsBundle` 改 `AccountsBundle`

- [ ] **Step 4: 更新所有 callers 的 import + 類名**

需要動的檔案（grep 出來）：

```powershell
grep -rln "all_accounts_bundle\|AllAccountsBundle" lib/ test/
```

對每一個檔案：
- import 路徑：`'package:genshin_impact_wish_gacha_analyzer/models/all_accounts_bundle.dart'` → `'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart'`
- 類名：`AllAccountsBundle` → `AccountsBundle`

預期需要動的檔案：
- `lib/state/wish_repository.dart`
- `lib/services/all_accounts_export.dart`（檔名暫時保留，下個 Task 才改）
- `lib/services/all_accounts_import.dart`（同上）
- `lib/pages/settings_page.dart`
- `test/state/wish_repository_test.dart`

- [ ] **Step 5: 跑 analyze + test 確認綠燈**

```powershell
flutter analyze
flutter test
```

Expected：
- `analyze`：`No issues found!`
- `test`：`All tests passed!`

若有 `Undefined name 'AllAccountsBundle'` 或 `Target of URI doesn't exist` 之類錯誤，回頭看 Step 4 漏的檔案。

- [ ] **Step 6: 格式化 + commit**

```powershell
dart format lib/ test/
git add -A
git commit -m "refactor(models): rename AllAccountsBundle to AccountsBundle"
```

---

## Task 2: 改名服務層 — `exportAllAccounts` / `importAllAccounts` (service-level) + 檔名

**Files:**
- Rename: `lib/services/all_accounts_export.dart` → `lib/services/accounts_export.dart`
- Rename: `lib/services/all_accounts_import.dart` → `lib/services/accounts_import.dart`
- Rename: `test/services/all_accounts_export_test.dart` → `test/services/accounts_export_test.dart`
- Rename: `test/services/all_accounts_import_test.dart` → `test/services/accounts_import_test.dart`
- Modify: 4 個改名後的檔案內的函式名 + import
- Modify: `lib/pages/settings_page.dart`（import + 呼叫名）

- [ ] **Step 1: git mv 四個檔案**

```powershell
git mv lib/services/all_accounts_export.dart lib/services/accounts_export.dart
git mv lib/services/all_accounts_import.dart lib/services/accounts_import.dart
git mv test/services/all_accounts_export_test.dart test/services/accounts_export_test.dart
git mv test/services/all_accounts_import_test.dart test/services/accounts_import_test.dart
```

- [ ] **Step 2: 改 `lib/services/accounts_export.dart`**

把 `exportAllAccounts` 改為 `exportAccounts`：

```dart
// 把目前狀態打包成 [AccountsBundle] 並序列化成 pretty-printed JSON 字串。
//
// 帳號順序套用 [mergeUidOrder]，與設定頁顯示順序一致。
String exportAccounts({
  required Map<String, BannerStorage> byUid,
  required List<String> uidOrder,
  required Map<String, String> uidAliases,
  required String? lastActiveUid,
  required String appVersion,
  required DateTime now,
}) {
  // 內容不變，只把 final bundle = AllAccountsBundle(...) 改成
  // final bundle = AccountsBundle(...) （Task 1 已改）
  // ...
}
```

- [ ] **Step 3: 改 `lib/services/accounts_import.dart`**

把 service-level `importAllAccounts` 改為 `importAccounts`：

```dart
// 把 JSON 文字解析回 [AccountsBundle]。任何結構或型別不符都會
// 拋 FormatException。
AccountsBundle importAccounts(String text) {
  // 內容不變
  // ...
  return AccountsBundle.fromJson(raw);
}
```

- [ ] **Step 4: 改 test 檔的 import + 函式名**

`test/services/accounts_export_test.dart`：
- import：`'package:.../services/all_accounts_export.dart'` → `'package:.../services/accounts_export.dart'`
- 呼叫：`exportAllAccounts(...)` → `exportAccounts(...)`

`test/services/accounts_import_test.dart`：
- import：`'package:.../services/all_accounts_import.dart'` → `'package:.../services/accounts_import.dart'`
- 呼叫：`importAllAccounts(...)` → `importAccounts(...)`

- [ ] **Step 5: 更新 callers**

```powershell
grep -rln "all_accounts_export\|all_accounts_import\|exportAllAccounts\| importAllAccounts(" lib/ test/
```

> 注意 grep 中的 `importAllAccounts(` 前面有空格 — 這是為了排除 `WishRepositoryNotifier.importAllAccounts()` method 呼叫（Task 3 才處理），只抓 service-level 的呼叫。如果你的 shell 處理不到空格，分兩次 grep。

預期需要動：
- `lib/pages/settings_page.dart`：
  - 兩行 import：`/services/all_accounts_export.dart` / `/services/all_accounts_import.dart`
  - 一處呼叫：`exportAllAccounts(...)` → `exportAccounts(...)`
  - 一處呼叫：`bundle = importAllAccounts(text);` → `bundle = importAccounts(text);`

- [ ] **Step 6: 跑 analyze + test 確認綠燈**

```powershell
flutter analyze
flutter test
```

Expected：`No issues found!` + `All tests passed!`。

- [ ] **Step 7: 格式化 + commit**

```powershell
dart format lib/ test/
git add -A
git commit -m "refactor(services): rename exportAllAccounts/importAllAccounts to drop All"
```

---

## Task 3: 改名 Repository — `ImportAllResult` → `ImportResult`、`importAllAccounts` method → `importAccounts`

**Files:**
- Modify: `lib/state/wish_repository.dart`
- Modify: `lib/pages/settings_page.dart`
- Modify: `test/state/wish_repository_test.dart`

- [ ] **Step 1: 改 `lib/state/wish_repository.dart`**

第 24 行附近：

```dart
class ImportResult {
  const ImportResult({
    required this.successAccounts,
    required this.totalRecords,
    required this.failedUids,
  });

  final int successAccounts;
  final int totalRecords;
  final List<String> failedUids;
}
```

第 390 行附近的 method：

```dart
Future<ImportResult> importAccounts(AccountsBundle bundle) async {
  // 內容不變
  // ...
}
```

把該檔內所有 `ImportAllResult` 出現位置（grep 標出有 4 處）全改為 `ImportResult`。

驗證：

```powershell
grep -n "ImportAllResult\|importAllAccounts" lib/state/wish_repository.dart
# Expected: 沒有 match
```

- [ ] **Step 2: 改 caller `lib/pages/settings_page.dart`**

`settings_page.dart` 第 351 行附近：

```dart
final result = await ref
    .read(wishRepositoryProvider.notifier)
    .importAccounts(bundle);  // ← 從 importAllAccounts 改
```

- [ ] **Step 3: 改 test `test/state/wish_repository_test.dart`**

該檔有 4 個測試標題含 `importAllAccounts:`、4 處呼叫 `.importAllAccounts(bundle)`。全部改為 `importAccounts`：

```powershell
grep -n "importAllAccounts\|ImportAllResult" test/state/wish_repository_test.dart
```

對每處：
- test 標題字串：`'importAllAccounts: ...'` → `'importAccounts: ...'`
- 呼叫：`.importAllAccounts(bundle)` → `.importAccounts(bundle)`
- 如有 `ImportAllResult` 類名引用，改 `ImportResult`

- [ ] **Step 4: 跑 analyze + test 確認綠燈**

```powershell
flutter analyze
flutter test
```

Expected：`No issues found!` + `All tests passed!`。

- [ ] **Step 5: 格式化 + commit**

```powershell
dart format lib/ test/
git add -A
git commit -m "refactor(repository): rename importAllAccounts method and ImportAllResult"
```

---

## Task 4: 改名 settings_page 內部 helper

**Files:**
- Modify: `lib/pages/settings_page.dart`

- [ ] **Step 1: 改 `_exportAll` → `_export`、`_importAll` → `_import`**

兩個都是純內部 helper，沒外部 caller。在 `lib/pages/settings_page.dart`：

- method 宣告：`Future<void> _exportAll(...)` → `Future<void> _export(...)`
- method 宣告：`Future<void> _importAll(...)` → `Future<void> _import(...)`
- 呼叫位置（`_DataManagement.build` 內）：
  - `onPressed: !hasData ? null : () => _exportAll(context, ref)` → `... _export(context, ref)`
  - `onPressed: () => _importAll(context, ref)` → `... _import(context, ref)`

- [ ] **Step 2: 跑 analyze + test**

```powershell
flutter analyze
flutter test
```

Expected：`No issues found!` + `All tests passed!`。

- [ ] **Step 3: commit**

```powershell
dart format lib/ test/
git add -A
git commit -m "refactor(settings-page): rename _exportAll/_importAll helpers"
```

---

## Task 5: L10n — 改名既有 key + 更換按鈕文字 + 新增字串

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/pages/settings_page.dart`（key 使用處）
- Auto-regen: `lib/l10n/generated/*.dart`

### 改名既有 key（6 個）+ 文字調整（2 個）

| 舊 key | 新 key | 新文字（若有改） |
|---|---|---|
| `settingsExportAll` | `settingsExportAccounts` | zh_Hant: `匯出資料` / zh_Hans: `导出数据` / en: `Export data` |
| `settingsImportAll` | `settingsImportAccounts` | zh_Hant: `匯入資料` / zh_Hans: `导入数据` / en: `Import data` |
| `settingsExportAllSuccess` | `settingsExportSuccess` | 不變 |
| `settingsImportAllSuccess` | `settingsImportSuccess` | 不變 |
| `settingsImportAllPartial` | `settingsImportPartial` | 不變 |
| `settingsImportAllFailed` | `settingsImportFailed` | 不變 |

### 新增 key（7 個）

| key | zh_Hant | zh_Hans | en |
|---|---|---|---|
| `settingsExportSelectTitle` | 選擇要匯出的帳號 | 选择要导出的账号 | Select accounts to export |
| `settingsImportSelectTitle` | 選擇要匯入的帳號 | 选择要导入的账号 | Select accounts to import |
| `settingsImportOverwriteBadge` | 覆蓋 | 覆盖 | Overwrite |
| `accountsPickerSelectAll` | 全選 | 全选 | Select all |
| `accountRecordCount` | {n} 筆紀錄 | {n} 条记录 | {n} records |
| `confirmExport` | 匯出 | 导出 | Export |
| `confirmContinue` | 繼續 | 继续 | Continue |

- [ ] **Step 1: 更新 `lib/l10n/app_zh_Hant.arb`**

開檔，找到既有的 `settingsExportAll` 等 6 個 key，把 key 名一律改為新名。`@settingsExportAllSuccess` 等 metadata key 同步改。`settingsExportAccounts` / `settingsImportAccounts` 文案改為 `匯出資料` / `匯入資料`。

在 `settingsImportAllFailed`（改名後 `settingsImportFailed`）下面、`confirmTitle` 上面新增以下區塊：

```json
  "settingsExportSelectTitle": "選擇要匯出的帳號",
  "settingsImportSelectTitle": "選擇要匯入的帳號",
  "settingsImportOverwriteBadge": "覆蓋",
  "accountsPickerSelectAll": "全選",
  "accountRecordCount": "{n} 筆紀錄",
  "@accountRecordCount": {
    "placeholders": { "n": { "type": "int" } }
  },
```

在 `confirmImport` 下面加：

```json
  "confirmExport": "匯出",
  "confirmContinue": "繼續",
```

- [ ] **Step 2: 同步 `lib/l10n/app_zh_Hans.arb`**

對照 zh_Hant 做同樣的 key 改名 + 新增。文字改為 zh_Hans 版本：
- `settingsExportAccounts`: `导出数据`
- `settingsImportAccounts`: `导入数据`
- `settingsExportSelectTitle`: `选择要导出的账号`
- `settingsImportSelectTitle`: `选择要导入的账号`
- `settingsImportOverwriteBadge`: `覆盖`
- `accountsPickerSelectAll`: `全选`
- `accountRecordCount`: `{n} 条记录`
- `confirmExport`: `导出`
- `confirmContinue`: `继续`

- [ ] **Step 3: 同步 `lib/l10n/app_en.arb`**

- `settingsExportAccounts`: `Export data`
- `settingsImportAccounts`: `Import data`
- `settingsExportSelectTitle`: `Select accounts to export`
- `settingsImportSelectTitle`: `Select accounts to import`
- `settingsImportOverwriteBadge`: `Overwrite`
- `accountsPickerSelectAll`: `Select all`
- `accountRecordCount`: `{n} records`
- `confirmExport`: `Export`
- `confirmContinue`: `Continue`

- [ ] **Step 4: 重新生成 l10n**

```powershell
flutter gen-l10n
```

Expected：無錯誤。`lib/l10n/generated/app_localizations.dart` 與三個 locale 檔自動更新。**不要手動編輯 generated 檔。**

- [ ] **Step 5: 更新 `lib/pages/settings_page.dart` 內的 key 引用**

對應的 6 個改名 key：

```dart
// 按鈕標籤
l.settingsExportAll        → l.settingsExportAccounts
l.settingsImportAll        → l.settingsImportAccounts

// snackbar
l.settingsExportAllSuccess → l.settingsExportSuccess
l.settingsImportAllSuccess → l.settingsImportSuccess
l.settingsImportAllPartial → l.settingsImportPartial
l.settingsImportAllFailed  → l.settingsImportFailed
```

驗證：

```powershell
grep -n "settingsExportAll\|settingsImportAll" lib/pages/settings_page.dart
# Expected: 沒有 match（注意 `settingsExportAllSuccess` 也算 settingsExportAll 開頭，
# 但既然全部 6 個 key 都改了名，這個 grep 應該完全空）
```

- [ ] **Step 6: 跑 analyze + test 確認綠燈**

```powershell
flutter analyze
flutter test
```

Expected：`No issues found!` + `All tests passed!`。如果 generated 檔還有舊 key 引用，回頭跑 `flutter gen-l10n`。

- [ ] **Step 7: 格式化 + commit**

```powershell
dart format lib/ test/
git add -A
git commit -m "feat(l10n): drop 'All' from data management keys and add picker strings"
```

---

## Task 6: 建立 `AccountsPickerDialog` widget（TDD）

**Files:**
- Create: `lib/widgets/dialogs/accounts_picker_dialog.dart`
- Create: `test/widgets/dialogs/accounts_picker_dialog_test.dart`

### Step 1：建立空骨架 + 第一個 render 測試（fail）

- [ ] **Step 1a: 建立空骨架檔**

Create `lib/widgets/dialogs/accounts_picker_dialog.dart`:

```dart
import 'package:flutter/material.dart';

class AccountPickerEntry {
  const AccountPickerEntry({
    required this.uid,
    this.alias,
    required this.lastUpdated,
    required this.recordCount,
    this.badge,
  });

  final String uid;
  final String? alias;
  final DateTime lastUpdated;
  final int recordCount;
  final String? badge;
}

Future<List<String>?> showAccountsPickerDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  required List<AccountPickerEntry> entries,
}) {
  throw UnimplementedError();
}
```

- [ ] **Step 1b: 建測試檔，寫第一個 test：初始全勾、全選 checked、確認 enabled**

Create `test/widgets/dialogs/accounts_picker_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/accounts_picker_dialog.dart';

final _entries = [
  AccountPickerEntry(
    uid: '100000001',
    alias: '主號',
    lastUpdated: DateTime.utc(2026, 5, 10, 12),
    recordCount: 1234,
  ),
  AccountPickerEntry(
    uid: '100000002',
    lastUpdated: DateTime.utc(2026, 5, 11, 8),
    recordCount: 567,
  ),
  AccountPickerEntry(
    uid: '100000003',
    alias: '小號',
    lastUpdated: DateTime.utc(2026, 5, 12, 9),
    recordCount: 0,
    badge: '覆蓋',
  ),
];

// 用 file-level 變數捕捉 dialog 結果。每個 test 跑前 _open 會重置。
// 直接從 async _open return Future 會被 Dart auto-unwrap，所以採用
// 捕捉變數模式（同 test/widgets/dialogs/confirm_dialog_test.dart）。
List<String>? _result;
bool _completed = false;

Future<void> _open(
  WidgetTester tester, {
  List<AccountPickerEntry>? entries,
}) async {
  _result = null;
  _completed = false;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh', 'Hant'),
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                _result = await showAccountsPickerDialog(
                  context: ctx,
                  title: '選擇要匯出的帳號',
                  confirmLabel: '匯出',
                  entries: entries ?? _entries,
                );
                _completed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('initial state: all checked, select-all checked, confirm enabled', (
    tester,
  ) async {
    await _open(tester);

    // 3 個帳號 row 都顯示
    expect(find.text('100000001 (主號)'), findsOneWidget);
    expect(find.text('100000002'), findsOneWidget);
    expect(find.text('100000003 (小號)'), findsOneWidget);

    // 全選 checkbox 是 checked
    final selectAll = find.widgetWithText(CheckboxListTile, '全選');
    expect(selectAll, findsOneWidget);
    expect(tester.widget<CheckboxListTile>(selectAll).value, isTrue);

    // 確認按鈕 enabled
    final confirmBtn = find.widgetWithText(FilledButton, '匯出');
    expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNotNull);
  });
}
```

- [ ] **Step 1c: 跑測試確認 fail**

```powershell
flutter test test/widgets/dialogs/accounts_picker_dialog_test.dart
```

Expected：fail，原因為 `UnimplementedError` 或無對應 widget。

### Step 2：實作 dialog 主體讓第一個 test 通過

- [ ] **Step 2a: 把 dialog skeleton 填完**

替換 `lib/widgets/dialogs/accounts_picker_dialog.dart` 整個檔案：

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class AccountPickerEntry {
  const AccountPickerEntry({
    required this.uid,
    this.alias,
    required this.lastUpdated,
    required this.recordCount,
    this.badge,
  });

  final String uid;
  final String? alias;
  final DateTime lastUpdated;
  final int recordCount;
  final String? badge;
}

/// 顯示帳號挑選對話框；回傳被勾選的 UID 清單（保持 entries 傳入順序）。
/// 使用者取消時回傳 null。
Future<List<String>?> showAccountsPickerDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  required List<AccountPickerEntry> entries,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _AccountsPickerDialog(
      title: title,
      confirmLabel: confirmLabel,
      entries: entries,
    ),
  );
}

class _AccountsPickerDialog extends StatefulWidget {
  const _AccountsPickerDialog({
    required this.title,
    required this.confirmLabel,
    required this.entries,
  });

  final String title;
  final String confirmLabel;
  final List<AccountPickerEntry> entries;

  @override
  State<_AccountsPickerDialog> createState() => _AccountsPickerDialogState();
}

class _AccountsPickerDialogState extends State<_AccountsPickerDialog> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.entries.map((e) => e.uid).toSet();
  }

  bool? get _selectAllValue {
    if (_selected.isEmpty) return false;
    if (_selected.length == widget.entries.length) return true;
    return null;
  }

  void _setAll(bool checked) {
    setState(() {
      if (checked) {
        _selected
          ..clear()
          ..addAll(widget.entries.map((e) => e.uid));
      } else {
        _selected.clear();
      }
    });
  }

  void _toggle(String uid, bool checked) {
    setState(() {
      if (checked) {
        _selected.add(uid);
      } else {
        _selected.remove(uid);
      }
    });
  }

  void _onSelectAllTap() {
    // 自己接管 tristate cycle：true → false；false / null → true。
    _setAll(_selectAllValue != true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              tristate: true,
              value: _selectAllValue,
              title: Text(l.accountsPickerSelectAll),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              onChanged: (_) => _onSelectAllTap(),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final e = widget.entries[i];
                  return _PickerRow(
                    entry: e,
                    selected: _selected.contains(e.uid),
                    onChanged: (v) => _toggle(e.uid, v ?? false),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.confirmCancel),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final ordered = [
                    for (final e in widget.entries)
                      if (_selected.contains(e.uid)) e.uid,
                  ];
                  Navigator.of(context).pop(ordered);
                },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.entry,
    required this.selected,
    required this.onChanged,
  });

  final AccountPickerEntry entry;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final alias = entry.alias;
    final title = (alias != null && alias.isNotEmpty)
        ? '${entry.uid} ($alias)'
        : entry.uid;
    final lastUpdated = DateFormat(
      'yyyy-MM-dd HH:mm',
    ).format(entry.lastUpdated.toLocal());
    final badge = entry.badge;
    return CheckboxListTile(
      value: selected,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
      title: Row(
        children: [
          Expanded(child: Text(title)),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: tokens.stateDanger.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: tokens.stateDanger,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        '${l.accountLastUpdated(lastUpdated)} ・ ${l.accountRecordCount(entry.recordCount)}',
        style: TextStyle(color: tokens.textMuted, fontSize: 12),
      ),
    );
  }
}
```

- [ ] **Step 2b: 跑 test 確認第一個 case 通過**

```powershell
flutter test test/widgets/dialogs/accounts_picker_dialog_test.dart
```

Expected：第一個 testWidgets pass。

### Step 3：加 select-all tristate 測試

- [ ] **Step 3a: 在 test 檔加 4 個 select-all test**

加在第一個 `testWidgets` 之後：

```dart
  testWidgets('uncheck one entry → select-all becomes indeterminate (null)', (
    tester,
  ) async {
    await _open(tester);
    // 點第一個 row 的 checkbox（找它的 title）
    await tester.tap(find.text('100000001 (主號)'));
    await tester.pump();

    final selectAll = find.widgetWithText(CheckboxListTile, '全選');
    expect(tester.widget<CheckboxListTile>(selectAll).value, isNull);

    // 確認按鈕仍 enabled（還有 2 個勾）
    final confirmBtn = find.widgetWithText(FilledButton, '匯出');
    expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNotNull);
  });

  testWidgets('uncheck all → select-all unchecked + confirm disabled', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('100000001 (主號)'));
    await tester.tap(find.text('100000002'));
    await tester.tap(find.text('100000003 (小號)'));
    await tester.pump();

    final selectAll = find.widgetWithText(CheckboxListTile, '全選');
    expect(tester.widget<CheckboxListTile>(selectAll).value, isFalse);

    final confirmBtn = find.widgetWithText(FilledButton, '匯出');
    expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNull);
  });

  testWidgets('tap select-all when checked → all clear, confirm disabled', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('全選'));
    await tester.pump();

    final selectAll = find.widgetWithText(CheckboxListTile, '全選');
    expect(tester.widget<CheckboxListTile>(selectAll).value, isFalse);

    final confirmBtn = find.widgetWithText(FilledButton, '匯出');
    expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNull);
  });

  testWidgets('tap select-all when indeterminate → all check', (tester) async {
    await _open(tester);
    // 先 uncheck 一個進 indeterminate
    await tester.tap(find.text('100000001 (主號)'));
    await tester.pump();
    // 再點全選
    await tester.tap(find.text('全選'));
    await tester.pump();

    final selectAll = find.widgetWithText(CheckboxListTile, '全選');
    expect(tester.widget<CheckboxListTile>(selectAll).value, isTrue);
  });
```

- [ ] **Step 3b: 跑 test 確認全綠**

```powershell
flutter test test/widgets/dialogs/accounts_picker_dialog_test.dart
```

Expected：5 個 testWidgets 全 pass。

> 若 indeterminate 切換邏輯失敗（callback 帶 null/true/false 但我們無視 v 用 `_selectAllValue != true` 判定），核對 `_onSelectAllTap()` 實作。

### Step 4：加 alias / badge / 數量顯示測試

- [ ] **Step 4a: 加 display test**

```dart
  testWidgets('alias rendering: with and without alias', (tester) async {
    await _open(tester);
    expect(find.text('100000001 (主號)'), findsOneWidget);   // 有別名
    expect(find.text('100000002'), findsOneWidget);          // 無別名（不附括號）
    expect(find.text('100000003 (小號)'), findsOneWidget);
  });

  testWidgets('overwrite badge shown only when entry.badge != null', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('覆蓋'), findsOneWidget);
  });

  testWidgets('subtitle shows lastUpdated + recordCount per locale', (
    tester,
  ) async {
    await _open(tester);
    // 第一個 entry：lastUpdated = 2026-05-10 12:00 UTC，本地時間轉換可能不同
    // 用 substring 斷言避開時區差異。
    expect(find.textContaining('1234 筆紀錄'), findsOneWidget);
    expect(find.textContaining('567 筆紀錄'), findsOneWidget);
    expect(find.textContaining('0 筆紀錄'), findsOneWidget);
  });
```

- [ ] **Step 4b: 跑 test 確認全綠**

```powershell
flutter test test/widgets/dialogs/accounts_picker_dialog_test.dart
```

Expected：8 個 testWidgets 全 pass。

### Step 5：加 return value 測試

- [ ] **Step 5a: 加 cancel / confirm 回傳測試**

```dart
  testWidgets('cancel returns null', (tester) async {
    await _open(tester);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(_completed, isTrue);
    expect(_result, isNull);
  });

  testWidgets('confirm returns selected UIDs in entry order', (tester) async {
    await _open(tester);
    // 取消中間那個
    await tester.tap(find.text('100000002'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '匯出'));
    await tester.pumpAndSettle();
    expect(_completed, isTrue);
    expect(_result, ['100000001', '100000003']);
  });

  testWidgets('confirm returns all UIDs when nothing toggled', (tester) async {
    await _open(tester);
    await tester.tap(find.widgetWithText(FilledButton, '匯出'));
    await tester.pumpAndSettle();
    expect(_completed, isTrue);
    expect(_result, ['100000001', '100000002', '100000003']);
  });
```

- [ ] **Step 5b: 跑 test 確認全綠**

```powershell
flutter test test/widgets/dialogs/accounts_picker_dialog_test.dart
```

Expected：11 個 testWidgets 全 pass。

### Step 6：全套 test + commit

- [ ] **Step 6a: 跑全套**

```powershell
flutter analyze
flutter test
```

Expected：`No issues found!` + `All tests passed!`。

- [ ] **Step 6b: commit**

```powershell
dart format lib/ test/
git add lib/widgets/dialogs/accounts_picker_dialog.dart test/widgets/dialogs/accounts_picker_dialog_test.dart
git commit -m "feat(widgets): add AccountsPickerDialog with tri-state select-all"
```

---

## Task 7: 整合匯出流程

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Modify: `test/services/accounts_export_test.dart`（加過濾子集 test）

### Step 1：補 service 測試（過濾子集）

- [ ] **Step 1a: 在 `test/services/accounts_export_test.dart` 末尾加 test**

```dart
  test('exports only the byUid subset it was given', () {
    // byUid 只塞兩個，模擬 picker 過濾後的子集
    final byUid = {
      'A': _bs('A', DateTime.utc(2026, 5, 10)),
      'C': _bs('C', DateTime.utc(2026, 5, 11)),
    };
    final out = exportAccounts(
      byUid: byUid,
      uidOrder: const ['A', 'C'],
      uidAliases: const {'A': '主號'},
      lastActiveUid: null,
      appVersion: '9.9.9',
      now: DateTime.utc(2026, 5, 12),
    );
    final decoded = jsonDecode(out) as Map<String, dynamic>;
    final accounts = decoded['accounts'] as List<dynamic>;
    expect(accounts.map((a) => a['uid']).toList(), ['A', 'C']);
    expect(decoded['last_active_uid'], isNull);
  });
```

- [ ] **Step 1b: 跑該 test pass**

```powershell
flutter test test/services/accounts_export_test.dart
```

Expected：兩個 test 都 pass。

### Step 2：改 `settings_page.dart` 的 `_export()`

- [ ] **Step 2a: 加 import**

在 `lib/pages/settings_page.dart` 檔頂的 import 區塊加：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/accounts_picker_dialog.dart';
```

（如果 `uid_ordering.dart` 已 import 就只加 picker dialog 那行。）

- [ ] **Step 2b: 替換 `_export()` 的內容**

把 `_export()`（剛剛改名後）整個替換成：

```dart
Future<void> _export(BuildContext ctx, WidgetRef ref) async {
  final l = AppLocalizations.of(ctx)!;
  final wish = ref.read(wishRepositoryProvider);
  final settings = ref.read(settingsProvider);
  final appVersion = ref.read(appVersionProvider);

  final ordered = mergeUidOrder(
    knownUids: wish.byUid.keys,
    customOrder: settings.uidOrder,
    lastUpdatedOf: (u) => wish.byUid[u]!.lastUpdated,
  );

  final entries = [
    for (final uid in ordered)
      AccountPickerEntry(
        uid: uid,
        alias: settings.uidAliases[uid],
        lastUpdated: wish.byUid[uid]!.lastUpdated,
        recordCount: wish.byUid[uid]!.allRecords.length,
      ),
  ];
  final picked = await showAccountsPickerDialog(
    context: ctx,
    title: l.settingsExportSelectTitle,
    confirmLabel: l.confirmExport,
    entries: entries,
  );
  if (picked == null || picked.isEmpty) return;
  if (!ctx.mounted) return;

  final now = DateTime.now();
  final stamp =
      '${now.year}-${_two(now.month)}-${_two(now.day)}_'
      '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';

  final loc = await getSaveLocation(
    suggestedName: 'genshin_wish_backup_$stamp.json',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON', extensions: ['json']),
    ],
  );
  if (loc == null) return;

  final pickedSet = picked.toSet();
  final filteredByUid = {
    for (final e in wish.byUid.entries)
      if (pickedSet.contains(e.key)) e.key: e.value,
  };
  final filteredAliases = {
    for (final e in settings.uidAliases.entries)
      if (pickedSet.contains(e.key)) e.key: e.value,
  };
  final filteredOrder = settings.uidOrder
      .where(pickedSet.contains)
      .toList(growable: false);
  final lastActive = pickedSet.contains(settings.lastActiveUid)
      ? settings.lastActiveUid
      : null;

  final text = exportAccounts(
    byUid: filteredByUid,
    uidOrder: filteredOrder,
    uidAliases: filteredAliases,
    lastActiveUid: lastActive,
    appVersion: appVersion,
    now: now,
  );
  await File(loc.path).writeAsString(text);
  if (!ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(content: Text(l.settingsExportSuccess(loc.path))),
  );
}
```

- [ ] **Step 2c: 跑 analyze + test 全綠**

```powershell
flutter analyze
flutter test
```

Expected：`No issues found!` + `All tests passed!`。

### Step 3：手動驗證匯出流程

- [ ] **Step 3: 跑 desktop app，匯出走 picker**

```powershell
flutter run -d windows
```

操作：
1. 確保至少有 2 個帳號的紀錄。
2. 設定 → 資料管理 → 「匯出資料」按鈕。
3. 應該跳出帳號挑選對話框，所有帳號預設勾上、「全選」checked、「匯出」按鈕 enabled。
4. 取消一個帳號 → 「全選」變 indeterminate。
5. 點「全選」→ 全清空、「匯出」按鈕 disabled。
6. 再點「全選」→ 全勾。
7. 留兩個勾、按「匯出」→ 跳檔案存檔對話框，存成 JSON。
8. 打開 JSON 確認只有勾起的帳號在 `accounts` 陣列，`last_active_uid` 為 null（若取消了原 lastActive）。
9. 取消對話框 → 不寫檔、不跳檔案對話框。

### Step 4：commit

- [ ] **Step 4: commit**

```powershell
dart format lib/ test/
git add -A
git commit -m "feat(settings-page): integrate accounts picker into export flow"
```

---

## Task 8: 整合匯入流程

**Files:**
- Modify: `lib/pages/settings_page.dart`

### Step 1：替換 `_import()` 內容

- [ ] **Step 1: 替換 `_import()`**

把 `_import()`（剛剛改名後）整個替換成：

```dart
Future<void> _import(BuildContext ctx, WidgetRef ref) async {
  final l = AppLocalizations.of(ctx)!;
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON', extensions: ['json']),
    ],
  );
  if (file == null) return;

  final String text;
  try {
    text = await file.readAsString();
  } catch (e) {
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(l.settingsImportFailed(e.toString()))),
    );
    return;
  }

  final AccountsBundle bundle;
  try {
    bundle = importAccounts(text);
  } on FormatException catch (e) {
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(l.settingsImportFailed(e.message))),
    );
    return;
  }

  // Picker：列出檔案內的帳號讓使用者勾選。
  final existing = ref.read(wishRepositoryProvider).byUid.keys.toSet();
  final entries = [
    for (final a in bundle.accounts)
      AccountPickerEntry(
        uid: a.data.uid,
        alias: a.alias,
        lastUpdated: a.data.lastUpdated,
        recordCount: a.data.allRecords.length,
        badge: existing.contains(a.data.uid)
            ? l.settingsImportOverwriteBadge
            : null,
      ),
  ];
  if (!ctx.mounted) return;
  final picked = await showAccountsPickerDialog(
    context: ctx,
    title: l.settingsImportSelectTitle,
    confirmLabel: l.confirmContinue,
    entries: entries,
  );
  if (picked == null || picked.isEmpty) return;
  if (!ctx.mounted) return;

  final pickedSet = picked.toSet();
  final filteredBundle = AccountsBundle(
    exportedAt: bundle.exportedAt,
    appVersion: bundle.appVersion,
    lastActiveUid: pickedSet.contains(bundle.lastActiveUid)
        ? bundle.lastActiveUid
        : null,
    accounts: bundle.accounts
        .where((a) => pickedSet.contains(a.data.uid))
        .toList(growable: false),
  );

  // Confirm dialog：以 filteredBundle 重新計算 incoming / conflicts / preserved。
  final incoming = filteredBundle.accounts
      .map((a) => a.data.uid)
      .toList(growable: false);
  final conflicts = incoming.where(existing.contains).toList(growable: false);
  final preserved = (existing.toSet()..removeAll(incoming)).toList()..sort();

  var totalRecords = 0;
  for (final a in filteredBundle.accounts) {
    for (final list in a.data.banners.values) {
      totalRecords += list.length;
    }
  }

  final buf = StringBuffer()
    ..writeln(l.settingsImportConfirmIntro(incoming.length, totalRecords));
  for (final a in filteredBundle.accounts) {
    final alias = a.alias;
    buf.writeln(
      alias == null || alias.isEmpty
          ? '  • ${a.data.uid}'
          : '  • ${a.data.uid} ($alias)',
    );
  }
  buf.writeln();
  if (conflicts.isEmpty) {
    buf.writeln(l.settingsImportConfirmNoConflict);
  } else {
    buf.writeln(l.settingsImportConfirmOverwriteHeader);
    for (final uid in conflicts) {
      buf.writeln('  • $uid');
    }
  }
  if (preserved.isNotEmpty) {
    buf.writeln();
    buf.writeln(l.settingsImportConfirmPreserveFooter(preserved.join(', ')));
  }
  buf.writeln();
  buf.write(l.settingsImportConfirmWarning);

  final ok = await showConfirmTypeDialog(
    context: ctx,
    title: l.settingsImportConfirmTitle,
    body: buf.toString(),
    expectedText: 'IMPORT',
    cancelLabel: l.confirmCancel,
    confirmLabel: l.confirmImport,
  );
  if (ok != true) return;
  if (!ctx.mounted) return;

  final result = await ref
      .read(wishRepositoryProvider.notifier)
      .importAccounts(filteredBundle);
  if (!ctx.mounted) return;

  final SnackBar snack;
  if (result.failedUids.isEmpty) {
    snack = SnackBar(
      content: Text(
        l.settingsImportSuccess(result.successAccounts, result.totalRecords),
      ),
    );
  } else {
    snack = SnackBar(
      content: Text(
        l.settingsImportPartial(
          result.successAccounts,
          filteredBundle.accounts.length,
          result.failedUids.join(', '),
        ),
      ),
    );
  }
  ScaffoldMessenger.of(ctx).showSnackBar(snack);
}
```

### Step 2：跑 analyze + test

- [ ] **Step 2: 跑 analyze + test**

```powershell
flutter analyze
flutter test
```

Expected：`No issues found!` + `All tests passed!`。

### Step 3：手動驗證匯入流程

- [ ] **Step 3: 用 Task 7 匯出的 JSON 測匯入**

```powershell
flutter run -d windows
```

操作：
1. 把目前帳號清掉（資料管理 → 清除所有資料），讓本機沒有任何 UID。
2. 「匯入資料」→ 選 JSON → 應該跳 picker，所有帳號預設勾上、沒有覆蓋標籤（因為本機空）。
3. 取消其中一個 → 按「繼續」 → 進入既有確認對話框，列出剩下要匯入的帳號、無衝突。
4. 輸入 `IMPORT` → 確認 → snackbar 顯示成功匯入 N 個帳號。
5. 再匯入一次同一份 JSON：picker 應該顯示「覆蓋」標籤在已存在的 UID 上。
6. 取消整個 picker（按取消按鈕）→ 不彈確認對話框、不執行匯入。

### Step 4：commit

- [ ] **Step 4: commit**

```powershell
dart format lib/ test/
git add -A
git commit -m "feat(settings-page): integrate accounts picker into import flow"
```

---

## Task 9: 最終驗證

**Files:** （無新動）

- [ ] **Step 1: 跑全套 quality check**

```powershell
dart format lib/ test/
flutter analyze
flutter test
```

Expected：
- format 無 diff（已 commit）
- analyze: `No issues found!`
- test: `All tests passed!`

- [ ] **Step 2: 對 spec 做最終 sanity check**

對照 `docs/superpowers/specs/2026-05-12-accounts-picker-design.md` 第 2 節「需求」：

1. 按鈕文字「匯出資料」/「匯入資料」沒「全部」字眼 → `lib/l10n/app_*.arb` 應為新文字。
2. 匯出 / 匯入皆顯示 picker → `_export()` / `_import()` 都呼叫 `showAccountsPickerDialog()`。
3. 預設全勾 → dialog state `_selected` 初始為 entries 全集。
4. 「全選」tri-state → `tristate: true` + `_onSelectAllTap()` 自接管 cycle。
5. 資訊欄：UID、別名、最後更新、紀錄數、覆蓋標籤（匯入端） → `_PickerRow` widget 結構。
6. 服務 / 模型改名 → grep 不應有 `AllAccountsBundle` / `exportAllAccounts` / `importAllAccounts` / `ImportAllResult` 殘留。

```powershell
grep -rn "AllAccountsBundle\|exportAllAccounts\|importAllAccounts\|ImportAllResult\|settingsExportAll\|settingsImportAll" lib/ test/
# Expected: 沒有 match（generated/* 也要看）
```

- [ ] **Step 3: 確認 git status 乾淨**

```powershell
git status
git log --oneline -10
```

Expected：working tree clean、最近 8 個 commit 對應 Task 1~8。

---

## YAGNI / 不做的事

照 spec 第 8 節：
- 不加「只匯出活躍」/「只匯出有衝突」快捷
- 不在 picker 顯示卡池細分
- 不改 `exportAccounts()` 簽名
- 不重新命名 `ExportedAccount`
- `accountRecordCount` 不加 ICU plural
- `BannerStorage` 不加新 `recordCount` getter

## 風險

- **規模改名**：caller 漏改編譯會擋下；如果 `flutter analyze` 仍綠但 generated 檔抓不到新 key，跑 `flutter gen-l10n`。
- **i18n 模板**：`l10n.yaml` 的 `template-arb-file` 是 `app_zh_Hant.arb`，其他語系（除 zh_Hans/en 外）會 fallback 至 template。改完 zh_Hant 後其他語系自動有正體中文文字，但 commit `d78687b` 已決定這是接受的行為。
- **JSON 向後相容**：`schema_version` 仍是 1，舊 JSON 可匯入新 app，新 JSON 也可匯入舊 app（schema 沒變）。
