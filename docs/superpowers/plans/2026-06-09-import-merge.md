# Import Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「匯入全部資料」從整帳號覆蓋改為非破壞性合併——依 `GachaRecord.id` union 去重、永不丟本機資料、偏好只補空缺、放寬確認流程、回報新增/已存在筆數。

**Architecture:** 新增純函式合併原語 `BannerStorage.mergeWith`（記錄級 helper `_mergeRecordsById`）；`_runImport` 改成「本機沒有 → 直接存、已有 → mergeWith 後存」並統計 added/duplicate；`ImportResult` 改欄位；確認流程抽取既有內聯 confirm 成共用 `showConfirmDialog`（不重造輪子），picker badge 與文案改合併語意。

**Tech Stack:** Flutter / Dart、Riverpod、`flutter gen-l10n`（ARB 多語）、`flutter_test`。一律優先用 `fvm`（找不到再退回 `flutter`／`dart`）。

**規格依據：** `docs/superpowers/specs/2026-06-09-import-merge-design.md`。**分支：** `feat/import-merge`（已建立）。

---

## File Structure

| 檔案 | 角色 |
|------|------|
| `lib/models/banner_storage.dart` | 新增合併原語 `mergeWith` + `static _mergeRecordsById` |
| `test/models/banner_storage_test.dart` | **新建**：`mergeWith` 單元測試 |
| `lib/state/update_progress.dart` | `ImportResult` 欄位：`addedRecords`/`duplicateRecords`（移除 `totalRecords`） |
| `lib/state/gacha_repository.dart` | `_runImport` 合併邏輯＋計數＋偏好只補空缺＋兩處 log；`importAccountsAndFetchHoYoWiki` log 改欄位 |
| `lib/widgets/update_progress_dialog.dart` | 完成摘要改新欄位／新 `progressDoneImportSummary` 簽名 |
| `lib/widgets/dialogs/confirm_dialog.dart` | 新增無打字 `showConfirmDialog`（`isDanger` 參數） |
| `lib/widgets/dialogs/accounts_picker_dialog.dart` | `_PickerRow` badge 改中性色 |
| `lib/pages/settings_page.dart` | `_import` 改合併語意＋用 `showConfirmDialog`；`_clearGallery`／`_refetchAll` 改用共用 helper |
| `lib/l10n/app_*.arb`（9 個已翻譯語系） | 新增/改寫/刪除 key（見各 Task） |
| 既有測試 | `test/state/gacha_repository_test.dart`、`test/state/gacha_repository_import_with_hoyowiki_test.dart`、`test/widgets/dialogs/accounts_picker_dialog_test.dart`、`test/widgets/dialogs/confirm_dialog_test.dart` 改新語意 |

**已翻譯語系（其餘 22 個 ARB 為 Crowdin 空殼，不動）：** `app_zh.arb`(template)、`app_en.arb`、`app_es.arb`、`app_fr.arb`、`app_ja.arb`、`app_pt_BR.arb`、`app_th.arb`、`app_vi.arb`、`app_zh_Hans.arb`。

---

## Task 1: `BannerStorage.mergeWith` 合併原語

**Files:**
- Modify: `lib/models/banner_storage.dart`
- Test: `test/models/banner_storage_test.dart`（新建）

- [ ] **Step 1: 寫失敗測試**

