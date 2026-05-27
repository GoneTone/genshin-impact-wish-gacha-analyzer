# Accounts Picker (Export & Import) & Drop "All" Naming

**日期**：2026-05-12
**狀態**：Draft → 等待 user review

## 背景

「資料管理」區塊目前提供整包匯出 / 匯入：

- 按鈕文案：`匯出全部資料` / `匯入全部資料`（zh_Hant）。
- 匯出 (`_exportAll`)：直接把 `wishRepositoryProvider` 全部 byUid 丟給 `exportAllAccounts()`。
- 匯入 (`_importAll`)：解析檔案後直接列出整包帳號讓使用者確認 → `importAllAccounts(bundle)`。使用者無法剔除某些帳號。

整個流程是 commit `34d1caa` 一系列把舊的 per-account 匯出改為一包匯出後的結果。希望保有一包匯出 / 匯入的便利，但加上挑選彈性，並讓使用者在挑選時看到每個帳號的關鍵資訊。

## 需求

1. 移除按鈕文字的「全部」字眼：「匯出資料」/「匯入資料」。
2. 匯出與匯入都顯示帳號挑選對話框：
   - 列出帳號讓使用者勾選。
   - 預設全勾。
   - 列表上方有「全選」checkbox，可一鍵切換全選 / 全清（tri-state）。
3. 對話框內每個帳號顯示資訊欄：UID、別名（若有）、最後更新時間、紀錄數量。匯入端額外顯示「覆蓋」標籤（該 UID 在本機已存在）。
4. 服務 / 模型 / l10n key 改名，移除 `All` 字眼。

## 設計

### 1. 共用挑選對話框

新增 widget：`lib/widgets/dialogs/accounts_picker_dialog.dart`，匯出與匯入共用。

公開介面：

```dart
class AccountPickerEntry {
  const AccountPickerEntry({
    required this.uid,
    this.alias,
    required this.lastUpdated,
    required this.recordCount,
    this.badge,  // 例：「覆蓋」；null = 不顯示
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
});
```

呼叫端構造 `entries`：
- **匯出**：用 `mergeUidOrder()` 排序本機 byUid → 每筆 `AccountPickerEntry(uid, alias, lastUpdated, recordCount = byUid[uid]!.allRecords.length, badge: null)`。
- **匯入**：依檔案內順序 → 每筆 `AccountPickerEntry(uid, alias = ExportedAccount.alias, lastUpdated, recordCount = a.data.allRecords.length, badge: existing.contains(uid) ? l.settingsImportOverwriteBadge : null)`。

`BannerStorage.allRecords` 已存在，直接 `.length`。**不新增 getter**。

#### UI 結構

```
╭─ 選擇要匯入的帳號 ──────────────────────────────╮
│  ☑ 全選                                            │  ← tri-state 主控
│  ────────────────────────────────────────────────│
│  ☑ 100000001 (主帳號)              [覆蓋]          │
│      最後更新 2026-05-11 12:00 ・ 1,200 筆紀錄    │
│  ────────────────────────────────────────────────│
│  ☑ 100000004                                       │
│      最後更新 2026-05-12 08:00 ・ 500 筆紀錄      │
│  ────────────────────────────────────────────────│
│  ...                                               │
│                              [取消]  [繼續]        │  ← 0 勾時 disabled
╰────────────────────────────────────────────────────╯
```

- 每筆兩行：第一行 UID + 別名 + 覆蓋標籤；第二行最後更新 + 紀錄數，灰色 `textMuted`。
- 別名顯示：`UID (alias)`，無別名時只顯示 UID。
- 「覆蓋」標籤：右側小圓角 chip，用 `stateDanger` / `accentPrimary` 帶警示色（實作時挑色，符合 `theme/tokens.dart`）。
- 「全選」`CheckboxListTile`，`tristate: true`：
  - 全勾 → `true`；全空 → `false`；部分勾 → `null`（indeterminate）。
  - 點擊：`true` → 全清；`false` 或 `null` → 全勾。
- 確認按鈕在 `selected.isEmpty` 時 disabled。
- 帳號數較多時整個列表內捲（`ListView` shrinkWrap + scroll；對話框 max height 由 `Dialog`/`AlertDialog` 限制）。

#### 狀態管理

`StatefulWidget`，內部 `Set<String> _selected` 初始為 `entries.map((e) => e.uid).toSet()`。純對話框暫態，不用 Riverpod。

### 2. 匯出流程整合

`settings_page.dart` 內 `_export()`（重新命名後）：

