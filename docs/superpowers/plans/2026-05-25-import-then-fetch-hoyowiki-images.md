# Import-Then-Fetch HoYoWiki Images Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 設定頁匯入帳號資料完成後，自動接續一段「增量」HoYoWiki 圖片抓取，並用既有 `UpdateProgressDialog` 統一呈現「匯入了 N 個帳號 + 下載了 M 張圖」結果。

**Architecture:** 在 `GachaRepository` 新增 `importAccountsAndFetchHoYoWiki` 入口，內含完整 progress lifecycle（Preparing → import body → `_fetchHoYoWiki` → UpdateCompleted）。共用既有 `_isUpdating` / `_cancelTriggered` 互斥機制與 `_fetchHoYoWiki` 增量補圖三階段。`UpdateCompleted` 加 nullable `importSummary` 欄位讓既有 dialog 多顯示一行。`settings_page` 端只剩 fire-and-forget 呼叫。

**Tech Stack:** Flutter 3.x、Riverpod (NotifierProvider)、Dart sealed classes、logging 套件、flutter_test、MockClient (package:http/testing.dart)、SharedPreferences mock。

**Spec:** `docs/superpowers/specs/2026-05-25-import-then-fetch-hoyowiki-images-design.md`

---

## File Map

| 動作 | 路徑 | 說明 |
|---|---|---|
| Modify | `lib/state/update_progress.dart` | 新增 `ImportSummary` value class；`UpdateCompleted` 加 nullable `importSummary` 欄位 |
| Modify | `lib/state/gacha_repository.dart` | `importAccounts` body 抽 private `_runImport` + 加 `@visibleForTesting debugImportOnly`；新增 public `importAccountsAndFetchHoYoWiki` |
| Modify | `lib/widgets/update_progress_dialog.dart` | `_Body` 的 `UpdateCompleted` case 加 importSummary 分歧 |
| Modify | `lib/pages/settings_page.dart` | `_DataManagement._import` 末段改 fire-and-forget；匯入按鈕 disable 條件補 `progress != null` |
| Modify | `lib/l10n/app_zh.arb` (source) | 新增 `progressDoneImportSummary` / `progressPartialImportFailed` |
| Modify | `lib/l10n/{en, zh_Hans, ja, es, fr, pt_BR, th, vi}.arb` | 同步新增兩個 key |
| Modify | `test/state/gacha_repository_test.dart` | 既有 4 個 importAccounts test 的 caller rename 至 `debugImportOnly` |
| Create | `test/state/gacha_repository_import_with_hoyowiki_test.dart` | 5 個整合測試 case |
| Create | `test/pages/settings_page_import_button_test.dart` | 匯入按鈕 disable 邏輯 widget test |

---

## Task 1: 擴充 `UpdateProgress`（新增 `ImportSummary` 與 `UpdateCompleted.importSummary` 欄位）

**Files:**
- Modify: `lib/state/update_progress.dart`

純型別擴充，沒邏輯可測。後續 task 的測試會驗證新欄位的使用。

- [ ] **Step 1: 加入 `ImportSummary` value class 與 `UpdateCompleted.importSummary` 欄位**

在 `lib/state/update_progress.dart` 檔案頂端加 `import 'package:meta/meta.dart';`（若已有可略），然後修改如下：

```dart
import 'package:meta/meta.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/update_error.dart';

export 'package:genshin_impact_wish_gacha_analyzer/state/update_error.dart';

/// 更新進度狀態：準備中、等待捕獲、拉取中、完成、失敗。
sealed class UpdateProgress {
  const UpdateProgress();
}

// ... 中略 (Preparing / WaitingForCapture / FetchingBanner 保持不變) ...

/// 匯入流程的結果摘要，供 [UpdateCompleted] 在 dialog 顯示。
@immutable
class ImportSummary {
  /// 建立 [ImportSummary]。
  const ImportSummary({
    required this.successAccounts,
    required this.totalRecords,
    required this.failedUids,
  });

  /// 成功寫入 storage 的帳號數。
  final int successAccounts;

  /// 成功匯入的總祈願紀錄數。
  final int totalRecords;

  /// 寫入 storage 失敗的 UID 列表（空 list 表示全成功）。
  final List<String> failedUids;
}

/// 更新完成。
class UpdateCompleted extends UpdateProgress {
  /// 建立 [UpdateCompleted]。
  const UpdateCompleted({
    required this.totalNewRecords,
    required this.failedBanners,
    required this.updatedAt,
    required this.hoYoWikiImagesDownloaded,
    this.importSummary,
  });

  /// 本次更新新增的總紀錄數（update 流程用；import 流程為 0）。
  final int totalNewRecords;

  /// 拉取失敗的 banner 名稱 key 列表。
  final List<String> failedBanners;

  /// 更新完成時間（UTC）。
  final DateTime updatedAt;

  /// 本次補抓 HoYoWiki 圖片成功寫入磁碟的張數（icon + header 各算一張）。
  /// 既有圖檔已存在不重抓的不算；只計入本次新下載成功的張數。
  final int hoYoWikiImagesDownloaded;

  /// 匯入流程的結果摘要；非 import 入口為 null。
  final ImportSummary? importSummary;
}
```

`Preparing` / `WaitingForCapture` / `FetchingBanner` / `UpdateFailed` / `FetchingHoYoWiki` / `HoYoWikiPhase` 完全不動。

- [ ] **Step 2: 驗證仍可 build**

```bash
flutter analyze lib/state/update_progress.dart
```

Expected: `No issues found!`

- [ ] **Step 3: 跑既有測試確認沒踩到任何 caller**

```bash
flutter test test/state/gacha_repository_test.dart test/state/gacha_repository_refetch_test.dart test/state/gacha_repository_hoyowiki_test.dart
```

Expected: 全綠（因為 `importSummary` 是 nullable 預設 null，所有既有 `UpdateCompleted(...)` 呼叫不受影響）。

- [ ] **Step 4: Commit**

```bash
git add lib/state/update_progress.dart
git commit -m "feat(update-progress): add ImportSummary and UpdateCompleted.importSummary"
```

---