建立 `test/models/banner_storage_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';

GachaRecord _r(String id, {String lang = 'zh-tw'}) => GachaRecord(
  id: id,
  uid: '100000001',
  gachaType: '301',
  name: 'x',
  itemType: '武器',
  rankType: 3,
  time: DateTime.utc(2025, 1, 1),
  lang: lang,
);

BannerStorage _s(
  Map<String, List<GachaRecord>> banners, {
  DateTime? lastUpdated,
}) => BannerStorage(
  uid: '100000001',
  lastUpdated: lastUpdated ?? DateTime.utc(2026, 1, 1),
  banners: banners,
);

void main() {
  test('union by id, dedup, sorted desc', () {
    final local = _s({
      '301': [_r('3'), _r('1')],
    });
    final incoming = _s({
      '301': [_r('2'), _r('1')],
    });
    final merged = local.mergeWith(incoming);
    expect(merged.banners['301']!.map((r) => r.id).toList(), ['3', '2', '1']);
  });

  test('banner keys are unioned', () {
    final local = _s({
      '301': [_r('1')],
    });
    final incoming = _s({
      '302': [_r('2')],
    });
    final merged = local.mergeWith(incoming);
    expect(merged.banners.keys.toSet(), {'301', '302'});
    expect(merged.banners['301']!.single.id, '1');
    expect(merged.banners['302']!.single.id, '2');
  });

  test('lastUpdated takes the newer of the two', () {
    final local = _s({'301': []}, lastUpdated: DateTime.utc(2026, 1, 1));
    final incoming = _s({'301': []}, lastUpdated: DateTime.utc(2026, 5, 12));
    expect(local.mergeWith(incoming).lastUpdated, DateTime.utc(2026, 5, 12));
    expect(incoming.mergeWith(local).lastUpdated, DateTime.utc(2026, 5, 12));
  });

  test('same id: keep local, but backfill empty local lang from incoming', () {
    final local = _s({
      '301': [_r('1', lang: '')],
    });
    final incoming = _s({
      '301': [_r('1', lang: 'en-us')],
    });
    final merged = local.mergeWith(incoming);
    expect(merged.banners['301']!.single.lang, 'en-us');
  });

  test('same id: non-empty local lang is NOT overwritten by incoming', () {
    final local = _s({
      '301': [_r('1', lang: 'zh-tw')],
    });
    final incoming = _s({
      '301': [_r('1', lang: 'en-us')],
    });
    final merged = local.mergeWith(incoming);
    expect(merged.banners['301']!.single.lang, 'zh-tw');
  });

  test('empty local merges to incoming content', () {
    final local = _s({});
    final incoming = _s({
      '301': [_r('2'), _r('1')],
    });
    final merged = local.mergeWith(incoming);
    expect(merged.banners['301']!.map((r) => r.id).toList(), ['2', '1']);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/models/banner_storage_test.dart`
Expected: FAIL（`mergeWith` 未定義 → 編譯錯誤）。

- [ ] **Step 3: 實作 `mergeWith` + `_mergeRecordsById`**

在 `lib/models/banner_storage.dart`，於 `copyWith`（約第 51-58 行）之後、`allRecords` getter 之前，新增：

```dart
  /// 將 [incoming]（同一 UID 的另一份存檔）合併進本份，回傳新的 [BannerStorage]。
  ///
  /// 逐 banner 依 [GachaRecord.id] union 去重後降序排序；本機既有記錄一律保留，
  /// 同 id 時保留本機那筆（若本機 lang 為空、[incoming] 非空則回填 lang）。
  /// [lastUpdated] 取兩者較新者。
  BannerStorage mergeWith(BannerStorage incoming) {
    final keys = {...banners.keys, ...incoming.banners.keys};
    final mergedBanners = <String, List<GachaRecord>>{
      for (final key in keys)
        key: _mergeRecordsById(
          banners[key] ?? const [],
          incoming.banners[key] ?? const [],
        ),
    };
    final newer = incoming.lastUpdated.isAfter(lastUpdated)
        ? incoming.lastUpdated
        : lastUpdated;
    return BannerStorage(uid: uid, lastUpdated: newer, banners: mergedBanners);
  }

  /// 合併兩條同 banner 的記錄：依 id union 去重（同 id 保留 [local]，必要時以
  /// [incoming] 的非空 lang 回填）→ 依 id 降序排序（id 等長 19 碼，字典序＝數值序）。
  static List<GachaRecord> _mergeRecordsById(
    List<GachaRecord> local,
    List<GachaRecord> incoming,
  ) {
    final byId = <String, GachaRecord>{};
    for (final r in local) {
      byId[r.id] = r;
    }
    for (final r in incoming) {
      final existing = byId[r.id];
      if (existing == null) {
        byId[r.id] = r;
      } else if (existing.lang.isEmpty && r.lang.isNotEmpty) {
        byId[r.id] = existing.copyWith(lang: r.lang);
      }
    }
    return byId.values.toList()..sort((a, b) => b.id.compareTo(a.id));
  }
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/models/banner_storage_test.dart`
Expected: PASS（6 個 test 全綠）。

- [ ] **Step 5: commit**

```bash
git add lib/models/banner_storage.dart test/models/banner_storage_test.dart
git commit -m "feat(import): add BannerStorage.mergeWith union-by-id primitive"
```

---

## Task 2: `_runImport` 合併邏輯 + `ImportResult` 欄位

把覆蓋改成合併、統計 added/duplicate、偏好只補空缺、active 保留本機，並改 `ImportResult` 欄位與下游摘要／log。此 Task 因欄位耦合需一次改到綠。

**Files:**
- Modify: `lib/state/update_progress.dart`（`ImportResult`）
- Modify: `lib/state/gacha_repository.dart`（`_runImport`、`importAccountsAndFetchHoYoWiki` log）
- Modify: `lib/widgets/update_progress_dialog.dart`（摘要呼叫）
- Modify: `lib/l10n/app_zh.arb` + 其餘 8 個已翻譯語系（`progressDoneImportSummary`）
- Test: `test/state/gacha_repository_test.dart`、`test/state/gacha_repository_import_with_hoyowiki_test.dart`