```dart
Future<void> _export(BuildContext ctx, WidgetRef ref) async {
  final l = AppLocalizations.of(ctx)!;
  final wish = ref.read(wishRepositoryProvider);
  final settings = ref.read(settingsProvider);
  final appVersion = ref.read(appVersionProvider);

  // 1. 排序
  final ordered = mergeUidOrder(
    knownUids: wish.byUid.keys,
    customOrder: settings.uidOrder,
    lastUpdatedOf: (u) => wish.byUid[u]!.lastUpdated,
  );

  // 2. 構造 entries 並顯示 picker
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

  // 3. 檔案儲存對話框（原邏輯）
  // ...

  // 4. 過濾後傳給服務層
  final pickedSet = picked.toSet();
  final filteredByUid = {
    for (final e in wish.byUid.entries)
      if (pickedSet.contains(e.key)) e.key: e.value,
  };
  final filteredAliases = {
    for (final e in settings.uidAliases.entries)
      if (pickedSet.contains(e.key)) e.key: e.value,
  };
  final filteredOrder = settings.uidOrder.where(pickedSet.contains).toList();
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
  // ... 寫檔、snackbar 不變 ...
}
```

`exportAccounts()` 簽名不變，過濾在 UI 層完成。

### 3. 匯入流程整合

`_import()`（重新命名後）的新流程：

```dart
Future<void> _import(BuildContext ctx, WidgetRef ref) async {
  final l = AppLocalizations.of(ctx)!;

  // 1. 選檔 + 讀取 + 解析（原邏輯）
  final file = await openFile(...);
  if (file == null) return;
  // ... read & parse to AccountsBundle ...

  // 2. NEW: 顯示 picker
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
  final picked = await showAccountsPickerDialog(
    context: ctx,
    title: l.settingsImportSelectTitle,
    confirmLabel: l.confirmContinue,
    entries: entries,
  );
  if (picked == null || picked.isEmpty) return;

  // 3. 過濾 bundle
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

  // 4. 既有 confirm 對話框（用 filteredBundle 構建文字、輸入 IMPORT 確認）
  //    incoming / conflicts / preserved 計算改以 filteredBundle 為基礎；
  //    其他邏輯不變。

  // 5. importAccounts(filteredBundle)（原邏輯）
}
```

挑選 → 確認 兩階段：

1. **Picker** 負責挑選 + 顯示資訊，按「繼續」進下一步。
2. **既有 confirm dialog** 負責列出衝突 / 保留、要求輸入 `IMPORT`、最終確認。

過濾 bundle 直接用 `AccountsBundle` 既有 const 建構子，模型不需要新增 API。

### 4. 服務 / 模型 / Repository 改名

| 舊 | 新 |
|---|---|
| `lib/services/all_accounts_export.dart` | `lib/services/accounts_export.dart` |
| `lib/services/all_accounts_import.dart` | `lib/services/accounts_import.dart` |
| `lib/models/all_accounts_bundle.dart` | `lib/models/accounts_bundle.dart` |
| `test/services/all_accounts_export_test.dart` | `test/services/accounts_export_test.dart` |
| `test/services/all_accounts_import_test.dart` | `test/services/accounts_import_test.dart` |
| `test/models/all_accounts_bundle_test.dart` | `test/models/accounts_bundle_test.dart` |
| `exportAllAccounts()` | `exportAccounts()` |
| `importAllAccounts()`（service-level） | `importAccounts()` |
| `WishRepositoryNotifier.importAllAccounts()` | `.importAccounts()` |
| `AllAccountsBundle` 類別 | `AccountsBundle` |
| `ImportAllResult` 類別 | `ImportResult` |
| `ExportedAccount` | **保留**，語意正確 |

**JSON schema 不動**。匯出檔內欄位本來就沒有 `all`（`schema_version` / `exported_at` / `app_version` / `last_active_uid` / `accounts`），向後相容性自然成立。

callers 須同步更新：
- `lib/pages/settings_page.dart`（service import + class import + 多個 call site）
- `lib/state/wish_repository.dart`（model import + method 名）
- 3 個 test 檔案路徑 + 符號

### 5. l10n 變更

只動 `app_zh_Hant.arb`、`app_zh_Hans.arb`、`app_en.arb`。其他語系於 commit `d78687b` 已刪除等同模板的翻譯走 fallback，無需動。

#### 改名既有 key

| 舊 key | 新 key |
|---|---|
| `settingsExportAll` | `settingsExportAccounts` |
| `settingsImportAll` | `settingsImportAccounts` |
| `settingsExportAllSuccess` | `settingsExportSuccess` |
| `settingsImportAllSuccess` | `settingsImportSuccess` |
| `settingsImportAllPartial` | `settingsImportPartial` |
| `settingsImportAllFailed` | `settingsImportFailed` |

文案調整：