## Task 2: i18n 新增字串到 9 個成熟翻譯語系

**Files:**
- Modify: `lib/l10n/app_zh.arb`（source）
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_ja.arb`
- Modify: `lib/l10n/app_es.arb`
- Modify: `lib/l10n/app_fr.arb`
- Modify: `lib/l10n/app_pt_BR.arb`
- Modify: `lib/l10n/app_th.arb`
- Modify: `lib/l10n/app_vi.arb`

兩個新 key：`progressDoneImportSummary`（帶 accounts/records 兩個 int placeholder）與 `progressPartialImportFailed`（帶 uids String placeholder）。**插入位置**：在每個檔案內 `progressPartialFailed` 區塊之後（既有 `updateProgressHoyoWikiSearching` 之前）。

- [ ] **Step 1: 修改 `app_zh.arb`（source，簡潔風格）**

在 `progressPartialFailed` 區塊之後加：

```jsonc
  "progressDoneImportSummary": "本次匯入 {accounts} 個帳號（共 {records} 筆紀錄）",
  "@progressDoneImportSummary": {
    "description": "Completion dialog line shown when the import-then-fetch flow finishes: how many accounts and total records were imported in this run.",
    "placeholders": {
      "accounts": { "type": "int" },
      "records":  { "type": "int" }
    }
  },
  "progressPartialImportFailed": "⚠ 部分匯入失敗：{uids}",
  "@progressPartialImportFailed": {
    "description": "Completion dialog warning line shown when some UIDs failed to write to storage during import. uids is a comma-separated list.",
    "placeholders": { "uids": { "type": "String" } }
  },
```

- [ ] **Step 2: 修改 `app_zh_Hans.arb`**

在 `progressPartialFailed` 區塊之後加：

```jsonc
  "progressDoneImportSummary": "本次导入 {accounts} 个账号（共 {records} 条记录）",
  "@progressDoneImportSummary": {
    "description": "Completion dialog line shown when the import-then-fetch flow finishes: how many accounts and total records were imported in this run.",
    "placeholders": {
      "accounts": { "type": "int" },
      "records":  { "type": "int" }
    }
  },
  "progressPartialImportFailed": "⚠ 部分导入失败：{uids}",
  "@progressPartialImportFailed": {
    "description": "Completion dialog warning line shown when some UIDs failed to write to storage during import. uids is a comma-separated list.",
    "placeholders": { "uids": { "type": "String" } }
  },
```

- [ ] **Step 3: 修改 `app_en.arb`（帶 plural form）**

```jsonc
  "progressDoneImportSummary": "{accounts, plural, =1{Imported 1 account ({records} records)} other{Imported {accounts} accounts ({records} records)}}",
  "@progressDoneImportSummary": {
    "description": "Completion dialog line shown when the import-then-fetch flow finishes: how many accounts and total records were imported in this run.",
    "placeholders": {
      "accounts": { "type": "int" },
      "records":  { "type": "int" }
    }
  },
  "progressPartialImportFailed": "⚠ Partial import failure: {uids}",
  "@progressPartialImportFailed": {
    "description": "Completion dialog warning line shown when some UIDs failed to write to storage during import. uids is a comma-separated list.",
    "placeholders": {
      "uids": { "type": "String" }
    }
  },
```

- [ ] **Step 4: 修改 `app_ja.arb`**

```jsonc
  "progressDoneImportSummary": "{accounts} 件のアカウントをインポート（{records} 件の記録）",
  "@progressDoneImportSummary": {
    "description": "Completion dialog line shown when the import-then-fetch flow finishes: how many accounts and total records were imported in this run.",
    "placeholders": {
      "accounts": { "type": "int" },
      "records":  { "type": "int" }
    }
  },
  "progressPartialImportFailed": "⚠ 一部のインポートに失敗：{uids}",
  "@progressPartialImportFailed": {
    "description": "Completion dialog warning line shown when some UIDs failed to write to storage during import. uids is a comma-separated list.",
    "placeholders": {
      "uids": { "type": "String" }
    }
  },
```

- [ ] **Step 5: 修改 `app_es.arb`（plural form 對齊既有風格）**

```jsonc
  "progressDoneImportSummary": "{accounts, plural, =1{1 cuenta importada ({records} registros)} other{{accounts} cuentas importadas ({records} registros)}}",
  "@progressDoneImportSummary": {
    "description": "Completion dialog line shown when the import-then-fetch flow finishes: how many accounts and total records were imported in this run.",
    "placeholders": {
      "accounts": { "type": "int" },
      "records":  { "type": "int" }
    }
  },
  "progressPartialImportFailed": "⚠ Importación parcialmente fallida: {uids}",
  "@progressPartialImportFailed": {
    "description": "Completion dialog warning line shown when some UIDs failed to write to storage during import. uids is a comma-separated list.",
    "placeholders": {
      "uids": { "type": "String" }
    }
  },
```

- [ ] **Step 6: 修改 `app_fr.arb`（plural form）**

```jsonc
  "progressDoneImportSummary": "{accounts, plural, =1{1 compte importé ({records} enregistrements)} other{{accounts} comptes importés ({records} enregistrements)}}",
  "@progressDoneImportSummary": {
    "description": "Completion dialog line shown when the import-then-fetch flow finishes: how many accounts and total records were imported in this run.",
    "placeholders": {
      "accounts": { "type": "int" },
      "records":  { "type": "int" }
    }
  },
  "progressPartialImportFailed": "⚠ Échec partiel de l'import : {uids}",
  "@progressPartialImportFailed": {
    "description": "Completion dialog warning line shown when some UIDs failed to write to storage during import. uids is a comma-separated list.",
    "placeholders": {
      "uids": { "type": "String" }
    }
  },