- [ ] **Step 1: 改 `ImportResult` 欄位**

`lib/state/update_progress.dart`，把 `ImportResult`（約 49-65 行）整段改為：

```dart
/// 帳號批次匯入的結果摘要。
class ImportResult {
  /// 建立 [ImportResult]。
  const ImportResult({
    required this.successAccounts,
    required this.addedRecords,
    required this.duplicateRecords,
    required this.failedUids,
  });

  /// 成功匯入的帳號數。
  final int successAccounts;

  /// 合併後新增的記錄數（備份中 id 本機原本沒有的）。
  final int addedRecords;

  /// 合併時已存在而略過的記錄數（備份中 id 本機原本就有的）。
  final int duplicateRecords;

  /// 匯入失敗的 UID 列表。
  final List<String> failedUids;
}
```

- [ ] **Step 2: 改寫 `_runImport` 的合併迴圈與計數**

`lib/state/gacha_repository.dart`，把 `_runImport` 開頭到帳號迴圈結束（約 665-692 行）改為：

```dart
  Future<ImportResult> _runImport(AccountsBundle bundle) async {
    final storage = ref.read(gachaStorageProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final newByUid = Map<String, BannerStorage>.from(state.byUid);
    final failed = <String>[];
    var addedRecords = 0;
    var duplicateRecords = 0;
    var successCount = 0;

    for (final account in bundle.accounts) {
      final incoming = account.data;
      try {
        final localBefore = newByUid[incoming.uid];
        final toSave = localBefore == null
            ? incoming
            : localBefore.mergeWith(incoming);
        await storage.save(toSave);
        if (!ref.mounted) {
          return ImportResult(
            successAccounts: successCount,
            addedRecords: addedRecords,
            duplicateRecords: duplicateRecords,
            failedUids: failed,
          );
        }
        final added =
            toSave.allRecords.length - (localBefore?.allRecords.length ?? 0);
        addedRecords += added;
        duplicateRecords += incoming.allRecords.length - added;
        newByUid[incoming.uid] = toSave;
        successCount++;
      } catch (_) {
        failed.add(incoming.uid);
      }
    }
```

- [ ] **Step 3: 改別名為「只補空缺」**

同檔，把別名段（約 694-704 行）改為：

```dart
    final currentSettings = ref.read(settingsProvider);
    final mergedAliases = Map<String, String>.from(currentSettings.uidAliases);
    for (final account in bundle.accounts) {
      final uid = account.data.uid;
      if (failed.contains(uid)) continue;
      if (mergedAliases.containsKey(uid)) continue; // 本機已有別名 → 保留
      final a = account.alias?.trim();
      if (a != null && a.isNotEmpty) {
        mergedAliases[uid] = a;
      }
    }
```

- [ ] **Step 4: 改 `uidOrder` 為「本機不動、新 UID 接最後」**

同檔，把排序段（約 706-714 行）改為：

```dart
    final localOrder = currentSettings.uidOrder;
    final localSet = localOrder.toSet();
    final appended = bundle.accounts
        .where((a) => !failed.contains(a.data.uid))
        .map((a) => a.data.uid)
        .where((uid) => !localSet.contains(uid))
        .toList(growable: false);
    final newOrder = [...localOrder, ...appended];
```

- [ ] **Step 5: 改 active 為「保留本機優先」**

同檔，把 active 計算段（約 716-726 行，`final desiredActive = ...` 到 `final newActive = ...`）改為：

```dart
    final localActive = state.activeUid;
    final desiredActive = bundle.lastActiveUid;
    final newActive =
        (localActive != null && newByUid.containsKey(localActive))
        ? localActive
        : (desiredActive != null && newByUid.containsKey(desiredActive))
        ? desiredActive
        : (newByUid.isEmpty
              ? null
              : (newOrder.isEmpty ? newByUid.keys.first : newOrder.first));
```

- [ ] **Step 6: 改兩處 `ImportResult` 建構與收尾 log**

同檔：

1. `_runImport` 的 unmount 提前返回（約 733-739 行，在 `applyImportedPreferences` 之後）改為帶 `addedRecords`/`duplicateRecords`：

```dart
    if (!ref.mounted) {
      return ImportResult(
        successAccounts: successCount,
        addedRecords: addedRecords,
        duplicateRecords: duplicateRecords,
        failedUids: failed,
      );
    }
```

2. 收尾 log（約 747-751 行）改為脫敏 + added/duplicate：

```dart
    _log.info(
      'import: success=$successCount '
      'failed=[${failed.map(sanitizeUid).join(",")}] '
      'added=$addedRecords duplicate=$duplicateRecords',
    );
```

