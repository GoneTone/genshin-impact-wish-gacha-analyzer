# 匯入時判別檔案是否由本軟體匯出 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 匯入時辨識並拒絕「非本軟體匯出」的備份檔（如姐妹專案鳴潮的檔），混合舊檔則只匯入可辨識的原神 banner。

**Architecture:** 匯出端寫入 `app` 識別欄位（純加法、不 bump schema_version）。匯入端在 `importAccounts` 內、`AccountsBundle.fromJson` 之前判別：顯式 `app` 相符 → 完整信任、不過濾；`app` 不符 → 丟新例外 `ForeignBundleException`；無 `app` 的舊檔 → 依卡池代碼是否屬於 `gachaTypes` 已知集合判別並濾掉未知 banner（純外來則拋例外）。UI 依型別顯示在地化原因。

**Tech Stack:** Flutter／Dart、FVM、ARB + `flutter gen-l10n`（template = `app_zh.arb`，輸出 `lib/l10n/generated/` 未進版控）。

> 設計來源：`docs/superpowers/specs/2026-06-09-import-foreign-app-detection-design.md`
> 此分支已含前一支功能（匯入／匯出錯誤在地化）：`importAccounts` 已有 `on UnsupportedSchemaVersionException`／`on FormatException`，`settings_page` 已有對應 catch 臂，ARB 已有 `importReason*`／`exportReasonWriteFailed`。
> 指令一律優先 `fvm flutter`／`fvm dart`；找不到 `fvm` 才退回 `flutter`／`dart`。Commit message 用英文 conventional commits；dartdoc／註解用繁中全形標點。不要 git push。

---

## 檔案結構

| 檔案 | 動作 | 責任 |
|------|------|------|
| `lib/models/accounts_bundle.dart` | Modify | 新增 `accountsBundleAppId` 常數；`toJson` 加寫 `app` 欄位 |
| `lib/services/accounts_import.dart` | Modify | 新增 `ForeignBundleException`；`importAccounts` 加身分判別兩條路 + `_screenLegacyBundle` helper |
| `lib/pages/settings_page.dart` | Modify | 匯入 catch 加 `on ForeignBundleException` → 在地化原因 |
| `lib/l10n/app_zh.arb` + 另 8 個已翻語系 | Modify | 新增 `importReasonForeignApp` |
| `test/models/accounts_bundle_test.dart` | Modify | `toJson` 含 `app` |
| `test/services/accounts_export_test.dart` | Modify | 匯出 JSON 含 `app` |
| `test/services/accounts_import_test.dart` | Modify | 身分判別／過濾／順序測試 |

已翻語系（要補 key 的 9 個）：`zh`（來源）、`en`、`fr`、`es`、`ja`、`vi`、`th`、`zh_Hans`、`pt_BR`。其餘約 22 個空殼 ARB **不要碰**。

---

## Task 1: 匯出端寫入 `app` 識別欄位

**Files:**
- Modify: `lib/models/accounts_bundle.dart`（檔頭加常數；`toJson` `:71-77`）
- Test: `test/models/accounts_bundle_test.dart`、`test/services/accounts_export_test.dart`

- [ ] **Step 1: 寫失敗測試（先紅）**

在 `test/models/accounts_bundle_test.dart` 的 `main()` 內、最後一個 `test(...)` 之後（檔尾 `}` 之前）加入：

```dart

  test('toJson includes the app identifier', () {
    final bundle = AccountsBundle(
      exportedAt: DateTime.utc(2026, 6, 9),
      appVersion: '1.0.0',
      lastActiveUid: null,
      accounts: const [],
    );
    expect(bundle.toJson()['app'], accountsBundleAppId);
  });
```

在 `test/services/accounts_export_test.dart` 第一個 test 的 `expect(decoded['schema_version'], 1);`（約 `:33`）下一行加入：

```dart
    expect(decoded['app'], accountsBundleAppId);
```