```

- [ ] **Step 7: 修改 `app_pt_BR.arb`（plural form）**

```jsonc
  "progressDoneImportSummary": "{accounts, plural, =1{1 conta importada ({records} registros)} other{{accounts} contas importadas ({records} registros)}}",
  "@progressDoneImportSummary": {
    "description": "Completion dialog line shown when the import-then-fetch flow finishes: how many accounts and total records were imported in this run.",
    "placeholders": {
      "accounts": { "type": "int" },
      "records":  { "type": "int" }
    }
  },
  "progressPartialImportFailed": "⚠ Falha parcial na importação: {uids}",
  "@progressPartialImportFailed": {
    "description": "Completion dialog warning line shown when some UIDs failed to write to storage during import. uids is a comma-separated list.",
    "placeholders": {
      "uids": { "type": "String" }
    }
  },
```

- [ ] **Step 8: 修改 `app_th.arb`**

```jsonc
  "progressDoneImportSummary": "นำเข้า {accounts} บัญชี ({records} รายการ)",
  "@progressDoneImportSummary": {
    "description": "Completion dialog line shown when the import-then-fetch flow finishes: how many accounts and total records were imported in this run.",
    "placeholders": {
      "accounts": { "type": "int" },
      "records":  { "type": "int" }
    }
  },
  "progressPartialImportFailed": "⚠ การนำเข้าบางส่วนล้มเหลว: {uids}",
  "@progressPartialImportFailed": {
    "description": "Completion dialog warning line shown when some UIDs failed to write to storage during import. uids is a comma-separated list.",
    "placeholders": {
      "uids": { "type": "String" }
    }
  },
```

- [ ] **Step 9: 修改 `app_vi.arb`**

```jsonc
  "progressDoneImportSummary": "Đã nhập {accounts} tài khoản ({records} bản ghi)",
  "@progressDoneImportSummary": {
    "description": "Completion dialog line shown when the import-then-fetch flow finishes: how many accounts and total records were imported in this run.",
    "placeholders": {
      "accounts": { "type": "int" },
      "records":  { "type": "int" }
    }
  },
  "progressPartialImportFailed": "⚠ Nhập một phần thất bại: {uids}",
  "@progressPartialImportFailed": {
    "description": "Completion dialog warning line shown when some UIDs failed to write to storage during import. uids is a comma-separated list.",
    "placeholders": {
      "uids": { "type": "String" }
    }
  },
```

- [ ] **Step 10: 重新產生 generated localizations 並驗證**

```bash
flutter gen-l10n
flutter analyze
```

Expected：`gen-l10n` 無錯誤訊息、`analyze` 輸出 `No issues found!`。

- [ ] **Step 11: 跑全套測試確認 i18n 沒影響任何既有 widget**

```bash
flutter test
```

Expected: 全綠。

- [ ] **Step 12: Commit**

```bash
git add lib/l10n/app_zh.arb lib/l10n/app_zh_Hans.arb lib/l10n/app_en.arb lib/l10n/app_ja.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_pt_BR.arb lib/l10n/app_th.arb lib/l10n/app_vi.arb
git commit -m "i18n: add progressDoneImportSummary and progressPartialImportFailed (9 mature locales)"
```

---

## Task 3: 重構 `importAccounts` → `_runImport` + `debugImportOnly`

**Files:**
- Modify: `lib/state/gacha_repository.dart`
- Modify: `test/state/gacha_repository_test.dart`（4 個既有 importAccounts test 的 caller）

純機械重構：把現有 public `importAccounts(bundle)` body 抽成 private `_runImport`，加 `@visibleForTesting Future<ImportResult> debugImportOnly(...)`，刪除 public `importAccounts`。既有 4 個 test 改 caller name。

- [ ] **Step 1: `gacha_repository.dart` 重構**

在 `lib/state/gacha_repository.dart` 找到 `Future<ImportResult> importAccounts(AccountsBundle bundle) async { ... }`（現約 line 575）。

**做兩件事**：

1. **方法重新命名 + dartdoc 更新**：把方法簽名 `Future<ImportResult> importAccounts(AccountsBundle bundle) async {` 改為 `Future<ImportResult> _runImport(AccountsBundle bundle) async {`。方法 body 完全保留（包含：`storage.save` per-UID try/catch、`settingsNotifier` 取得、`mergedAliases` 計算、`exportedOrder` / `remaining` / `newOrder` 計算、`desiredActive` / `fallback` / `newActive` 計算、`settingsNotifier.applyImportedPreferences` 呼叫、`state.copyWith` 更新、結尾 `_log.info` 與 return）。**唯一改動只有方法名**。

2. **更新 dartdoc**（原本內容是「批次匯入 [AccountsBundle]，合併現有帳號資料與偏好設定。」），改為：

```dart
  /// 批次匯入 [AccountsBundle]，合併現有帳號資料與偏好設定。
  ///
  /// 純資料層操作，**不**啟動 progress 或 HoYoWiki 圖片抓取。
  /// 對外入口請用 [importAccountsAndFetchHoYoWiki]。
  Future<ImportResult> _runImport(AccountsBundle bundle) async {
```

3. **緊接在 `_runImport` 方法之後新增 testing-only 入口**：

```dart
  /// 測試用：暴露 [_runImport] 給單元測試（驗證純 import 邏輯，
  /// 不必 mock HoYoWiki fetcher）。生產勿用。
  @visibleForTesting
  Future<ImportResult> debugImportOnly(AccountsBundle bundle) =>
      _runImport(bundle);
```

4. **不需另刪舊 public `importAccounts`**：因為步驟 1 是 in-place rename，舊符號已不存在。

- [ ] **Step 2: 修改既有 4 個 importAccounts test 的 caller**

`test/state/gacha_repository_test.dart` 4 處（約 line 988, 1067, 1121, 1189）將：

```dart
final result = await container
    .read(gachaRepositoryProvider.notifier)
    .importAccounts(bundle);
```

改為：

```dart
final result = await container
    .read(gachaRepositoryProvider.notifier)
    .debugImportOnly(bundle);
```

其他斷言與 setup 完全不動。

- [ ] **Step 3: 跑這支 test 確認綠**

```bash
flutter test test/state/gacha_repository_test.dart
```

Expected: 全綠（含 4 個 importAccounts/debugImportOnly test 全 pass）。

- [ ] **Step 4: 跑 analyze 確認沒漏改的 caller**

```bash
flutter analyze
```

Expected: `No issues found!`。如有錯誤指向 `importAccounts` 不存在，回頭修。

- [ ] **Step 5: Commit**

```bash
git add lib/state/gacha_repository.dart test/state/gacha_repository_test.dart
git commit -m "refactor(gacha-repo): extract importAccounts body to _runImport + debugImportOnly"
```

---

## Task 4: TDD — 主路徑（bundle 含帳號 + 祈願 record，整段跑完 emit UpdateCompleted）

**Files:**
- Create: `test/state/gacha_repository_import_with_hoyowiki_test.dart`
- Modify: `lib/state/gacha_repository.dart`（新增 `importAccountsAndFetchHoYoWiki`）

照 `gacha_repository_refetch_test.dart` 樣板：用 `MockClient` 假 `search` / `entry_page` / image 三個端點。

- [ ] **Step 1: 寫失敗測試（檔案不存在 → 整個 test file 為新）**

建立 `test/state/gacha_repository_import_with_hoyowiki_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

GachaRecord _rec({
  required String id,
  required String uid,
  required String name,
  required String gachaType,
  String lang = 'en-us',
}) => GachaRecord(
  id: id,
  uid: uid,
  gachaType: gachaType,
  name: name,
  itemType: 'Character',
  rankType: 5,
  time: DateTime(2026, 5, 24),
  lang: lang,
);

http.Client _hoYoWikiMockClient({void Function(String keyword)? onSearch}) =>
    MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        final kw = req.url.queryParameters['keyword']!;
        onSearch?.call(kw);
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': kw,
                  'entry_page_id': 'eid_$kw',
                  'menu': {
                    'sub_menus': [
                      {'id': 2},
                    ],
                  },
                },
              ],
            },
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/entry_page')) {
        final id = req.url.queryParameters['entry_page_id']!;
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'page': {
                'icon_url': 'https://x/${id}_icon.png',
                'header_img_url': 'https://x/${id}_header.png',
              },
            },
          }),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });

Future<ProviderContainer> _bootstrap({
  required Directory tempDir,
  required http.Client apiClient,
}) async {
  final storage = GachaStorage(tempDir);
  final hoyowikiDir = Directory('${tempDir.path}/hoyowiki');
  await hoyowikiDir.create();
  final indexStorage = HoYoWikiIndexStorage(hoyowikiDir);

  final container = ProviderContainer(
    overrides: [
      gachaStorageProvider.overrideWithValue(storage),
      hoyowikiIndexStorageProvider.overrideWithValue(indexStorage),
      hoyowikiCacheDirProvider.overrideWithValue(hoyowikiDir),
      hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
      cancellableHttpClientFactoryProvider.overrideWithValue(
        () => CancellableHttpClient(client: apiClient, cancel: () {}),
      ),
    ],
  );
  await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
  await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
  return container;
}

void main() {
  test('主路徑：import + 增量補圖 → emit UpdateCompleted with importSummary',
      () async {
    final searchCalls = <String>[];
    final apiClient = _hoYoWikiMockClient(onSearch: searchCalls.add);

    final tempDir =
        await Directory.systemTemp.createTemp('gacha_import_main_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final container =
        await _bootstrap(tempDir: tempDir, apiClient: apiClient);
    addTearDown(container.dispose);

    // 構造 bundle：兩個帳號、各一筆祈願紀錄
    final bundle = AccountsBundle(
      exportedAt: DateTime.utc(2026, 5, 25),
      appVersion: 'x',
      lastActiveUid: '1001',
      accounts: [
        ExportedAccount(
          data: BannerStorage(
            uid: '1001',
            lastUpdated: DateTime.utc(2026, 5, 25),
            banners: {
              '301': [_rec(id: '1', uid: '1001', name: 'Hu Tao', gachaType: '301')],
              '302': [],
              '500': [],
              '200': [],
              '100': [],
            },
          ),
        ),
        ExportedAccount(
          data: BannerStorage(
            uid: '1002',
            lastUpdated: DateTime.utc(2026, 5, 25),
            banners: {
              '301': [],
              '302': [],
              '500': [],
              '200': [
                _rec(id: '2', uid: '1002', name: 'Skyward Harp', gachaType: '200'),
              ],
              '100': [],
            },
          ),
        ),
      ],
    );

    await container
        .read(gachaRepositoryProvider.notifier)
        .importAccountsAndFetchHoYoWiki(bundle);

    // 跨 UID 去重後 search 兩次
    expect(searchCalls.toSet(), {'Hu Tao', 'Skyward Harp'});

    // byUid 含兩個帳號
    final state = container.read(gachaRepositoryProvider);
    expect(state.byUid.keys.toSet(), {'1001', '1002'});

    // 結束 emit UpdateCompleted；importSummary 與圖片下載數齊全
    final progress = state.progress;
    expect(progress, isA<UpdateCompleted>());
    final completed = progress as UpdateCompleted;
    expect(completed.importSummary, isNotNull);
    expect(completed.importSummary!.successAccounts, 2);
    expect(completed.importSummary!.failedUids, isEmpty);
    expect(completed.importSummary!.totalRecords, 2);
    expect(
      completed.hoYoWikiImagesDownloaded,
      4,
      reason: 'Hu Tao + Skyward Harp，各 icon+header = 4 張',
    );
  });
}
```

- [ ] **Step 2: 跑測試確認 FAIL**

```bash
flutter test test/state/gacha_repository_import_with_hoyowiki_test.dart
```

Expected: FAIL，因為 `importAccountsAndFetchHoYoWiki` 不存在。錯誤訊息會類似 `The method 'importAccountsAndFetchHoYoWiki' isn't defined`。

- [ ] **Step 3: 在 `gacha_repository.dart` 新增 `importAccountsAndFetchHoYoWiki`**

於 `GachaRepository` 類別內、`forceRefetchAllHoYoWikiImages` 方法之後加入：

```dart
  /// Logger 實例（匯入流程，獨立子樹以利日誌過濾）。
  static final _importLog = Logger('gacha.import');

  /// 匯入帳號 bundle，並接續以增量方式抓取 HoYoWiki 圖片。
  ///
  /// 流程：
  ///   1. 互斥檢查：`state.progress != null` 直接 no-op。
  ///   2. emit `Preparing`、建 cancellable client。
  ///   3. 跑 [_runImport] 寫入 storage 與更新 settings。
  ///   4. 跑 [_fetchHoYoWiki] 三階段（best-effort，例外 warn-log）。
  ///   5. 結束一律 emit `UpdateCompleted(importSummary: ...)`，不論取消與否。
  ///      取消時 import 已寫入 storage 無法回滾，仍透過 dialog 告知使用者
  ///      「資料已匯入、圖片下載被略過」。
  Future<void> importAccountsAndFetchHoYoWiki(AccountsBundle bundle) async {
    if (state.progress != null) {
      _importLog.info('skip: another progress in-flight');
      return;
    }
    if (_isUpdating) return;
    _isUpdating = true;
    _cancelTriggered = false;
    _importLog.info('start, accounts=${bundle.accounts.length}');

    final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
    _activeCancellable = cancellable;
    state = state.copyWith(progress: const Preparing());

    try {
      final result = await _runImport(bundle);
      if (!ref.mounted) return;
      _importLog.info(
        'import done: success=${result.successAccounts} '
        'failed=[${result.failedUids.join(",")}] '
        'records=${result.totalRecords}',
      );

      var images = 0;
      try {
        images = await _fetchHoYoWiki(cancellable.client);
      } catch (e, st) {
        _importLog.warning('hoyowiki stage threw (ignored)', e, st);
      }
      if (!ref.mounted) return;

      if (_cancelTriggered) {
        _importLog.info('cancelled during hoyowiki, still emitting completed');
      }
      state = state.copyWith(
        progress: UpdateCompleted(
          totalNewRecords: 0,
          failedBanners: const [],
          updatedAt: DateTime.now().toUtc(),
          hoYoWikiImagesDownloaded: images,
          importSummary: ImportSummary(
            successAccounts: result.successAccounts,
            totalRecords: result.totalRecords,
            failedUids: result.failedUids,
          ),
        ),
      );
      _importLog.info('done, images=$images');
    } finally {
      _activeCancellable?.client.close();
      _activeCancellable = null;
      _cancelTriggered = false;
      _isUpdating = false;
    }
  }
```

- [ ] **Step 4: 跑測試確認 PASS**

```bash
flutter test test/state/gacha_repository_import_with_hoyowiki_test.dart
```

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/state/gacha_repository.dart test/state/gacha_repository_import_with_hoyowiki_test.dart
git commit -m "feat(gacha-repo): add importAccountsAndFetchHoYoWiki with main path test"
```

---

## Task 5: TDD — 空 bundle（不打 HoYoWiki API、emit UpdateCompleted with images=0）

**Files:**
- Modify: `test/state/gacha_repository_import_with_hoyowiki_test.dart`

- [ ] **Step 1: 在現有 test file 內加新 test case**

```dart
  test('空 bundle：不打 HoYoWiki API、emit UpdateCompleted with images=0',
      () async {
    var apiCalled = false;
    final apiClient = MockClient((req) async {
      apiCalled = true;
      return http.Response('', 404);
    });

    final tempDir =
        await Directory.systemTemp.createTemp('gacha_import_empty_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final container =
        await _bootstrap(tempDir: tempDir, apiClient: apiClient);
    addTearDown(container.dispose);

    final bundle = AccountsBundle(
      exportedAt: DateTime.utc(2026, 5, 25),
      appVersion: 'x',
      lastActiveUid: null,
      accounts: const [],
    );

    await container
        .read(gachaRepositoryProvider.notifier)
        .importAccountsAndFetchHoYoWiki(bundle);

    expect(apiCalled, isFalse, reason: '空 bundle 不該有任何 unique pair → 不打 API');
    final progress = container.read(gachaRepositoryProvider).progress;
    expect(progress, isA<UpdateCompleted>());
    final completed = progress as UpdateCompleted;
    expect(completed.hoYoWikiImagesDownloaded, 0);
    expect(completed.importSummary, isNotNull);
    expect(completed.importSummary!.successAccounts, 0);
    expect(completed.importSummary!.totalRecords, 0);
    expect(completed.importSummary!.failedUids, isEmpty);
  });
```

- [ ] **Step 2: 跑測試確認 PASS（這個 case 應該已能 pass，因為主路徑實作涵蓋）**

```bash
flutter test test/state/gacha_repository_import_with_hoyowiki_test.dart
```

Expected: 主路徑 + 空 bundle 兩個 case 都 PASS。如果空 bundle 失敗，回頭看 `_runImport` 或 `_fetchHoYoWiki` 是否能正確處理 empty。

- [ ] **Step 3: Commit**

```bash
git add test/state/gacha_repository_import_with_hoyowiki_test.dart
git commit -m "test(import-with-hoyowiki): cover empty bundle path"
```

---

## Task 6: TDD — 互斥（state.progress 非 null 時 no-op）

**Files:**
- Modify: `test/state/gacha_repository_import_with_hoyowiki_test.dart`

- [ ] **Step 1: 加 test case**

```dart
  test('互斥早退：state.progress 非 null 時 no-op', () async {
    final apiClient = MockClient((req) async => http.Response('', 404));
    final tempDir =
        await Directory.systemTemp.createTemp('gacha_import_mutex_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final container =
        await _bootstrap(tempDir: tempDir, apiClient: apiClient);
    addTearDown(container.dispose);

    final notifier = container.read(gachaRepositoryProvider.notifier);
    // 第一次：保持 reference 但不 await。
    final first = notifier.importAccountsAndFetchHoYoWiki(
      AccountsBundle(
        exportedAt: DateTime.utc(2026, 5, 25),
        appVersion: 'x',
        lastActiveUid: null,
        accounts: const [],
      ),
    );
    // 第二次：應立刻 no-op（早退）。
    final second = notifier.importAccountsAndFetchHoYoWiki(
      AccountsBundle(
        exportedAt: DateTime.utc(2026, 5, 25),
        appVersion: 'x',
        lastActiveUid: null,
        accounts: const [],
      ),
    );
    await Future.wait(<Future<void>>[first, second]);

    final progress = container.read(gachaRepositoryProvider).progress;
    expect(progress, isA<UpdateCompleted>(),
        reason: '第一次跑完應 emit UpdateCompleted；第二次 no-op 不會覆寫');
  });
```

- [ ] **Step 2: 跑測試確認 PASS**

```bash
flutter test test/state/gacha_repository_import_with_hoyowiki_test.dart
```

Expected: 互斥 case PASS（含先前 case 仍綠）。實作早就有 `if (state.progress != null) return;` 與 `_isUpdating` 保護。

- [ ] **Step 3: Commit**

```bash
git add test/state/gacha_repository_import_with_hoyowiki_test.dart
git commit -m "test(import-with-hoyowiki): cover mutex re-entry guard"
```

---

## Task 7: TDD — HoYoWiki 階段取消：仍 emit UpdateCompleted（importSummary 反映已寫入）

**Files:**
- Modify: `test/state/gacha_repository_import_with_hoyowiki_test.dart`

模擬：bundle import 完成後，呼叫 `cancelPreparing()` 設 `_cancelTriggered = true`，HoYoWiki 階段第一個 isAborted 檢查就早退。最終仍應 emit `UpdateCompleted`。

由於 `_runImport` 是同步在 single microtask 內 await 寫 storage，最務實的測法是直接在 import 動作完成、HoYoWiki 階段啟動「之前」就觸發 cancel。我們透過 `notifier.cancelPreparing()` 設旗標即可，因為 `_runImport` 不檢 cancel flag，HoYoWiki 進入後 `isAborted()` 才檢。

- [ ] **Step 1: 加 test case**

```dart
  test('HoYoWiki 階段取消：import 仍寫入、emit UpdateCompleted', () async {
    // 用一個會 hang 的 search endpoint，給我們時機呼叫 cancel
    final searchCalled = <String>[];
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        searchCalled.add(req.url.queryParameters['keyword']!);
        // 立刻回 404 讓 search 階段瞬間結束、進 entry 階段前 isAborted 檢查觸發
        return http.Response('', 404);
      }
      return http.Response.bytes([1, 2, 3], 200);
    });

    final tempDir =
        await Directory.systemTemp.createTemp('gacha_import_cancel_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final container =
        await _bootstrap(tempDir: tempDir, apiClient: apiClient);
    addTearDown(container.dispose);

    final bundle = AccountsBundle(
      exportedAt: DateTime.utc(2026, 5, 25),
      appVersion: 'x',
      lastActiveUid: '1001',
      accounts: [
        ExportedAccount(
          data: BannerStorage(
            uid: '1001',
            lastUpdated: DateTime.utc(2026, 5, 25),
            banners: {
              '301': [_rec(id: '1', uid: '1001', name: 'Hu Tao', gachaType: '301')],
              '302': [],
              '500': [],
              '200': [],
              '100': [],
            },
          ),
        ),
      ],
    );

    final notifier = container.read(gachaRepositoryProvider.notifier);
    final future = notifier.importAccountsAndFetchHoYoWiki(bundle);
    // 同 microtask 觸發 cancel：_runImport 已啟動，HoYoWiki 階段早退保證
    notifier.cancelPreparing();
    await future;

    final state = container.read(gachaRepositoryProvider);
    // import 不可回滾：byUid 仍包含 1001
    expect(state.byUid.containsKey('1001'), isTrue,
        reason: 'import 寫入無法回滾');
    final progress = state.progress;
    expect(progress, isA<UpdateCompleted>(),
        reason: '取消仍 emit UpdateCompleted（不像 forceRefetch 的 clearProgress）');
    final completed = progress as UpdateCompleted;
    expect(completed.importSummary, isNotNull);
    expect(completed.importSummary!.successAccounts, 1);
  });
```

- [ ] **Step 2: 跑測試確認 PASS**

```bash
flutter test test/state/gacha_repository_import_with_hoyowiki_test.dart
```

Expected: 取消 case PASS（含先前 case 仍綠）。

- [ ] **Step 3: Commit**

```bash
git add test/state/gacha_repository_import_with_hoyowiki_test.dart
git commit -m "test(import-with-hoyowiki): cancel during hoyowiki still emits completed"
```

---

## Task 8: TDD — 部分 UID 寫 storage 失敗（importSummary.failedUids 反映）

**Files:**
- Modify: `test/state/gacha_repository_import_with_hoyowiki_test.dart`

利用一個 `_ThrowingSaveStorage` fake：對特定 UID 寫入失敗，其他成功。

- [ ] **Step 1: 加 test case + fake storage**

在 `test/state/gacha_repository_import_with_hoyowiki_test.dart` 檔尾（`void main()` 區塊外）加 fake：

```dart
/// 對特定 UID 寫入時拋例外，用於測 partial-failure 路徑。
class _SelectiveFailureStorage extends GachaStorage {
  _SelectiveFailureStorage(super.baseDir, this._failUid);
  final String _failUid;

  @override
  Future<void> save(BannerStorage data) async {
    if (data.uid == _failUid) {
      throw const FileSystemException('simulated save failure');
    }
    return super.save(data);
  }
}
```

在 `main()` 內加：

```dart
  test('部分 UID 寫 storage 失敗：importSummary.failedUids 非空', () async {
    final apiClient = _hoYoWikiMockClient();

    final tempDir =
        await Directory.systemTemp.createTemp('gacha_import_partial_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final failStorage = _SelectiveFailureStorage(tempDir, '1002');
    final hoyowikiDir = Directory('${tempDir.path}/hoyowiki');
    await hoyowikiDir.create();
    final indexStorage = HoYoWikiIndexStorage(hoyowikiDir);

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(failStorage),
        hoyowikiIndexStorageProvider.overrideWithValue(indexStorage),
        hoyowikiCacheDirProvider.overrideWithValue(hoyowikiDir),
        hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

    final bundle = AccountsBundle(
      exportedAt: DateTime.utc(2026, 5, 25),
      appVersion: 'x',
      lastActiveUid: '1001',
      accounts: [
        ExportedAccount(
          data: BannerStorage(
            uid: '1001',
            lastUpdated: DateTime.utc(2026, 5, 25),
            banners: {
              '301': [_rec(id: '1', uid: '1001', name: 'Hu Tao', gachaType: '301')],
              '302': [],
              '500': [],
              '200': [],
              '100': [],
            },
          ),
        ),
        ExportedAccount(
          data: BannerStorage(
            uid: '1002',
            lastUpdated: DateTime.utc(2026, 5, 25),
            banners: {
              '301': [_rec(id: '2', uid: '1002', name: 'Other', gachaType: '301')],
              '302': [],
              '500': [],
              '200': [],
              '100': [],
            },
          ),
        ),
      ],
    );

    await container
        .read(gachaRepositoryProvider.notifier)
        .importAccountsAndFetchHoYoWiki(bundle);

    final progress = container.read(gachaRepositoryProvider).progress;
    expect(progress, isA<UpdateCompleted>());
    final completed = progress as UpdateCompleted;
    expect(completed.importSummary, isNotNull);
    expect(completed.importSummary!.successAccounts, 1);
    expect(completed.importSummary!.failedUids, ['1002']);
  });
```

- [ ] **Step 2: 跑測試確認 PASS**

```bash
flutter test test/state/gacha_repository_import_with_hoyowiki_test.dart
```

Expected: 5 個 case 全綠。`_runImport` 既有 try/catch per-UID 邏輯處理失敗。

- [ ] **Step 3: 跑全部新測試確認 5 個 case 都過**

```bash
flutter test test/state/gacha_repository_import_with_hoyowiki_test.dart
```

Expected: 5 個 case 全綠。

- [ ] **Step 4: Commit**

```bash
git add test/state/gacha_repository_import_with_hoyowiki_test.dart
git commit -m "test(import-with-hoyowiki): cover per-UID storage save failure"
```

---

## Task 9: Dialog `_Body` 加 `importSummary` 分歧顯示

**Files:**
- Modify: `lib/widgets/update_progress_dialog.dart`

`UpdateCompleted` 的 case 加 `importSummary` 分歧；若非 null，顯示 import summary 替代 `progressDoneSummary`，並在底部多加 partial-import-failed warning。

- [ ] **Step 1: 改 `_Body` build 內 `UpdateCompleted` case**

在 `lib/widgets/update_progress_dialog.dart` 找到 `UpdateCompleted(...)` 的 switch case（現約 line 223），改為：

```dart
      UpdateCompleted(
        :final totalNewRecords,
        :final failedBanners,
        :final hoYoWikiImagesDownloaded,
        :final importSummary,
      ) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (importSummary != null)
              Text(l.progressDoneImportSummary(
                importSummary.successAccounts,
                importSummary.totalRecords,
              ))
            else
              Text(l.progressDoneSummary(totalNewRecords)),
            const SizedBox(height: AppSpacing.xs),
            Text(l.progressDoneImagesSummary(hoYoWikiImagesDownloaded)),
            if (failedBanners.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                l.progressPartialFailed(
                  failedBanners.map(resolveBannerName).join('、'),
                ),
                style: TextStyle(color: tokens.stateDanger),
              ),
            ],
            if (importSummary != null && importSummary.failedUids.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                l.progressPartialImportFailed(
                  importSummary.failedUids.join(', '),
                ),
                style: TextStyle(color: tokens.stateDanger),
              ),
            ],
          ],
        ),