3. 最終 return（約 752-756 行）改為：

```dart
    return ImportResult(
      successAccounts: successCount,
      addedRecords: addedRecords,
      duplicateRecords: duplicateRecords,
      failedUids: failed,
    );
```

4. `importAccountsAndFetchHoYoWiki` 的 log（約 608-612 行）改為：

```dart
      _importLog.info(
        'import done: success=${result.successAccounts} '
        'failed=[${result.failedUids.map(sanitizeUid).join(",")}] '
        'added=${result.addedRecords} duplicate=${result.duplicateRecords}',
      );
```

- [ ] **Step 7: 改 `progressDoneImportSummary` ARB（9 語系）**

`lib/l10n/app_zh.arb`（template），把 `progressDoneImportSummary`（約 164-171 行，含 `@` block）整段改為：

```json
  "progressDoneImportSummary": "已合併 {accounts} 個帳號：新增 {added} 筆、已存在 {duplicate} 筆",
  "@progressDoneImportSummary": {
    "description": "Completion dialog line shown when the import-then-fetch flow finishes: accounts merged, plus new vs already-present record counts.",
    "placeholders": {
      "accounts": { "type": "int" },
      "added": { "type": "int" },
      "duplicate": { "type": "int" }
    }
  },
```

其餘 8 個語系把 `progressDoneImportSummary` 的字串值改為下表（`app_en.arb` 連同其 `@` block 的 placeholders 一併補上 `added`/`duplicate`；其他語系僅改字串值即可，`@` block 非 template 不影響 codegen）：

| 語系 | 值 |
|------|----|
| en | `{accounts, plural, =1{Merged 1 account} other{Merged {accounts} accounts}}: {added} new, {duplicate} already present` |
| es | `{accounts, plural, =1{Se combinó 1 cuenta} other{Se combinaron {accounts} cuentas}}: {added} nuevos, {duplicate} ya existentes` |
| fr | `{accounts, plural, =1{1 compte fusionné} other{{accounts} comptes fusionnés}} : {added} nouveaux, {duplicate} déjà présents` |
| ja | `{accounts} 個のアカウントを結合しました：新規 {added} 件、既存 {duplicate} 件` |
| pt_BR | `{accounts, plural, =1{1 conta mesclada} other{{accounts} contas mescladas}}: {added} novos, {duplicate} já existentes` |
| th | `ผสาน {accounts} บัญชีแล้ว: ใหม่ {added} รายการ, มีอยู่แล้ว {duplicate} รายการ` |
| vi | `Đã hợp nhất {accounts} tài khoản: {added} mới, {duplicate} đã có` |
| zh_Hans | `已合并 {accounts} 个账号：新增 {added} 条、已存在 {duplicate} 条` |

- [ ] **Step 8: 改完成對話框呼叫點**

`lib/widgets/update_progress_dialog.dart`（約 233-239 行），把 `progressDoneImportSummary` 呼叫改為：

```dart
            if (importSummary != null)
              Text(
                l.progressDoneImportSummary(
                  importSummary.successAccounts,
                  importSummary.addedRecords,
                  importSummary.duplicateRecords,
                ),
              )
```

- [ ] **Step 9: 重新產生 l10n**

Run: `fvm flutter gen-l10n`
Expected: 無錯誤；`progressDoneImportSummary(int, int, int)` 生成於 `lib/l10n/generated/`。

- [ ] **Step 10: 改既有 repo 測試到合併語意（先讓它們表達新預期 → 紅）**

`test/state/gacha_repository_test.dart`：

(a) 測試 `importAccounts: per-UID overwrite preserves non-imported accounts`（約 1047-1127 行）：
- 改 test 名稱為 `importAccounts: merges into existing UID, preserves non-imported`。
- 在 `SharedPreferences.setMockInitialValues`（約 1066-1068 行）補上 `uidOrder`、`lastActiveUid` 使結果決定性：

```dart
      SharedPreferences.setMockInitialValues({
        'pref.uidAliases': jsonEncode({'100000003': '另一支'}),
        'pref.uidOrder': jsonEncode(['100000001', '100000003']),
        'pref.lastActiveUid': '100000001',
      });
```

- 把註解「`// 100000001 overwritten`」改成「`// 100000001 merged: lastUpdated takes newer`」（斷言值 `DateTime.utc(2026, 5, 12)` 不變，因 max(2026-01-01, 2026-05-12)）。
- 把 uidOrder 斷言（約 1124 行）改為完整新順序：

```dart
      expect(settings.uidOrder, ['100000001', '100000003', '100000002']);
```