並在該檔 import 區塊（`:5` `accounts_export.dart` 那行之後）補上 model import 讓常數可見：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/models/accounts_bundle_test.dart test/services/accounts_export_test.dart`
Expected: FAIL — `Undefined name 'accountsBundleAppId'`（常數還沒建立）。

- [ ] **Step 3: 新增常數並寫入 toJson**

在 `lib/models/accounts_bundle.dart` 第 1 行 import 之後、`UnsupportedSchemaVersionException` 之前插入：

```dart

/// 本軟體的匯出識別字串，寫入備份檔的 `app` 欄位供匯入端辨識來源。
///
/// 值對齊 pubspec 套件名；姐妹專案（鳴潮）為 `wuthering_waves_convene_gacha_analyzer`，天生相異。
const String accountsBundleAppId = 'genshin_impact_wish_gacha_analyzer';
```

把 `AccountsBundle.toJson`（`:71-77`）改為（在 `schema_version` 後加 `app`）：

```dart
  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'app': accountsBundleAppId,
    'exported_at': exportedAt.toUtc().toIso8601String(),
    'app_version': appVersion,
    'last_active_uid': lastActiveUid,
    'accounts': accounts.map((a) => a.toJson()).toList(growable: false),
  };
```

`fromJson` 不需改（忽略未知欄位）。schema_version 維持 `1`。

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/models/accounts_bundle_test.dart test/services/accounts_export_test.dart`
Expected: PASS（既有 round-trip／export 測試仍綠）。

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/ test/
fvm flutter analyze
git add lib/models/accounts_bundle.dart test/models/accounts_bundle_test.dart test/services/accounts_export_test.dart
git commit -m "feat(export): tag exported bundles with app identifier"
```

---

## Task 2: `ForeignBundleException` + 身分判別與過濾（importAccounts）

**Files:**
- Modify: `lib/services/accounts_import.dart`
- Test: `test/services/accounts_import_test.dart`

- [ ] **Step 1: 寫失敗測試（先紅）**

在 `test/services/accounts_import_test.dart` 檔頭加入 `dart:convert` import（若尚無），確認已 import `accounts_bundle.dart`（前一支功能已加；若無則補）。在檔頭 import 區塊後、`void main()` 之前加入測試輔助：

```dart
Map<String, dynamic> _account(String uid, List<String> codes) => {
  'uid': uid,
  'last_updated': '2026-05-12T07:55:00.000Z',
  'banners': {for (final c in codes) c: <dynamic>[]},
};