```

`_Title` / `_actions` 不動。

- [ ] **Step 2: 跑 analyze 確認沒漏掉新 i18n key**

```bash
flutter analyze lib/widgets/update_progress_dialog.dart
```

Expected: `No issues found!`。若爆 `progressDoneImportSummary` / `progressPartialImportFailed` 找不到，回頭驗證 Task 2 的 `flutter gen-l10n` 確實跑過。

- [ ] **Step 3: 跑 update_progress_dialog 相關既有 test（若存在）**

```bash
flutter test test/widgets/update_progress_dialog_test.dart 2>/dev/null || echo "(no dedicated test file; covered by integration)"
```

Expected: 沒有專屬測試檔；整合於 settings_page 與 repository test。

- [ ] **Step 4: 跑全套單元測試確認沒踩到既有 UpdateCompleted 渲染**

```bash
flutter test
```

Expected: 全綠。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/update_progress_dialog.dart
git commit -m "feat(update-progress-dialog): show import summary when present"
```

---

## Task 10: `settings_page._import` 改造 + 匯入按鈕 disable

**Files:**
- Modify: `lib/pages/settings_page.dart`

兩個改動：
1. `_import` 末段：移除 snackbar、改 fire-and-forget 呼叫 `importAccountsAndFetchHoYoWiki`。
2. 匯入按鈕 disable 條件補上 `progress != null`（既有 `_DataManagement.build` 已 watch `progress`）。