(b) 測試 `importAccounts: uidOrder merges imported order first, then remaining`（約 1129-1193 行）：
- 改名為 `importAccounts: uidOrder keeps local order, appends new UIDs`。
- 把結尾斷言（約 1190-1191 行）改為：

```dart
      // local order [100000004, 100000001, 100000003] unchanged; new 100000002 appended
      expect(order, ['100000004', '100000001', '100000003', '100000002']);
```

(c) 測試 `importAccounts: bundle lastActiveUid switches active to it when imported`（約 1258-1314 行）：
- 改名為 `importAccounts: keeps local active when local active is valid`。
- 把結尾兩個斷言（約 1311-1312 行）改為：

```dart
      expect(container.read(gachaRepositoryProvider).activeUid, '200000001');
      expect(container.read(settingsProvider).lastActiveUid, '200000001');
```

(d) 在 (c) 之後新增一個互補測試（本機無 active → 採用備份 active），以及一個記錄級合併測試。貼在 (c) 的 `);` 之後：

```dart
  test(
    'importAccounts: adopts bundle lastActiveUid when local has no active',
    () async {
      final storage = GachaStorage(tempDir);
      final container = ProviderContainer(
        overrides: [
          gachaStorageProvider.overrideWithValue(storage),
          gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
          cancellableHttpClientFactoryProvider.overrideWithValue(
            () => CancellableHttpClient(
              client: MockClient((_) async => http.Response('{}', 200)),
              cancel: () {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(gachaRepositoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final bundle = AccountsBundle(
        exportedAt: DateTime.utc(2026, 5, 12),
        appVersion: 'x',
        lastActiveUid: '200000002',
        accounts: [
          ExportedAccount(
            data: BannerStorage(
              uid: '200000002',
              lastUpdated: DateTime.utc(2026, 5, 12),
              banners: const {'301': []},
            ),
          ),
        ],
      );

      await container
          .read(gachaRepositoryProvider.notifier)
          .debugImportOnly(bundle);

      expect(container.read(gachaRepositoryProvider).activeUid, '200000002');
    },
  );

  test(
    'importAccounts: merges records by id, never drops local, counts added/duplicate',
    () async {
      GachaRecord rec(String id) => GachaRecord(
        id: id,
        uid: '100000001',
        gachaType: '301',
        name: 'x',
        itemType: '武器',
        rankType: 3,
        time: DateTime.utc(2025, 1, 1),
        lang: 'zh-tw',
      );

      final storage = GachaStorage(tempDir);
      await storage.save(
        BannerStorage(
          uid: '100000001',
          lastUpdated: DateTime.utc(2026, 1, 1),
          banners: {
            '301': [rec('3'), rec('1')],
          },
        ),
      );

      final container = ProviderContainer(
        overrides: [
          gachaStorageProvider.overrideWithValue(storage),
          gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
          cancellableHttpClientFactoryProvider.overrideWithValue(
            () => CancellableHttpClient(
              client: MockClient((_) async => http.Response('{}', 200)),
              cancel: () {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(gachaRepositoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final bundle = AccountsBundle(
        exportedAt: DateTime.utc(2026, 5, 12),
        appVersion: 'x',
        lastActiveUid: null,
        accounts: [
          ExportedAccount(
            data: BannerStorage(
              uid: '100000001',
              lastUpdated: DateTime.utc(2026, 5, 12),
              banners: {
                '301': [rec('2'), rec('1')],
              },
            ),
          ),
        ],
      );

      final result = await container
          .read(gachaRepositoryProvider.notifier)
          .debugImportOnly(bundle);

      expect(result.addedRecords, 1); // id 2 是新的
      expect(result.duplicateRecords, 1); // id 1 已存在
      final merged = container
          .read(gachaRepositoryProvider)
          .byUid['100000001']!
          .banners['301']!
          .map((r) => r.id)
          .toList();
      expect(merged, ['3', '2', '1']); // 本機 id 3 沒被丟、降序
    },
  );
```

> 注意：若 `GachaRecord` 未在此測試檔 import，於檔頭補 `import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';`。

`test/state/gacha_repository_import_with_hoyowiki_test.dart`：
- 把 `totalRecords` 斷言（約 184 行）改為：

```dart
    expect(completed.importSummary!.addedRecords, 2);
    expect(completed.importSummary!.duplicateRecords, 0);
```

- 把空 bundle 的 `totalRecords` 斷言（約 230 行）改為：

```dart
    expect(completed.importSummary!.addedRecords, 0);
    expect(completed.importSummary!.duplicateRecords, 0);
```

- [ ] **Step 11: 跑相關測試確認通過**

Run: `fvm flutter test test/state/gacha_repository_test.dart test/state/gacha_repository_import_with_hoyowiki_test.dart`
Expected: PASS（含新合併語意、新計數測試）。