Map<String, dynamic> _bundle({
  String? app,
  int schema = 1,
  required List<Map<String, dynamic>> accounts,
}) => {
  'schema_version': schema,
  if (app != null) 'app': app,
  'exported_at': '2026-05-12T08:30:00.000Z',
  'app_version': '1.0.0',
  'last_active_uid': null,
  'accounts': accounts,
};
```

在 `main()` 內、最後一個 `test(...)` 之後加入：

```dart

  test('explicit app mismatch → ForeignBundleException', () {
    final text = jsonEncode(
      _bundle(
        app: 'wuthering_waves_convene_gacha_analyzer',
        accounts: [_account('A', ['301'])],
      ),
    );
    expect(() => importAccounts(text), throwsA(isA<ForeignBundleException>()));
  });

  test('explicit app match → no filtering, unknown codes kept', () {
    final text = jsonEncode(
      _bundle(
        app: accountsBundleAppId,
        accounts: [
          _account('A', ['301', '600']),
        ],
      ),
    );
    final bundle = importAccounts(text);
    expect(bundle.accounts.single.data.banners.keys.toSet(), {'301', '600'});
  });

  test('legacy pure Genshin codes → all banners kept', () {
    final text = jsonEncode(
      _bundle(
        accounts: [
          _account('A', ['301', '302']),
        ],
      ),
    );
    final bundle = importAccounts(text);
    expect(bundle.accounts.single.data.banners.keys.toSet(), {'301', '302'});
  });

  test('legacy pure Wuthering Waves codes → ForeignBundleException', () {
    final text = jsonEncode(
      _bundle(
        accounts: [
          _account('A', ['1', '2', '7']),
        ],
      ),
    );
    expect(() => importAccounts(text), throwsA(isA<ForeignBundleException>()));
  });

  test('legacy mixed codes → unknown banners filtered, known kept', () {
    final text = jsonEncode(
      _bundle(
        accounts: [
          _account('A', ['301', '1']),
        ],
      ),
    );
    final bundle = importAccounts(text);
    expect(bundle.accounts.single.data.banners.keys.toSet(), {'301'});
  });

  test('legacy mixed → account left with only foreign codes is dropped', () {
    final text = jsonEncode(
      _bundle(
        accounts: [
          _account('A', ['301']),
          _account('B', ['1', '2']),
        ],
      ),
    );
    final bundle = importAccounts(text);
    expect(bundle.accounts.map((a) => a.data.uid).toList(), ['A']);
  });

  test('legacy empty accounts → not foreign, empty bundle', () {
    final text = jsonEncode(_bundle(accounts: []));
    final bundle = importAccounts(text);
    expect(bundle.accounts, isEmpty);
  });

  test('pure foreign with schema_version 999 → ForeignBundleException '
      '(precedes version check)', () {
    final text = jsonEncode(
      _bundle(
        schema: 999,
        accounts: [
          _account('A', ['1']),
        ],
      ),
    );
    expect(() => importAccounts(text), throwsA(isA<ForeignBundleException>()));
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/services/accounts_import_test.dart`
Expected: FAIL — `Undefined name 'ForeignBundleException'`（型別還沒建立）。

- [ ] **Step 3: 實作例外、判別與過濾**

在 `lib/services/accounts_import.dart` 的 import 區塊（`:5` `accounts_bundle.dart` 之後）加上：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
```

在 `_log` 定義之後、`importAccounts` 之前新增例外型別：

```dart
/// 匯入檔不是由本軟體匯出（`app` 識別碼不符，或舊檔卡池代碼非原神已知集合）時拋出。
class ForeignBundleException implements Exception {
  /// 建立 [ForeignBundleException]。
  const ForeignBundleException();

  @override
  String toString() => 'ForeignBundleException';
}
```

把 `importAccounts` 的 body 改為（在既有 `try { return AccountsBundle.fromJson(...) }` 之前插入身分判別，並把傳入改為 `prepared`）：

```dart
AccountsBundle importAccounts(String text) {
  Object? raw;
  try {
    raw = jsonDecode(text);
  } catch (e) {
    _log.warning('import failed: invalid JSON ($e)');
    throw const FormatException('Invalid JSON');
  }
  if (raw is! Map<String, dynamic>) {
    _log.warning('import failed: top-level not an object');
    throw const FormatException('Top-level value must be an object');
  }

  final app = raw['app'];
  final Map<String, dynamic> prepared;
  if (app is String) {
    if (app != accountsBundleAppId) {
      _log.warning('import failed: foreign bundle (app=$app)');
      throw const ForeignBundleException();
    }
    prepared = raw; // 本軟體自己的檔，完整信任、不過濾
  } else {
    prepared = _screenLegacyBundle(raw);
  }

  try {
    return AccountsBundle.fromJson(prepared);
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
}
```

在 `importAccounts` 之後新增 helper：

```dart
/// 處理無 `app` 欄位的舊備份：依卡池代碼判別是否為本軟體（原神）檔，並濾掉非原神 banner。
///
/// 蒐集 `accounts[*].banners` 的 key 與 [gachaTypes] 已知集合比對：確有卡池資料但無一是
/// 原神代碼 → 丟 [ForeignBundleException]（純外來，如鳴潮檔）；否則回傳濾除未知 banner 後的
/// raw（未知代碼的 banner 整條跳過、不解析其記錄，濾空的帳號一併移除），只留可辨識的原神 banner。
/// 讀不出任何卡池資料（空檔／結構模糊）→ 原樣交回，由 [AccountsBundle.fromJson] 後續處理。
Map<String, dynamic> _screenLegacyBundle(Map<String, dynamic> raw) {
  final known = {for (final t in gachaTypes) t.gachaType};
  final accountsRaw = raw['accounts'];
  if (accountsRaw is! List) return raw;

  var sawAnyCode = false;
  var keptAnyKnown = false;
  final filteredAccounts = <dynamic>[];
  for (final entry in accountsRaw) {
    if (entry is! Map<String, dynamic>) {
      filteredAccounts.add(entry);
      continue;
    }
    final bannersRaw = entry['banners'];
    if (bannersRaw is! Map<String, dynamic>) {
      filteredAccounts.add(entry);
      continue;
    }
    final keptBanners = <String, dynamic>{};
    for (final code in bannersRaw.keys) {
      sawAnyCode = true;
      if (known.contains(code)) {
        keptBanners[code] = bannersRaw[code];
        keptAnyKnown = true;
      }
    }
    if (keptBanners.isNotEmpty) {
      filteredAccounts.add({...entry, 'banners': keptBanners});
    }
  }

  if (sawAnyCode && !keptAnyKnown) {
    _log.warning('import failed: foreign bundle (no Genshin pools)');
    throw const ForeignBundleException();
  }
  return {...raw, 'accounts': filteredAccounts};
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/services/accounts_import_test.dart`
Expected: PASS（含既有 Invalid JSON／top-level array／`schema_version > 1 → UnsupportedSchemaVersionException` 三條——注意該條用空 `accounts`，會通過 `_screenLegacyBundle`（無代碼、不判外來）再撞版本檢查，仍綠）。

- [ ] **Step 5: Commit**

```bash
fvm dart format lib/ test/
fvm flutter analyze
git add lib/services/accounts_import.dart test/services/accounts_import_test.dart
git commit -m "feat(import): reject foreign-app bundles and filter unknown banners"
```

---

## Task 3: 新增 `importReasonForeignApp`（9 語系）+ gen-l10n

**Files:**
- Modify: `lib/l10n/app_zh.arb`、`app_en.arb`、`app_fr.arb`、`app_es.arb`、`app_ja.arb`、`app_vi.arb`、`app_th.arb`、`app_zh_Hans.arb`、`app_pt_BR.arb`

> 每個檔案：找到 `exportReasonWriteFailed` 那行，在其後緊接插入該語系的 `importReasonForeignApp` 行（同 2 空格縮排、行尾保留逗號——後面還有其他 key）。無 `@key` 區塊（比照同組 reason key）。**只改這 9 個檔案。**

- [ ] **Step 1: 9 檔各插入一行**

`app_zh.arb`（template）：
```json
  "importReasonForeignApp": "此檔案不是由本軟體匯出的備份",
```

`app_en.arb`：
```json
  "importReasonForeignApp": "This file was not exported by the app",
```

`app_fr.arb`：
```json
  "importReasonForeignApp": "Ce fichier n'a pas été exporté par cette application",
```

`app_es.arb`：
```json
  "importReasonForeignApp": "Este archivo no es una copia de seguridad exportada por la aplicación",
```

`app_ja.arb`：
```json
  "importReasonForeignApp": "このファイルは本ツールでエクスポートされたバックアップではありません",
```

`app_vi.arb`：
```json
  "importReasonForeignApp": "Tệp này không phải bản sao lưu được xuất từ ứng dụng này",
```

`app_th.arb`：
```json
  "importReasonForeignApp": "ไฟล์นี้ไม่ใช่ข้อมูลสำรองที่ส่งออกจากแอปนี้",
```

`app_zh_Hans.arb`：
```json
  "importReasonForeignApp": "此文件不是由本软件导出的备份",
```

`app_pt_BR.arb`：
```json
  "importReasonForeignApp": "Este arquivo de backup não foi exportado por este aplicativo",
```

- [ ] **Step 2: 重新產生 l10n**

Run: `fvm flutter gen-l10n`
Expected: 無錯誤；`lib/l10n/generated/app_localizations.dart` 重新產生（未進版控、不 commit）。

- [ ] **Step 3: 驗證 getter 與 ARB 合法**

確認 `lib/l10n/generated/app_localizations.dart` 出現 `String get importReasonForeignApp;`（grep）。
Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: 眼睛複查多位元組字串**

開 `app_zh.arb`、`app_ja.arb`、`app_th.arb` 確認三條多位元組字串完整、JSON 逗號正確、未加 `@` 區塊、未動其他 key。

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/
git commit -m "feat(l10n): add foreign-app import failure reason string"
```

---

## Task 4: UI —— `settings_page` 加 `on ForeignBundleException` 臂

**Files:**
- Modify: `lib/pages/settings_page.dart`（`importAccounts` catch，約 `:538-559`）

> `settings_page.dart` 已 import `services/accounts_import.dart`（`ForeignBundleException` 可見）與 `models/accounts_bundle.dart`，不需補 import。

- [ ] **Step 1: 在 importAccounts 的 try 後加第一個 catch 臂**

把：

```dart
    try {
      bundle = importAccounts(text);
    } on UnsupportedSchemaVersionException {
```

改為（在 `on UnsupportedSchemaVersionException` 之前插入 `on ForeignBundleException`）：

```dart
    try {
      bundle = importAccounts(text);
    } on ForeignBundleException {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(l.settingsImportFailed(l.importReasonForeignApp)),
        ),
      );
      return;
    } on UnsupportedSchemaVersionException {
```

（其餘 `on UnsupportedSchemaVersionException`／`on FormatException` 兩臂維持原樣。英文細節已於 `importAccounts` 內 `_log.warning`，UI 不重複 log。）

- [ ] **Step 2: 格式化**

Run: `fvm dart format lib/ test/`
Expected: 無錯誤。

- [ ] **Step 3: 靜態分析**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: 全套測試**

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/pages/settings_page.dart
git commit -m "fix(import): show localized reason for foreign-app backup files"
```

---

## Task 5: 最終驗收

- [ ] **Step 1: 全套品質檢查**

```bash
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
```

Expected：format 無變動、analyze `No issues found!`、test `All tests passed!`。

- [ ] **Step 2: 手動驗收**

匯入一個鳴潮備份檔（或把 `app` 改成別的字串／把 banner key 換成 `1`,`2` 的舊格式檔）確認顯示「此檔案不是由本軟體匯出的備份」（非英文、非「請更新 App」）；匯入正常原神檔仍成功。

> 不要主動 git push。

---

## Self-Review

**Spec coverage：**
- 匯出 `app` 識別欄位、不 bump schema_version → Task 1。✓
- 顯式 `app` 不符 → 拒絕；相符 → 不過濾 → Task 2 Step 3（`app is String` 分支）+ 測試。✓
- 舊檔 lenient + 過濾未知 banner、純外來拋例外、濾空帳號移除 → Task 2 `_screenLegacyBundle` + 測試。✓
- 判別在版本檢查之前（順序）→ Task 2（身分判別在 `fromJson` 之前）+ 「schema 999 純外來 → ForeignBundleException」測試。✓
- `ForeignBundleException` 型別 → Task 2。✓
- UI 在地化原因 → Task 4 + Task 3（`importReasonForeignApp` 9 語系）。✓
- analyze + test 全綠 → Task 4 Step 3-4、Task 5。✓

**Placeholder 掃描：** 無 TBD／TODO；每步含完整程式碼與實際譯文。✓

**型別一致性：** `accountsBundleAppId`（Task 1 定義 → Task 2 引用、測試引用）、`ForeignBundleException`（Task 2 定義 → Task 4 catch → Task 2 測試）、`_screenLegacyBundle`、`importReasonForeignApp`（Task 3 定義 → Task 4 引用）全程一致。✓

**不在範圍：** 姐妹專案（鳴潮 repo）加對應 `app` 欄位；既有 `UnsupportedSchemaVersionException`／其餘 reason key（前一支已處理）。