- [ ] **Step 1: 改 `_DataManagement.build` 內匯入按鈕 disable**

在 `lib/pages/settings_page.dart` 找到匯入按鈕（現約 line 362）：

```dart
OutlinedButton.icon(
  onPressed: () => _import(context, ref),
  icon: const Icon(Icons.upload_outlined, size: 18),
  label: Text(l.settingsImportData),
),
```

改為：

```dart
OutlinedButton.icon(
  onPressed: progress != null ? null : () => _import(context, ref),
  icon: const Icon(Icons.upload_outlined, size: 18),
  label: Text(l.settingsImportData),
),
```

`progress` 變數 build 內既已存在（從 `ref.watch(gachaRepositoryProvider.select((s) => s.progress))` 取得）。

- [ ] **Step 2: 改 `_import` 末段**

找到 `_import` 末段（confirm 通過後到 snackbar 那段，現約 line 615-649）。**刪除**：

```dart
    final result = await ref
        .read(gachaRepositoryProvider.notifier)
        .importAccounts(filteredBundle);
    if (!ctx.mounted) return;

    final SnackBar snack;
    if (result.failedUids.isEmpty) {
      Logger('accounts.io').info(
        'import: success=${result.successAccounts} '
        'records=${result.totalRecords}',
      );
      snack = SnackBar(
        content: Text(
          l.settingsImportSuccess(result.successAccounts, result.totalRecords),
        ),
      );
    } else {
      Logger('accounts.io').warning(
        'import partial: success=${result.successAccounts} '
        'failed=[${result.failedUids.join(",")}]',
      );
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
```