- [ ] **Step 12: commit**

```bash
git add lib/state/update_progress.dart lib/state/gacha_repository.dart lib/widgets/update_progress_dialog.dart lib/l10n/ test/state/gacha_repository_test.dart test/state/gacha_repository_import_with_hoyowiki_test.dart
git commit -m "feat(import): merge records by id instead of overwriting account"
```

---

## Task 3: 共用 `showConfirmDialog`（抽取既有內聯 confirm）

`settings_page.dart` 的 `_clearGallery`／`_refetchAll` 已各自手寫無打字 confirm。抽成共用 helper（不重造輪子），新匯入確認也用它。

**Files:**
- Modify: `lib/widgets/dialogs/confirm_dialog.dart`（新增 `showConfirmDialog`）
- Modify: `lib/pages/settings_page.dart`（`_clearGallery`、`_refetchAll` 改用）
- Test: `test/widgets/dialogs/confirm_dialog_test.dart`

- [ ] **Step 1: 寫失敗測試**

`test/widgets/dialogs/confirm_dialog_test.dart`，在最後一個 `testWidgets` 之後、`main` 的結尾 `}` 之前插入：

```dart
  testWidgets('showConfirmDialog: confirm enabled immediately, returns true', (
    tester,
  ) async {
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  confirmed = await showConfirmDialog(
                    context: ctx,
                    title: 'Merge',
                    body: 'About to merge',
                    cancelLabel: 'Cancel',
                    confirmLabel: 'Import',
                    confirmIcon: Icons.check,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // 無 TextField；確認鍵一開始就 enabled
    expect(find.byType(TextField), findsNothing);
    final confirmBtn = find.widgetWithText(FilledButton, 'Import');
    expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNotNull);

    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('showConfirmDialog: cancel returns false', (tester) async {
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  confirmed = await showConfirmDialog(
                    context: ctx,
                    title: 'Merge',
                    body: 'About to merge',
                    cancelLabel: 'Cancel',
                    confirmLabel: 'Import',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/dialogs/confirm_dialog_test.dart`
Expected: FAIL（`showConfirmDialog` 未定義）。

- [ ] **Step 3: 新增 `showConfirmDialog`**

`lib/widgets/dialogs/confirm_dialog.dart`，在 `showConfirmTypeDialog` 函式（約 29 行結束）之後新增：

```dart
/// 顯示一個一般確認 dialog（無打字閘）。
/// 回傳值：true = 確認 / false = 取消 / null = 系統 dismiss。
/// [isDanger] 為 true 時確認鍵用 danger 紅；false 時用預設（中性）配色。
Future<bool?> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String cancelLabel,
  required String confirmLabel,
  IconData? confirmIcon,
  bool isDanger = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final tokens = Theme.of(ctx).gacha;
      return AppDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: isDanger
                ? FilledButton.styleFrom(
                    backgroundColor: tokens.stateDanger,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: confirmIcon == null
                ? Text(confirmLabel)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(confirmIcon, size: 18),
                      const SizedBox(width: 8),
                      Text(confirmLabel),
                    ],
                  ),
          ),
        ],
      );
    },
  );
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/widgets/dialogs/confirm_dialog_test.dart`
Expected: PASS（既有打字測試 + 2 個新測試）。

- [ ] **Step 5: 把 `_clearGallery` 改用共用 helper**

`lib/pages/settings_page.dart`，把 `_clearGallery` 內的 `showDialog<bool>(...)`（約 784-804 行）整段替換為：

```dart
    final ok = await showConfirmDialog(
      context: ctx,
      title: l.confirmClearGalleryCacheTitle,
      body: l.confirmClearGalleryCacheBody(sizeText),
      cancelLabel: l.actionCancel,
      confirmLabel: l.confirmClearGalleryCacheConfirm,
      isDanger: true,
    );
```

- [ ] **Step 6: 把 `_refetchAll` 改用共用 helper**

同檔，把 `_refetchAll` 內的 `showDialog<bool>(...)`（約 825-845 行）整段替換為：

```dart
    final ok = await showConfirmDialog(
      context: ctx,
      title: l.confirmRefetchHoyoWikiTitle,
      body: l.confirmRefetchHoyoWikiBody,
      cancelLabel: l.actionCancel,
      confirmLabel: l.confirmRefetchHoyoWikiConfirm,
      isDanger: true,
    );
```

> 確認 `settings_page.dart` 已 import `confirm_dialog.dart`（既有 `showConfirmTypeDialog` 已在用，應已 import；若無則補）。

- [ ] **Step 7: 跑分析 + 相關測試**