| 新 key | zh_Hant | zh_Hans | en |
|---|---|---|---|
| `settingsExportAccounts` | 匯出資料 | 导出数据 | Export data |
| `settingsImportAccounts` | 匯入資料 | 导入数据 | Import data |

`...Success` / `...Partial` / `...Failed` 僅改 key、內文不變。

#### 新增 key

| 新 key | zh_Hant | zh_Hans | en |
|---|---|---|---|
| `settingsExportSelectTitle` | 選擇要匯出的帳號 | 选择要导出的账号 | Select accounts to export |
| `settingsImportSelectTitle` | 選擇要匯入的帳號 | 选择要导入的账号 | Select accounts to import |
| `settingsImportOverwriteBadge` | 覆蓋 | 覆盖 | Overwrite |
| `accountsPickerSelectAll` | 全選 | 全选 | Select all |
| `accountRecordCount` | {n} 筆紀錄 | {n} 条记录 | {n} records |
| `confirmExport` | 匯出 | 导出 | Export |
| `confirmContinue` | 繼續 | 继续 | Continue |

`accountRecordCount` 用 `{n}` placeholder（`int`），不處理 ICU plural（YAGNI；現有 `progressDoneSummary` 等也只用單一表達）。

`accountLastUpdated` **重用**：picker 內顯示最後更新已有此 key，無需新增。

`accountsPickerSelectAll`、`confirmContinue`、`confirmExport` 為對話框 / global confirm 共用字串。`confirmExport` 放在既有 `confirmCancel` / `confirmDelete` / `confirmImport` 同層級。

#### l10n 生成

改完 arb 後跑 `flutter gen-l10n`，自動產 `lib/l10n/generated/*.dart`。**不手動編輯 generated 檔**。

### 6. Dart 識別子順帶調整

`settings_page.dart`：
- `_exportAll` → `_export`
- `_importAll` → `_import`

純內部 helper，沒外部 caller。

### 7. 測試

#### 新增

**`test/widgets/dialogs/accounts_picker_dialog_test.dart`**

- 初始狀態：所有帳號預設全勾、「全選」顯示 checked、確認按鈕 enabled。
- 取消單一帳號 → 「全選」變 indeterminate（tristate `null`）。
- 取消所有帳號 → 「全選」變 unchecked、確認按鈕 disabled。
- 點 indeterminate 「全選」→ 全部勾。
- 點 checked 「全選」→ 全部清空、確認按鈕 disabled。
- 「取消」回傳 `null`；確認回傳被勾的 UID list，順序與 `entries` 傳入一致。
- 帳號有別名 → 顯示為 `UID (alias)`；無別名 → 只顯示 UID。
- `badge != null` → 標籤可見；`badge == null` → 標籤不出現。
- `recordCount` 與 `lastUpdated` 顯示文字符合 l10n 預期。

#### 既有 test 改名 / 改動

- `test/services/all_accounts_export_test.dart` → `accounts_export_test.dart`，`exportAllAccounts` 改 `exportAccounts`。
- `test/services/all_accounts_import_test.dart` → `accounts_import_test.dart`，同上。
- `test/models/all_accounts_bundle_test.dart` → `accounts_bundle_test.dart`，`AllAccountsBundle` 改 `AccountsBundle`。
- `test/state/wish_repository_test.dart`：`importAllAccounts` 呼叫 + `AllAccountsBundle` import + 類名全部改。
- `exportAccounts` 測試補上「過濾子集」case：傳入只包含 2/3 UID 的 byUid map，斷言 JSON `accounts` 陣列僅含這兩個。

### 8. YAGNI / 不做的事

- 不為「只匯出活躍帳號」/「只匯出有覆蓋衝突的帳號」加快捷按鈕。
- 不在 picker 內顯示卡池細分（如各 banner 的紀錄數）；單一總筆數已夠。
- 不為過濾子集 case 改 `exportAccounts()` 簽名。
- 不重新命名 `ExportedAccount`。
- 不為 `accountRecordCount` 加 ICU plural；後續若有需求再補。
- 不在 `BannerStorage` 加新 `recordCount` getter（沿用 `allRecords.length`）。

### 9. 風險

- **大規模改名**：服務 / 模型 / repository / 6 個檔案路徑 + 多個類別 / 函式名，編譯器會抓出所有遺漏 import。`flutter analyze` + `flutter test` 必須全綠才能合。
- **i18n key rename**：忘了跑 `flutter gen-l10n` 會編譯失敗。
- **匯入 picker 與 confirm dialog 互動**：picker 是新階段，後面 confirm 仍要求輸入 `IMPORT`。flow 多一步點擊，但確認語意更明確（先看資訊挑帳號、再輸入字串敲定）。
- **JSON 格式**：仍是 schema_version 1，向後相容；不需要 migration。