**替換**為：

```dart
    // fire-and-forget：progress dialog 由 app_shell 既有 ref.listen 自動接管。
    unawaited(
      ref
          .read(gachaRepositoryProvider.notifier)
          .importAccountsAndFetchHoYoWiki(filteredBundle),
    );
```

確認檔頭 `import 'dart:async';` 已存在（用於 `unawaited`），現約 line 1。若不存在請加。

- [ ] **Step 3: 跑 analyze**

```bash
flutter analyze lib/pages/settings_page.dart
```

Expected: `No issues found!`。如有「`settingsImportSuccess` / `settingsImportPartial` 未使用」這類 warning，**保留** i18n key（其他語系 fallback 可能仍引用，且此 PR 範圍不含 i18n 清理）。

- [ ] **Step 4: 跑既有 settings_page 相關測試**

```bash
flutter test test/pages/settings_page_refetch_button_test.dart
```

Expected: 全綠。

- [ ] **Step 5: Commit**

```bash
git add lib/pages/settings_page.dart
git commit -m "feat(settings-page): wire import to importAccountsAndFetchHoYoWiki + disable button during progress"
```

---

## Task 11: settings_page 匯入按鈕 disable widget test

**Files:**
- Create: `test/pages/settings_page_import_button_test.dart`

照 `test/pages/settings_page_refetch_button_test.dart` 樣板。