Run: `fvm flutter analyze`
Expected: `No issues found!`
Run: `fvm flutter test test/widgets/dialogs/confirm_dialog_test.dart`
Expected: PASS

- [ ] **Step 8: commit**

```bash
git add lib/widgets/dialogs/confirm_dialog.dart lib/pages/settings_page.dart test/widgets/dialogs/confirm_dialog_test.dart
git commit -m "refactor(dialogs): extract shared showConfirmDialog from inline confirms"
```

---

## Task 4: `_import` 改合併語意 + picker badge 中性化 + ARB

**Files:**
- Modify: `lib/pages/settings_page.dart`（`_import`）
- Modify: `lib/widgets/dialogs/accounts_picker_dialog.dart`（`_PickerRow` badge 色）
- Modify: `lib/l10n/app_*.arb`（9 語系：新增/改寫/刪除）
- Test: `test/widgets/dialogs/accounts_picker_dialog_test.dart`

- [ ] **Step 1: ARB — 新增 / 改寫 / 刪除（先 template）**

`lib/l10n/app_zh.arb`：
- `settingsImportConfirmIntro`（約 439 行）字串改為：`"即將合併 {accounts} 個帳號（共 {records} 筆紀錄）："`（`@` block 不變）。
- 刪除 `settingsImportConfirmOverwriteHeader`（約 446 行）、`settingsImportConfirmWarning`（約 452 行）、`settingsImportOverwriteBadge`（約 475 行）整行。
- 新增 `settingsImportConfirmMergeHeader` 與 `settingsImportMergeBadge`。建議把 `settingsImportConfirmMergeHeader` 補在原 `settingsImportConfirmOverwriteHeader` 位置、`settingsImportMergeBadge` 補在原 `settingsImportOverwriteBadge` 位置：

```json
  "settingsImportConfirmMergeHeader": "下列帳號將與本機資料合併，不會刪除既有記錄：",
```
```json
  "settingsImportMergeBadge": "合併",
```

- [ ] **Step 2: ARB — 其餘 8 個已翻譯語系**

對 `app_en / app_es / app_fr / app_ja / app_pt_BR / app_th / app_vi / app_zh_Hans`：改 `settingsImportConfirmIntro`、刪 `settingsImportConfirmOverwriteHeader` + `settingsImportConfirmWarning` + `settingsImportOverwriteBadge`、新增 `settingsImportConfirmMergeHeader` + `settingsImportMergeBadge`，值如下表。

`settingsImportConfirmIntro`：

| 語系 | 值 |
|------|----|
| en | `About to merge {accounts} accounts ({records} records total):` |
| es | `A punto de combinar {accounts} cuentas ({records} registros en total):` |
| fr | `Sur le point de fusionner {accounts} comptes ({records} enregistrements au total) :` |
| ja | `{accounts} 個のアカウントを結合します（合計 {records} 件の記録）：` |
| pt_BR | `Prestes a mesclar {accounts} contas ({records} registros no total):` |
| th | `กำลังจะผสาน {accounts} บัญชี (รวม {records} ระเบียน):` |
| vi | `Sắp hợp nhất {accounts} tài khoản (tổng {records} bản ghi):` |
| zh_Hans | `即将合并 {accounts} 个账号（共 {records} 条记录）：` |

`settingsImportConfirmMergeHeader`：

| 語系 | 值 |
|------|----|
| en | `The following accounts will be merged with local data; existing records won't be deleted:` |
| es | `Las siguientes cuentas se combinarán con los datos locales; no se eliminarán los registros existentes:` |
| fr | `Les comptes suivants seront fusionnés avec les données locales ; les enregistrements existants ne seront pas supprimés :` |
| ja | `以下のアカウントはローカルデータと結合されます。既存の記録は削除されません：` |
| pt_BR | `As seguintes contas serão mescladas com os dados locais; os registros existentes não serão excluídos:` |
| th | `บัญชีต่อไปนี้จะถูกผสานกับข้อมูลในเครื่อง โดยจะไม่ลบระเบียนที่มีอยู่:` |
| vi | `Các tài khoản sau sẽ được hợp nhất với dữ liệu cục bộ; các bản ghi hiện có sẽ không bị xóa:` |
| zh_Hans | `以下账号将与本机数据合并，不会删除既有记录：` |

`settingsImportMergeBadge`：

| 語系 | 值 |
|------|----|
| en | `Merge` |
| es | `Combinar` |
| fr | `Fusionner` |
| ja | `結合` |
| pt_BR | `Mesclar` |
| th | `ผสาน` |
| vi | `Hợp nhất` |
| zh_Hans | `合并` |

- [ ] **Step 3: 重新產生 l10n**

Run: `fvm flutter gen-l10n`
Expected: 無錯誤；`settingsImportMergeBadge`、`settingsImportConfirmMergeHeader` getter 生成，舊三個 key 的 getter 消失。

- [ ] **Step 4: 改 `_import` badge → 合併**

`lib/pages/settings_page.dart`，把 picker entry 的 badge（約 556-558 行）改為：

```dart
          badge: existing.contains(a.data.uid)
              ? l.settingsImportMergeBadge
              : null,
```

- [ ] **Step 5: 改 `_import` 衝突區塊 + 移除警告 + 改確認 dialog**

同檔，把確認內文組裝與 dialog（約 608-632 行）整段改為：

```dart
    if (conflicts.isEmpty) {
      buf.writeln(l.settingsImportConfirmNoConflict);
    } else {
      buf.writeln(l.settingsImportConfirmMergeHeader);
      for (final uid in conflicts) {
        buf.writeln('  • $uid');
      }
    }
    if (preserved.isNotEmpty) {
      buf.writeln();
      buf.writeln(l.settingsImportConfirmPreserveFooter(preserved.join(', ')));
    }

    final ok = await showConfirmDialog(
      context: ctx,
      title: l.settingsImportConfirmTitle,
      body: buf.toString(),
      cancelLabel: l.actionCancel,
      confirmLabel: l.confirmImport,
      confirmIcon: Icons.check,
    );
    if (ok != true) return;
    if (!ctx.mounted) return;
```

> 此段移除了原本 `buf.writeln()` + `buf.write(l.settingsImportConfirmWarning)`（約 620-621 行）與 `showConfirmTypeDialog(... expectedText: 'IMPORT' ...)`。其餘 `_import`（檔案讀取、picker、`filteredBundle`、`incoming/conflicts/preserved`、`settingsImportConfirmIntro` 前言、fire-and-forget 呼叫）不變。

- [ ] **Step 6: picker badge 改中性色**

`lib/widgets/dialogs/accounts_picker_dialog.dart`，`_PickerRow.build` 的 badge `Container`（約 218-232 行），把兩處 `tokens.stateDanger` 改為 `tokens.accentPrimary`：

```dart
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: tokens.accentPrimary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: tokens.accentPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
```

同檔把 `AccountPickerEntry.badge` 的 dartdoc（約 31 行「可選的紅色警示徽章文字」）改為中性描述：

```dart
  /// 可選的徽章文字（如「合併」提示）。
```

- [ ] **Step 7: 改 picker 測試的 badge 文案**

`test/widgets/dialogs/accounts_picker_dialog_test.dart`：
- fixture（約 26 行）`badge: '覆蓋'` 改為 `badge: '合併'`。
- 測試 `overwrite badge shown only when entry.badge != null`（約 162-167 行）改名為 `badge shown only when entry.badge != null`，並把斷言（約 166 行）改為：

```dart
    expect(find.text('合併'), findsOneWidget);
```

- [ ] **Step 8: 跑分析 + 相關測試**

Run: `fvm flutter analyze`
Expected: `No issues found!`
Run: `fvm flutter test test/widgets/dialogs/accounts_picker_dialog_test.dart`
Expected: PASS

- [ ] **Step 9: commit**

```bash
git add lib/pages/settings_page.dart lib/widgets/dialogs/accounts_picker_dialog.dart lib/l10n/ test/widgets/dialogs/accounts_picker_dialog_test.dart
git commit -m "feat(import): non-destructive merge confirm flow and neutral badge"
```

---

## Task 5: 全套品質檢查

**Files:** 無（驗證）。

- [ ] **Step 1: 格式化**

Run: `fvm dart format lib/ test/`
Expected: 僅顯示被格式化的檔案數，無錯誤。

- [ ] **Step 2: 靜態分析**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全套測試**

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: 確認舊 key 無殘留引用**

Run: `git grep -n "settingsImportOverwriteBadge\|settingsImportConfirmWarning\|settingsImportConfirmOverwriteHeader"`
Expected: 在 `lib/` 與 `test/` 無命中（只可能殘留於 Crowdin 空殼 ARB——本計畫不動它們，可忽略；若 `lib/l10n/generated/` 仍有，表示 gen-l10n 未重跑）。

- [ ] **Step 5: 若 format 有改動則 commit**

```bash
git add -A
git commit -m "style(import): apply dart format"
```

（若 Step 1 無改動則略過。）

---

## 完成後

- 本計畫不主動 `git push`。
- 22 個 Crowdin 空殼語系的新 key 由 Crowdin pipeline 後補，不在本計畫手動處理。
- 後續若要驗證實機行為（匯入兩份重疊備份看記錄是否合併、確認框是否免打字），可用 `/run` 或 `/verify`。