- [ ] **Step 1: 建立新 test 檔**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/settings_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

class _NullCapture implements GachaCapture {
  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(null), cancel: () async {});
}

Future<ProviderContainer> _setupContainer({
  required GachaStorage storage,
  required Directory tempDir,
}) async {
  final container = ProviderContainer(
    overrides: [
      gachaStorageProvider.overrideWithValue(storage),
      gachaCaptureProvider.overrideWithValue(_NullCapture()),
      cancellableHttpClientFactoryProvider.overrideWithValue(
        () => CancellableHttpClient(
          client: MockClient((_) async => http.Response('{}', 200)),
          cancel: () {},
        ),
      ),
      hoyowikiIndexStorageProvider.overrideWithValue(
        HoYoWikiIndexStorage(tempDir),
      ),
      hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      appVersionProvider.overrideWithValue('0.0.0-test'),
    ],
  );
  await container.read(settingsProvider.notifier).waitForLoad();
  container.read(gachaRepositoryProvider);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return container;
}

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'Hant'),
    theme: buildDarkTheme(),
    home: const Scaffold(body: SettingsPage()),
  ),
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('settings_import_btn_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('progress 為 null：匯入按鈕 enabled（無紀錄也可按）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _setupContainer(
        storage: GachaStorage(tempDir),
        tempDir: tempDir,
      );
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final btn = find.widgetWithText(OutlinedButton, '匯入資料');
    expect(btn, findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(btn).onPressed,
      isNotNull,
      reason: '匯入按鈕在 progress 為 null 時應 enabled（含無紀錄）',
    );
  });

  testWidgets('progress 非 null：匯入按鈕 disabled', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _setupContainer(
        storage: GachaStorage(tempDir),
        tempDir: tempDir,
      );
    });
    addTearDown(container.dispose);

    // 用 debug API 將 progress 設為 Preparing
    container
        .read(gachaRepositoryProvider.notifier)
        .debugSetProgress(const Preparing());

    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final btn = find.widgetWithText(OutlinedButton, '匯入資料');
    expect(btn, findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(btn).onPressed,
      isNull,
      reason: 'progress 非 null 時匯入按鈕應 disabled',
    );
  });
}
```

- [ ] **Step 2: 跑測試確認 PASS**

```bash
flutter test test/pages/settings_page_import_button_test.dart
```

Expected: 兩個 case 全綠。

注意：`debugSetProgress` 是 `gacha_repository.dart` line 950 既有的 `@visibleForTesting` API，可直接呼叫。

- [ ] **Step 3: Commit**

```bash
git add test/pages/settings_page_import_button_test.dart
git commit -m "test(settings-page): import button enabled/disabled wiring"
```

---

## Task 12: 提交前品質檢查（依 CLAUDE.md）

**Files:**（無檔案修改；純檢查）

依 CLAUDE.md 規定「提交前品質檢查」三件套必須全綠。

- [ ] **Step 1: 格式化**

```bash
dart format lib/ test/
```

Expected: 列出修改檔，或顯示無變動。**如果有 diff**，後續會被 commit 帶走。

- [ ] **Step 2: 靜態分析**

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: 全套測試**

```bash
flutter test
```

Expected: `All tests passed!`

- [ ] **Step 4: 若 Step 1 有變動則 commit**

```bash
git status
# 若 dart format 有改檔，加進去：
git add -u
git commit -m "style: dart format after import-with-hoyowiki feature"
```

如果 status clean 則略過 commit。

- [ ] **Step 5: 整支分支提交歷史 sanity check**

```bash
git log --oneline -15
```

Expected: 看到 6-8 個結構良好的 commit（task 1 / task 2 / task 3 / task 4 / task 5 / task 6 / task 7 / task 8 / task 9 / task 10 / task 11 / 可能 style）。

---

## 完成後手動驗證（不強制，但建議）

- [ ] 啟動 app（debug 或 release 皆可），到設定頁
- [ ] 用一份**真實**的匯出 JSON（或從另一個 UID 匯出的 backup）按「匯入資料」
- [ ] 觀察：
  - confirm dialog 出現 → 輸入 `IMPORT` 確認
  - **`UpdateProgressDialog` 立即彈出**，依序顯示 Preparing → 三階段 HoYoWiki progress
  - 結束時 dialog 顯示「本次匯入 N 個帳號（共 M 筆紀錄）」+「下載 K 張物品圖片」
  - 帳號清單已含新匯入的 UID、UI 顯示對應角色/武器圖片
- [ ] dialog 進行中匯入按鈕應為 disabled 狀態
