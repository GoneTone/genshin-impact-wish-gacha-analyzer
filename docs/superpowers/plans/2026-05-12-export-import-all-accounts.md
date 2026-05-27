# Export / Import All Accounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the per-account JSON / CSV export and JSON import in the Settings page with a single "export / import all accounts" workflow that bundles every account's gacha data, aliases, sort order, and last-active UID into one JSON file. Import overwrites accounts that exist in the file but leaves untouched accounts alone (per-UID overwrite).

**Architecture:** Pure data layer (`AllAccountsBundle` value object) + two stateless services (`exportAllAccounts`, `importAllAccounts`) + a coordinator (`WishRepository.importAllAccounts`) that applies parsed bundles to storage and settings. UI parses first, then a `IMPORT`-typed confirm dialog shows the conflict list before apply.

**Tech Stack:** Flutter, Dart 3, Riverpod, `file_selector` (already in deps), `shared_preferences`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-05-12-export-import-all-accounts-design.md`

---

## File Structure

### Create

| Path | Responsibility |
|------|----------------|
| `lib/models/all_accounts_bundle.dart` | `AllAccountsBundle` + `ExportedAccount` value objects, `toJson` / `fromJson`. No I/O. |
| `lib/services/all_accounts_export.dart` | `exportAllAccounts(...)` — builds a bundle from app state, returns pretty-printed JSON string. |
| `lib/services/all_accounts_import.dart` | `importAllAccounts(String text)` — parses JSON into `AllAccountsBundle` with strict validation. |
| `test/models/all_accounts_bundle_test.dart` | Roundtrip + validation tests for the bundle. |
| `test/services/all_accounts_export_test.dart` | Order, alias, last-active correctness. |
| `test/services/all_accounts_import_test.dart` | Parse + error path tests. |

### Modify

| Path | Change |
|------|--------|
| `lib/state/settings.dart` | Add `applyImportedPreferences({...})` — atomic update of aliases + uidOrder + lastActiveUid (one `SettingsStorage.save`). |
| `lib/state/wish_repository.dart` | Add `ImportAllResult` + `importAllAccounts(AllAccountsBundle)`. Old `importData` is removed (UI no longer calls it). |
| `lib/pages/settings_page.dart` | `_DataManagement` button row: 4 → 2 (export all, import all) + the existing clear buttons. New `_exportAll` / `_importAll` handlers + conflict-aware confirm dialog. |
| `lib/l10n/app_zh_Hant.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_zh_Hans.arb` | Remove the 6 old keys, add 10 new keys (listed in Task 6). Other locales currently don't translate these keys; leave them as-is — Flutter falls back to the template. |
| `test/state/wish_repository_test.dart` | Add cases for `importAllAccounts` (per-UID overwrite, alias merge, order merge, last-active, partial failure). Remove cases using the deleted `importData` (none currently — `importData` was only called from UI). |
| `test/state/settings_test.dart` | Add a case for `applyImportedPreferences`. |

### Delete

| Path | Reason |
|------|--------|
| `lib/services/data_export.dart` | Replaced by `all_accounts_export.dart`. |
| `lib/services/data_import.dart` | Replaced by `all_accounts_import.dart`. |
| `test/services/data_export_test.dart` | Tests for deleted code. |
| `test/services/data_import_test.dart` | Tests for deleted code. |

### Commit order rationale

Each commit must leave `flutter analyze` and `flutter test` green. The order Task 1 → Task 8 honours this:

1. Tasks 1–5 add new pure-data + service + state code with their own tests; nothing in the UI calls it yet.
2. Task 6 adds new l10n keys **without removing old keys** (the UI still uses old keys at this point).
3. Task 7 switches the UI to call the new services and new l10n keys.
4. Task 8 deletes the now-unused old services, old tests, and old l10n keys.
5. Task 9 runs the full local check matrix.

---

## Task 1 — `AllAccountsBundle` model

**Files:**
- Create: `lib/models/all_accounts_bundle.dart`
- Test: `test/models/all_accounts_bundle_test.dart`

The model has two value objects:

```dart
class ExportedAccount {
  const ExportedAccount({required this.data, this.alias});
  final BannerStorage data; // already encapsulates uid, last_updated, banners
  final String? alias;      // null = no alias
}

class AllAccountsBundle {
  const AllAccountsBundle({
    required this.schemaVersion,
    required this.exportedAt,
    required this.appVersion,
    required this.lastActiveUid,
    required this.accounts,
  });
  final int schemaVersion;
  final DateTime exportedAt; // UTC
  final String appVersion;
  final String? lastActiveUid;
  final List<ExportedAccount> accounts; // order = export order
}
```

- [ ] **Step 1: Write failing roundtrip test**

```dart
// test/models/all_accounts_bundle_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/all_accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

WishRecord _r(String id, {String uid = '1'}) => WishRecord(
  id: id,
  uid: uid,
  gachaType: '301',
  name: '夜蘭',
  itemType: '角色',
  kind: WishItemKind.character,
  rankType: 5,
  time: DateTime.utc(2025, 4, 1, 14, 23),
  lang: 'zh-tw',
);

void main() {
  test('toJson / fromJson roundtrip preserves order, alias, last_active_uid', () {
    final bundle = AllAccountsBundle(
      schemaVersion: 1,
      exportedAt: DateTime.utc(2026, 5, 12, 8, 30),
      appVersion: '1.2.3',
      lastActiveUid: 'A',
      accounts: [
        ExportedAccount(
          alias: '主號',
          data: BannerStorage(
            uid: 'A',
            lastUpdated: DateTime.utc(2026, 5, 12, 7, 55),
            banners: {'301': [_r('1', uid: 'A')]},
          ),
        ),
        ExportedAccount(
          data: BannerStorage(
            uid: 'B',
            lastUpdated: DateTime.utc(2026, 5, 11, 20, 11),
            banners: const {'301': []},
          ),
        ),
      ],
    );

    final json = bundle.toJson();
    final back = AllAccountsBundle.fromJson(json);

    expect(back.schemaVersion, 1);
    expect(back.lastActiveUid, 'A');
    expect(back.accounts.map((a) => a.data.uid).toList(), ['A', 'B']);
    expect(back.accounts[0].alias, '主號');
    expect(back.accounts[1].alias, isNull);
    expect(back.accounts[0].data.banners['301']!.first.name, '夜蘭');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/all_accounts_bundle_test.dart`
Expected: FAIL — `all_accounts_bundle.dart` does not exist.

- [ ] **Step 3: Implement the model**

```dart
// lib/models/all_accounts_bundle.dart
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';

class ExportedAccount {
  const ExportedAccount({required this.data, this.alias});

  final BannerStorage data;
  final String? alias;

  Map<String, dynamic> toJson() {
    final base = data.toJson();
    if (alias != null && alias!.isNotEmpty) {
      base['alias'] = alias;
    }
    return base;
  }

  factory ExportedAccount.fromJson(Map<String, dynamic> json) {
    final rawAlias = json['alias'];
    final alias = (rawAlias is String && rawAlias.trim().isNotEmpty)
        ? rawAlias.trim()
        : null;
    return ExportedAccount(
      data: BannerStorage.fromJson(json),
      alias: alias,
    );
  }
}

class AllAccountsBundle {
  const AllAccountsBundle({
    required this.schemaVersion,
    required this.exportedAt,
    required this.appVersion,
    required this.lastActiveUid,
    required this.accounts,
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final DateTime exportedAt;
  final String appVersion;
  final String? lastActiveUid;
  final List<ExportedAccount> accounts;

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'exported_at': exportedAt.toUtc().toIso8601String(),
    'app_version': appVersion,
    'last_active_uid': lastActiveUid,
    'accounts': accounts.map((a) => a.toJson()).toList(growable: false),
  };

  factory AllAccountsBundle.fromJson(Map<String, dynamic> json) {
    final version = json['schema_version'];
    if (version is! int) {
      throw const FormatException('Missing or invalid "schema_version"');
    }
    if (version > currentSchemaVersion) {
      throw FormatException(
        'Unsupported schema version: $version. Please update the app.',
      );
    }

    final rawAccounts = json['accounts'];
    if (rawAccounts is! List) {
      throw const FormatException('Missing or invalid "accounts" array');
    }

    final accounts = <ExportedAccount>[];
    final seen = <String>{};
    for (var i = 0; i < rawAccounts.length; i++) {
      final entry = rawAccounts[i];
      if (entry is! Map<String, dynamic>) {
        throw FormatException('accounts[$i] must be an object');
      }
      ExportedAccount account;
      try {
        account = ExportedAccount.fromJson(entry);
      } catch (e) {
        throw FormatException('accounts[$i]: $e');
      }
      if (!seen.add(account.data.uid)) {
        throw FormatException('Duplicate UID in accounts: ${account.data.uid}');
      }
      accounts.add(account);
    }

    DateTime parsedExportedAt;
    final rawExportedAt = json['exported_at'];
    if (rawExportedAt is String) {
      try {
        parsedExportedAt = DateTime.parse(rawExportedAt);
      } catch (_) {
        parsedExportedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
    } else {
      parsedExportedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    final rawAppVersion = json['app_version'];
    final appVersion = rawAppVersion is String ? rawAppVersion : '';

    final rawLastActive = json['last_active_uid'];
    final lastActiveUid = rawLastActive is String ? rawLastActive : null;

    return AllAccountsBundle(
      schemaVersion: version,
      exportedAt: parsedExportedAt,
      appVersion: appVersion,
      lastActiveUid: lastActiveUid,
      accounts: accounts,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/all_accounts_bundle_test.dart`
Expected: PASS.

- [ ] **Step 5: Add error-path tests**

Append to `test/models/all_accounts_bundle_test.dart`:

```dart
  test('schema_version > 1 throws with "update the app" hint', () {
    final json = {
      'schema_version': 999,
      'exported_at': '2026-05-12T00:00:00.000Z',
      'app_version': '1.0.0',
      'last_active_uid': null,
      'accounts': <Map<String, dynamic>>[],
    };
    expect(
      () => AllAccountsBundle.fromJson(json),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('update the app'),
        ),
      ),
    );
  });

  test('missing schema_version throws', () {
    expect(
      () => AllAccountsBundle.fromJson({'accounts': []}),
      throwsA(isA<FormatException>()),
    );
  });

  test('accounts must be an array', () {
    expect(
      () => AllAccountsBundle.fromJson({
        'schema_version': 1,
        'accounts': 'nope',
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('duplicate UID throws', () {
    final accountJson = BannerStorage(
      uid: 'X',
      lastUpdated: DateTime.utc(2026),
      banners: const {'301': []},
    ).toJson();
    expect(
      () => AllAccountsBundle.fromJson({
        'schema_version': 1,
        'accounts': [accountJson, accountJson],
      }),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Duplicate UID'),
        ),
      ),
    );
  });

  test('alias empty string is read back as null', () {
    final bundle = AllAccountsBundle.fromJson({
      'schema_version': 1,
      'accounts': [
        {
          ...BannerStorage(
            uid: 'A',
            lastUpdated: DateTime.utc(2026),
            banners: const {'301': []},
          ).toJson(),
          'alias': '   ',
        },
      ],
    });
    expect(bundle.accounts.single.alias, isNull);
  });
```

- [ ] **Step 6: Run all bundle tests**

Run: `flutter test test/models/all_accounts_bundle_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 7: Commit**

```bash
dart format lib/models/all_accounts_bundle.dart test/models/all_accounts_bundle_test.dart
git add lib/models/all_accounts_bundle.dart test/models/all_accounts_bundle_test.dart
git commit -m "$(cat <<'EOF'
feat(models): add AllAccountsBundle for export/import payload

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2 — `exportAllAccounts` service

**Files:**
- Create: `lib/services/all_accounts_export.dart`
- Test: `test/services/all_accounts_export_test.dart`

Pure function: given current app state, return a `String` (pretty JSON). Order is computed via the existing `mergeUidOrder` helper.

- [ ] **Step 1: Write failing test**

```dart
// test/services/all_accounts_export_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/all_accounts_export.dart';

BannerStorage _bs(String uid, DateTime updated) => BannerStorage(
  uid: uid,
  lastUpdated: updated,
  banners: const {'301': [], '302': [], '100': [], '200': [], '500': []},
);

void main() {
  test('accounts order follows mergeUidOrder + inlines alias + lastActive', () {
    final byUid = {
      'A': _bs('A', DateTime.utc(2026, 5, 10)),
      'B': _bs('B', DateTime.utc(2026, 5, 12)),
      'C': _bs('C', DateTime.utc(2026, 5, 11)),
    };
    final out = exportAllAccounts(
      byUid: byUid,
      uidOrder: const ['C', 'A'], // custom order; B not in custom → goes by lastUpdated
      uidAliases: const {'A': '主號', 'C': '小號'},
      lastActiveUid: 'A',
      appVersion: '9.9.9',
      now: DateTime.utc(2026, 5, 12, 8, 30),
    );

    final decoded = jsonDecode(out) as Map<String, dynamic>;
    expect(decoded['schema_version'], 1);
    expect(decoded['app_version'], '9.9.9');
    expect(decoded['last_active_uid'], 'A');
    expect(decoded['exported_at'], '2026-05-12T08:30:00.000Z');

    final accounts = decoded['accounts'] as List<dynamic>;
    expect(accounts.map((a) => a['uid']).toList(), ['C', 'A', 'B']);
    expect(accounts[0]['alias'], '小號');
    expect(accounts[1]['alias'], '主號');
    expect(accounts[2].containsKey('alias'), isFalse);

    // pretty-printed → contains newlines + 2-space indent
    expect(out.contains('\n  '), isTrue);
  });
}
```

- [ ] **Step 2: Run to confirm it fails**

Run: `flutter test test/services/all_accounts_export_test.dart`
Expected: FAIL — `all_accounts_export.dart` not found.

- [ ] **Step 3: Implement**

```dart
// lib/services/all_accounts_export.dart
import 'dart:convert';

import 'package:genshin_impact_wish_gacha_analyzer/models/all_accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';

/// 把目前狀態打包成 [AllAccountsBundle] 並序列化成 pretty-printed JSON 字串。
///
/// 帳號順序套用 [mergeUidOrder]，與設定頁顯示順序一致。
String exportAllAccounts({
  required Map<String, BannerStorage> byUid,
  required List<String> uidOrder,
  required Map<String, String> uidAliases,
  required String? lastActiveUid,
  required String appVersion,
  required DateTime now,
}) {
  final ordered = mergeUidOrder(
    knownUids: byUid.keys,
    customOrder: uidOrder,
    lastUpdatedOf: (u) => byUid[u]!.lastUpdated,
  );

  final accounts = [
    for (final uid in ordered)
      ExportedAccount(
        data: byUid[uid]!,
        alias: uidAliases[uid],
      ),
  ];

  final bundle = AllAccountsBundle(
    schemaVersion: AllAccountsBundle.currentSchemaVersion,
    exportedAt: now.toUtc(),
    appVersion: appVersion,
    lastActiveUid: lastActiveUid,
    accounts: accounts,
  );

  return const JsonEncoder.withIndent('  ').convert(bundle.toJson());
}
```

- [ ] **Step 4: Run test to confirm pass**

Run: `flutter test test/services/all_accounts_export_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
dart format lib/services/all_accounts_export.dart test/services/all_accounts_export_test.dart
git add lib/services/all_accounts_export.dart test/services/all_accounts_export_test.dart
git commit -m "$(cat <<'EOF'
feat(services): add exportAllAccounts that bundles every account into one JSON

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3 — `importAllAccounts` service

**Files:**
- Create: `lib/services/all_accounts_import.dart`
- Test: `test/services/all_accounts_import_test.dart`

Thin wrapper over `AllAccountsBundle.fromJson` that normalises non-`FormatException` errors into `FormatException`.

- [ ] **Step 1: Write failing test**

```dart
// test/services/all_accounts_import_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/all_accounts_import.dart';

void main() {
  test('parses a minimal valid bundle', () {
    const text = '''
{
  "schema_version": 1,
  "exported_at": "2026-05-12T08:30:00.000Z",
  "app_version": "1.0.0",
  "last_active_uid": null,
  "accounts": []
}
''';
    final bundle = importAllAccounts(text);
    expect(bundle.schemaVersion, 1);
    expect(bundle.accounts, isEmpty);
  });

  test('not JSON → FormatException("Invalid JSON")', () {
    expect(
      () => importAllAccounts('definitely not json'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Invalid JSON'),
        ),
      ),
    );
  });

  test('top-level array → FormatException', () {
    expect(
      () => importAllAccounts('[]'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('object'),
        ),
      ),
    );
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/services/all_accounts_import_test.dart`
Expected: FAIL — service not found.

- [ ] **Step 3: Implement**

```dart
// lib/services/all_accounts_import.dart
import 'dart:convert';

import 'package:genshin_impact_wish_gacha_analyzer/models/all_accounts_bundle.dart';

/// 把 JSON 文字解析回 [AllAccountsBundle]。任何結構或型別不符都會
/// 統一拋出 [FormatException]，給 UI 顯示用。
AllAccountsBundle importAllAccounts(String text) {
  Object? raw;
  try {
    raw = jsonDecode(text);
  } catch (_) {
    throw const FormatException('Invalid JSON');
  }
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('Top-level value must be an object');
  }
  try {
    return AllAccountsBundle.fromJson(raw);
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('Failed to parse: $e');
  }
}
```

- [ ] **Step 4: Run test to confirm pass**

Run: `flutter test test/services/all_accounts_import_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
dart format lib/services/all_accounts_import.dart test/services/all_accounts_import_test.dart
git add lib/services/all_accounts_import.dart test/services/all_accounts_import_test.dart
git commit -m "$(cat <<'EOF'
feat(services): add importAllAccounts parser with strict validation

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4 — `SettingsNotifier.applyImportedPreferences`

**Files:**
- Modify: `lib/state/settings.dart`
- Modify: `test/state/settings_test.dart`

Atomic three-field update so the import flow only writes `SettingsStorage` once.

- [ ] **Step 1: Write failing test**

Append to `test/state/settings_test.dart` (inside the same `main()` block):

```dart
  test('applyImportedPreferences updates aliases + uidOrder + lastActiveUid '
      'and persists once', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(settingsProvider.notifier).applyImportedPreferences(
      aliases: const {'A': '主號', 'C': '小號'},
      uidOrder: const ['A', 'C', 'B'],
      lastActiveUid: 'A',
    );

    final state = container.read(settingsProvider);
    expect(state.uidAliases, {'A': '主號', 'C': '小號'});
    expect(state.uidOrder, ['A', 'C', 'B']);
    expect(state.lastActiveUid, 'A');

    final reloaded = await SettingsStorage.load();
    expect(reloaded.uidAliases, {'A': '主號', 'C': '小號'});
    expect(reloaded.uidOrder, ['A', 'C', 'B']);
    expect(reloaded.lastActiveUid, 'A');
  });

  test('applyImportedPreferences with null lastActiveUid clears it', () async {
    SharedPreferences.setMockInitialValues({
      'pref.lastActiveUid': 'OLD',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(settingsProvider.notifier).applyImportedPreferences(
      aliases: const {},
      uidOrder: const [],
      lastActiveUid: null,
    );

    expect(container.read(settingsProvider).lastActiveUid, isNull);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.lastActiveUid, isNull);
  });
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/state/settings_test.dart`
Expected: FAIL — `applyImportedPreferences` not defined.

- [ ] **Step 3: Implement in `lib/state/settings.dart`**

Add this method to `SettingsNotifier` (place it after `clearAllUidPreferences`, around line 74):

```dart
  /// 一次性把匯入後的偏好寫入：aliases、uidOrder、lastActiveUid。
  /// 三個欄位合併寫入單次 [SettingsStorage.save]，避免中途失敗造成裂腦狀態。
  Future<void> applyImportedPreferences({
    required Map<String, String> aliases,
    required List<String> uidOrder,
    required String? lastActiveUid,
  }) async {
    state = state.copyWith(
      uidAliases: Map.unmodifiable(aliases),
      uidOrder: List.unmodifiable(uidOrder),
      lastActiveUid: lastActiveUid,
      clearLastActiveUid: lastActiveUid == null,
    );
    await SettingsStorage.save(state);
  }
```

- [ ] **Step 4: Run test to confirm pass**

Run: `flutter test test/state/settings_test.dart`
Expected: PASS (all settings tests).

- [ ] **Step 5: Commit**

```bash
dart format lib/state/settings.dart test/state/settings_test.dart
git add lib/state/settings.dart test/state/settings_test.dart
git commit -m "$(cat <<'EOF'
feat(settings): add applyImportedPreferences for atomic import write

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5 — `WishRepository.importAllAccounts`

**Files:**
- Modify: `lib/state/wish_repository.dart`
- Modify: `test/state/wish_repository_test.dart`

Coordinator that:
1. Writes each account to storage (per-UID overwrite). Single failures skip that UID, continue.
2. Builds merged aliases (existing ∪ imported, imported wins; failed UIDs **not** applied).
3. Builds merged `uidOrder` (imported order first, then remaining custom-ordered UIDs that weren't in the bundle).
4. Picks `lastActiveUid` from bundle if it landed successfully, else keeps current, else first ordered.
5. Atomically commits settings via `applyImportedPreferences`, then updates `WishState`.

Returns an `ImportAllResult` so the UI can show partial-failure SnackBars.

- [ ] **Step 1: Write failing test — per-UID overwrite + preserve C**

Append to `test/state/wish_repository_test.dart`:

```dart
  test('importAllAccounts: per-UID overwrite preserves non-imported accounts', () async {
    final storage = WishStorage(tempDir);
    // Existing: A (old data), C (untouched)
    await storage.save(BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 1, 1),
      banners: const {'301': []},
    ));
    await storage.save(BannerStorage(
      uid: 'C',
      lastUpdated: DateTime.utc(2026, 1, 1),
      banners: const {'301': []},
    ));

    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final newA = BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 5, 12),
      banners: const {'301': [], '302': []},
    );
    final newB = BannerStorage(
      uid: 'B',
      lastUpdated: DateTime.utc(2026, 5, 12),
      banners: const {'301': []},
    );
    final bundle = AllAccountsBundle(
      schemaVersion: 1,
      exportedAt: DateTime.utc(2026, 5, 12),
      appVersion: 'x',
      lastActiveUid: 'A',
      accounts: [
        ExportedAccount(data: newA, alias: '主號'),
        ExportedAccount(data: newB),
      ],
    );

    final result = await container
        .read(wishRepositoryProvider.notifier)
        .importAllAccounts(bundle);

    expect(result.failedUids, isEmpty);
    expect(result.successAccounts, 2);

    final state = container.read(wishRepositoryProvider);
    expect(state.byUid.keys.toSet(), {'A', 'B', 'C'});
    // A overwritten
    expect(state.byUid['A']!.lastUpdated, DateTime.utc(2026, 5, 12));
    // C preserved
    expect(state.byUid['C']!.lastUpdated, DateTime.utc(2026, 1, 1));
    expect(state.activeUid, 'A');

    // Settings: alias on A, no alias on B/C; order = [A, B, ...]
    final settings = container.read(settingsProvider);
    expect(settings.uidAliases, {'A': '主號'});
    expect(settings.uidOrder.take(2).toList(), ['A', 'B']);
    expect(settings.lastActiveUid, 'A');
  });
```

Add imports at the top of the file if not already present:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/models/all_accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/state/wish_repository_test.dart --name "per-UID overwrite"`
Expected: FAIL — `importAllAccounts` not defined.

- [ ] **Step 3: Implement `ImportAllResult` + `importAllAccounts` in `lib/state/wish_repository.dart`**

Add this class near the top of the file (after the `_NoRecordsException` declaration):

```dart
class ImportAllResult {
  const ImportAllResult({
    required this.successAccounts,
    required this.totalRecords,
    required this.failedUids,
  });

  final int successAccounts;
  final int totalRecords;
  final List<String> failedUids;
}
```

Add this method on `WishRepository` (place it right after the existing `importData` method, then **delete** `importData` — UI no longer needs it):

```dart
  Future<ImportAllResult> importAllAccounts(AllAccountsBundle bundle) async {
    final storage = ref.read(wishStorageProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final newByUid = Map<String, BannerStorage>.from(state.byUid);
    final failed = <String>[];
    var totalRecords = 0;
    var successCount = 0;

    for (final account in bundle.accounts) {
      try {
        await storage.save(account.data);
        if (!ref.mounted) {
          return ImportAllResult(
            successAccounts: successCount,
            totalRecords: totalRecords,
            failedUids: failed,
          );
        }
        newByUid[account.data.uid] = account.data;
        successCount++;
        for (final list in account.data.banners.values) {
          totalRecords += list.length;
        }
      } catch (_) {
        failed.add(account.data.uid);
      }
    }

    final currentSettings = ref.read(settingsProvider);
    final mergedAliases = Map<String, String>.from(currentSettings.uidAliases);
    for (final account in bundle.accounts) {
      if (failed.contains(account.data.uid)) continue;
      final a = account.alias?.trim();
      if (a == null || a.isEmpty) {
        mergedAliases.remove(account.data.uid);
      } else {
        mergedAliases[account.data.uid] = a;
      }
    }

    final exportedOrder = bundle.accounts
        .where((a) => !failed.contains(a.data.uid))
        .map((a) => a.data.uid)
        .toList();
    final exportedSet = exportedOrder.toSet();
    final remaining = currentSettings.uidOrder
        .where((u) => !exportedSet.contains(u))
        .toList();
    final newOrder = [...exportedOrder, ...remaining];

    final desiredActive = bundle.lastActiveUid;
    final fallback = state.activeUid != null && newByUid.containsKey(state.activeUid)
        ? state.activeUid
        : (newByUid.isEmpty ? null : (newOrder.isEmpty ? newByUid.keys.first : newOrder.first));
    final newActive = (desiredActive != null && newByUid.containsKey(desiredActive))
        ? desiredActive
        : fallback;

    await settingsNotifier.applyImportedPreferences(
      aliases: mergedAliases,
      uidOrder: newOrder,
      lastActiveUid: newActive,
    );
    if (!ref.mounted) {
      return ImportAllResult(
        successAccounts: successCount,
        totalRecords: totalRecords,
        failedUids: failed,
      );
    }

    state = state.copyWith(
      byUid: newByUid,
      activeUid: newActive,
      clearActiveUid: newActive == null,
    );

    return ImportAllResult(
      successAccounts: successCount,
      totalRecords: totalRecords,
      failedUids: failed,
    );
  }
```

Also **remove** the old `importData` method (lines 377–386 in the current file) since the UI no longer calls it.

At the top of the file, add the import:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/models/all_accounts_bundle.dart';
```

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/state/wish_repository_test.dart --name "per-UID overwrite"`
Expected: PASS.

- [ ] **Step 5: Add order-merge test**

Append to `test/state/wish_repository_test.dart`:

```dart
  test('importAllAccounts: uidOrder merges imported order first, then remaining', () async {
    final storage = WishStorage(tempDir);
    for (final uid in ['A', 'C', 'D']) {
      await storage.save(BannerStorage(
        uid: uid,
        lastUpdated: DateTime.utc(2026, 1, 1),
        banners: const {'301': []},
      ));
    }

    SharedPreferences.setMockInitialValues({
      'pref.uidOrder': jsonEncode(['D', 'A', 'C']),
    });

    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final bundle = AllAccountsBundle(
      schemaVersion: 1,
      exportedAt: DateTime.utc(2026, 5, 12),
      appVersion: 'x',
      lastActiveUid: null,
      accounts: [
        ExportedAccount(data: BannerStorage(
          uid: 'B',
          lastUpdated: DateTime.utc(2026, 5, 12),
          banners: const {'301': []},
        )),
        ExportedAccount(data: BannerStorage(
          uid: 'A',
          lastUpdated: DateTime.utc(2026, 5, 12),
          banners: const {'301': []},
        )),
      ],
    );

    await container.read(wishRepositoryProvider.notifier).importAllAccounts(bundle);

    final order = container.read(settingsProvider).uidOrder;
    // imported [B, A] first, then remaining custom order minus imported = [D, C]
    expect(order, ['B', 'A', 'D', 'C']);
  });
```

- [ ] **Step 6: Add partial-failure test**

Append:

```dart
  test('importAllAccounts: storage write failure marks UID failed and skips it', () async {
    // Inject a storage that fails on UID == "B"
    final storage = _FailingStorage(tempDir, failOnUid: 'B');
    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final bundle = AllAccountsBundle(
      schemaVersion: 1,
      exportedAt: DateTime.utc(2026, 5, 12),
      appVersion: 'x',
      lastActiveUid: 'B',
      accounts: [
        ExportedAccount(data: BannerStorage(
          uid: 'A',
          lastUpdated: DateTime.utc(2026, 5, 12),
          banners: const {'301': []},
        ), alias: '主號'),
        ExportedAccount(data: BannerStorage(
          uid: 'B',
          lastUpdated: DateTime.utc(2026, 5, 12),
          banners: const {'301': []},
        )),
      ],
    );

    final result = await container
        .read(wishRepositoryProvider.notifier)
        .importAllAccounts(bundle);

    expect(result.failedUids, ['B']);
    expect(result.successAccounts, 1);

    final state = container.read(wishRepositoryProvider);
    expect(state.byUid.keys, ['A']);
    // lastActiveUid asked for B (failed) → falls back to A
    expect(state.activeUid, 'A');
    // uidOrder doesn't contain failed B
    expect(container.read(settingsProvider).uidOrder.contains('B'), isFalse);
  });
```

Add the `_FailingStorage` helper at the bottom of the file (above `void main()` is fine too):

```dart
class _FailingStorage extends WishStorage {
  _FailingStorage(super.baseDir, {required this.failOnUid});
  final String failOnUid;

  @override
  Future<void> save(BannerStorage data) async {
    if (data.uid == failOnUid) {
      throw Exception('simulated failure');
    }
    return super.save(data);
  }
}
```

- [ ] **Step 7: Run all repository tests**

Run: `flutter test test/state/wish_repository_test.dart`
Expected: PASS (existing + 3 new tests).

- [ ] **Step 8: Commit**

```bash
dart format lib/state/wish_repository.dart test/state/wish_repository_test.dart
git add lib/state/wish_repository.dart test/state/wish_repository_test.dart
git commit -m "$(cat <<'EOF'
feat(repo): add importAllAccounts with per-UID overwrite and partial failure

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6 — l10n: add new keys (do not remove old yet)

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`

The UI in Task 7 needs new strings. We add them first **without removing the old ones**, so Task 6's commit stays green (no UI change yet, old keys still referenced from `settings_page.dart`).

- [ ] **Step 1: Append new keys to `lib/l10n/app_zh_Hant.arb`**

Insert these entries **right after** the existing `settingsImportFailed` block (around line 223), before `confirmTitle`:

```json
  "settingsExportAll": "匯出全部資料",
  "settingsImportAll": "匯入全部資料",
  "settingsExportAllSuccess": "已匯出至 {path}",
  "@settingsExportAllSuccess": {
    "placeholders": { "path": { "type": "String" } }
  },
  "settingsImportConfirmTitle": "匯入確認",
  "settingsImportConfirmIntro": "即將匯入 {accounts} 個帳號（共 {records} 筆紀錄）：",
  "@settingsImportConfirmIntro": {
    "placeholders": {
      "accounts": { "type": "int" },
      "records": { "type": "int" }
    }
  },
  "settingsImportConfirmOverwriteHeader": "下列 UID 已有資料，將被覆蓋：",
  "settingsImportConfirmNoConflict": "無資料衝突。",
  "settingsImportConfirmPreserveFooter": "其他現有帳號（{uids}）將保留。",
  "@settingsImportConfirmPreserveFooter": {
    "placeholders": { "uids": { "type": "String" } }
  },
  "settingsImportConfirmWarning": "此操作無法復原。請輸入 IMPORT 以確認。",
  "settingsImportAllSuccess": "已成功匯入 {accounts} 個帳號（{records} 筆紀錄）",
  "@settingsImportAllSuccess": {
    "placeholders": {
      "accounts": { "type": "int" },
      "records": { "type": "int" }
    }
  },
  "settingsImportAllPartial": "已匯入 {success}/{total} 個帳號；失敗：{failedUids}",
  "@settingsImportAllPartial": {
    "placeholders": {
      "success": { "type": "int" },
      "total": { "type": "int" },
      "failedUids": { "type": "String" }
    }
  },
  "settingsImportAllFailed": "匯入失敗：{reason}",
  "@settingsImportAllFailed": {
    "placeholders": { "reason": { "type": "String" } }
  },
```

- [ ] **Step 2: Append the same keys to `lib/l10n/app_en.arb`**

In the same position (after the old `settingsImportFailed` block), insert:

```json
  "settingsExportAll": "Export all data",
  "settingsImportAll": "Import all data",
  "settingsExportAllSuccess": "Exported to {path}",
  "@settingsExportAllSuccess": {
    "placeholders": { "path": { "type": "String" } }
  },
  "settingsImportConfirmTitle": "Import confirmation",
  "settingsImportConfirmIntro": "About to import {accounts} accounts ({records} records total):",
  "@settingsImportConfirmIntro": {
    "placeholders": {
      "accounts": { "type": "int" },
      "records": { "type": "int" }
    }
  },
  "settingsImportConfirmOverwriteHeader": "The following UIDs already have data and will be overwritten:",
  "settingsImportConfirmNoConflict": "No data conflicts.",
  "settingsImportConfirmPreserveFooter": "Other existing accounts ({uids}) will be preserved.",
  "@settingsImportConfirmPreserveFooter": {
    "placeholders": { "uids": { "type": "String" } }
  },
  "settingsImportConfirmWarning": "This action cannot be undone. Type IMPORT to confirm.",
  "settingsImportAllSuccess": "Successfully imported {accounts} accounts ({records} records)",
  "@settingsImportAllSuccess": {
    "placeholders": {
      "accounts": { "type": "int" },
      "records": { "type": "int" }
    }
  },
  "settingsImportAllPartial": "Imported {success}/{total} accounts; failed: {failedUids}",
  "@settingsImportAllPartial": {
    "placeholders": {
      "success": { "type": "int" },
      "total": { "type": "int" },
      "failedUids": { "type": "String" }
    }
  },
  "settingsImportAllFailed": "Import failed: {reason}",
  "@settingsImportAllFailed": {
    "placeholders": { "reason": { "type": "String" } }
  },
```

- [ ] **Step 3: Append the same keys to `lib/l10n/app_zh_Hans.arb`**

Use the Simplified Chinese translations. Insert after the old `settingsImportFailed` block:

```json
  "settingsExportAll": "导出全部数据",
  "settingsImportAll": "导入全部数据",
  "settingsExportAllSuccess": "已导出至 {path}",
  "@settingsExportAllSuccess": {
    "placeholders": { "path": { "type": "String" } }
  },
  "settingsImportConfirmTitle": "导入确认",
  "settingsImportConfirmIntro": "即将导入 {accounts} 个账号（共 {records} 条记录）：",
  "@settingsImportConfirmIntro": {
    "placeholders": {
      "accounts": { "type": "int" },
      "records": { "type": "int" }
    }
  },
  "settingsImportConfirmOverwriteHeader": "下列 UID 已有数据，将被覆盖：",
  "settingsImportConfirmNoConflict": "无数据冲突。",
  "settingsImportConfirmPreserveFooter": "其他现有账号（{uids}）将保留。",
  "@settingsImportConfirmPreserveFooter": {
    "placeholders": { "uids": { "type": "String" } }
  },
  "settingsImportConfirmWarning": "此操作无法撤销。请输入 IMPORT 以确认。",
  "settingsImportAllSuccess": "已成功导入 {accounts} 个账号（{records} 条记录）",
  "@settingsImportAllSuccess": {
    "placeholders": {
      "accounts": { "type": "int" },
      "records": { "type": "int" }
    }
  },
  "settingsImportAllPartial": "已导入 {success}/{total} 个账号；失败：{failedUids}",
  "@settingsImportAllPartial": {
    "placeholders": {
      "success": { "type": "int" },
      "total": { "type": "int" },
      "failedUids": { "type": "String" }
    }
  },
  "settingsImportAllFailed": "导入失败：{reason}",
  "@settingsImportAllFailed": {
    "placeholders": { "reason": { "type": "String" } }
  },
```

- [ ] **Step 4: Re-generate l10n classes**

Run: `flutter gen-l10n`
Expected: completes without errors. Generated files in `lib/l10n/generated/` are updated to include the new keys.

If your repo uses an auto-build for l10n (check `pubspec.yaml` for `flutter:` `generate: true`), running `flutter test` or `flutter analyze` once also re-generates them. If `flutter gen-l10n` is not on PATH, run `flutter pub run flutter_localizations:gen_l10n` instead.

- [ ] **Step 5: Verify analyze passes**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
dart format lib/l10n/
git add lib/l10n/app_zh_Hant.arb lib/l10n/app_en.arb lib/l10n/app_zh_Hans.arb lib/l10n/generated/
git commit -m "$(cat <<'EOF'
feat(l10n): add strings for export/import all accounts flow

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7 — Settings page UI: switch to all-accounts flow

**Files:**
- Modify: `lib/pages/settings_page.dart`

Replace `_DataManagement` button row and handlers. The `_ConfirmDialog` flow uses the existing `showConfirmTypeDialog` helper with `expectedText: 'IMPORT'`.

The body of the dialog needs multi-line content — pass a single `body` string built with `\n` separators (matches the existing `showConfirmTypeDialog` signature, which accepts a plain `String body`).

- [ ] **Step 1: Replace the `_DataManagement` class body**

Open `lib/pages/settings_page.dart`. Replace the entire `_DataManagement` class (lines 185 – 334 of the current file) with:

```dart
class _DataManagement extends ConsumerWidget {
  const _DataManagement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(wishRepositoryProvider);
    final hasData = state.byUid.isNotEmpty;

    return Wrap(
      spacing: AppSpacing.s,
      runSpacing: AppSpacing.s,
      children: [
        OutlinedButton.icon(
          onPressed: !hasData ? null : () => _exportAll(context, ref),
          icon: const Icon(Icons.download_outlined, size: 18),
          label: Text(l.settingsExportAll),
        ),
        OutlinedButton.icon(
          onPressed: () => _importAll(context, ref),
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: Text(l.settingsImportAll),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).gacha.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: state.activeUid == null
              ? null
              : () => _clearActive(context, ref, state.activeUid!),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(l.settingsClearActive),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).gacha.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: !hasData ? null : () => _clearAll(context, ref),
          icon: const Icon(Icons.delete_forever_outlined, size: 18),
          label: Text(l.settingsClearAll),
        ),
      ],
    );
  }

  Future<void> _exportAll(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final wish = ref.read(wishRepositoryProvider);
    final settings = ref.read(settingsProvider);
    final appVersion = ref.read(appVersionProvider);

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

    final text = exportAllAccounts(
      byUid: wish.byUid,
      uidOrder: settings.uidOrder,
      uidAliases: settings.uidAliases,
      lastActiveUid: settings.lastActiveUid,
      appVersion: appVersion,
      now: now,
    );
    await File(loc.path).writeAsString(text);
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(l.settingsExportAllSuccess(loc.path))),
    );
  }

  Future<void> _importAll(BuildContext ctx, WidgetRef ref) async {
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
        SnackBar(content: Text(l.settingsImportAllFailed(e.toString()))),
      );
      return;
    }

    final AllAccountsBundle bundle;
    try {
      bundle = importAllAccounts(text);
    } on FormatException catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l.settingsImportAllFailed(e.message))),
      );
      return;
    }

    // Build dialog body.
    final existing = ref.read(wishRepositoryProvider).byUid.keys.toSet();
    final incoming = bundle.accounts.map((a) => a.data.uid).toList();
    final conflicts = incoming.where(existing.contains).toList();
    final preserved = existing.where((u) => !incoming.contains(u)).toList()
      ..sort();

    var totalRecords = 0;
    for (final a in bundle.accounts) {
      for (final list in a.data.banners.values) {
        totalRecords += list.length;
      }
    }

    final buf = StringBuffer()
      ..writeln(l.settingsImportConfirmIntro(incoming.length, totalRecords));
    for (final a in bundle.accounts) {
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
      confirmLabel: l.confirmDelete,
    );
    if (ok != true) return;
    if (!ctx.mounted) return;

    final result = await ref
        .read(wishRepositoryProvider.notifier)
        .importAllAccounts(bundle);
    if (!ctx.mounted) return;

    final SnackBar snack;
    if (result.failedUids.isEmpty) {
      snack = SnackBar(
        content: Text(
          l.settingsImportAllSuccess(result.successAccounts, result.totalRecords),
        ),
      );
    } else {
      snack = SnackBar(
        content: Text(
          l.settingsImportAllPartial(
            result.successAccounts,
            bundle.accounts.length,
            result.failedUids.join(', '),
          ),
        ),
      );
    }
    ScaffoldMessenger.of(ctx).showSnackBar(snack);
  }

  Future<void> _clearActive(BuildContext ctx, WidgetRef ref, String uid) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.confirmTitle,
      body: l.confirmClearActiveBody(uid),
      expectedText: uid,
      cancelLabel: l.confirmCancel,
      confirmLabel: l.confirmDelete,
    );
    if (ok != true) return;
    await ref.read(wishRepositoryProvider.notifier).clearActive();
  }

  Future<void> _clearAll(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.confirmTitle,
      body: l.confirmClearAllBody,
      expectedText: 'DELETE',
      cancelLabel: l.confirmCancel,
      confirmLabel: l.confirmDelete,
    );
    if (ok != true) return;
    await ref.read(wishRepositoryProvider.notifier).clearAll();
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
```

- [ ] **Step 2: Update imports at the top of `settings_page.dart`**

Replace the lines:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/data_export.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_import.dart';
```

with:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/models/all_accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/all_accounts_export.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/all_accounts_import.dart';
```

The `BannerStorage` import (used by the old `_exportJson`/`_exportCsv`) is no longer needed in this file — remove the line if it's unused after this change:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
```

Run `flutter analyze` after — it flags unused imports.

- [ ] **Step 3: Verify analyze + test pass**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: Manual UI smoke (Windows)**

Launch the app:

```powershell
flutter run -d windows
```

Verify in the Settings page → Data management section:
1. The four buttons are now: 匯出全部資料 / 匯入全部資料 / 清除目前帳號資料 / 清除所有資料.
2. With ≥1 account, click **匯出全部資料** → save a `.json` file → open it and confirm the structure matches the spec (top-level keys `schema_version`, `exported_at`, `app_version`, `last_active_uid`, `accounts`).
3. Click **匯入全部資料** → select the file just saved → confirm dialog shows the account list with aliases and "no data conflicts" (importing the same file) → type `IMPORT` → success SnackBar.
4. Delete one of the imported accounts via the account management section, then re-import the file. Expected: the just-deleted UID appears in the per-account list but **not** in the "將被覆蓋" conflict list (because it no longer exists locally); after confirming, the account comes back.
5. Add a fresh account (via "新增帳號") that is **not** in the exported file → re-import the file → confirm dialog lists that new UID under "其他現有帳號（…）將保留".
6. Click cancel on the dialog → no changes applied; account list unchanged.

If your local environment can't run on Windows for some reason, mark this step as "skipped — UI cannot be tested in this environment" in the final summary; do NOT claim success.

- [ ] **Step 5: Commit**

```bash
dart format lib/pages/settings_page.dart
git add lib/pages/settings_page.dart
git commit -m "$(cat <<'EOF'
feat(settings-page): switch data management to export/import all accounts

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8 — Cleanup: remove old single-account export/import

**Files:**
- Delete: `lib/services/data_export.dart`
- Delete: `lib/services/data_import.dart`
- Delete: `test/services/data_export_test.dart`
- Delete: `test/services/data_import_test.dart`
- Modify: `lib/l10n/app_zh_Hant.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_zh_Hans.arb` (remove the 6 now-unused keys)

UI no longer imports the old services or references the old l10n keys after Task 7, so this commit just trims dead code.

- [ ] **Step 1: Verify nothing still references the old services**

Run: `grep -RIn "data_export.dart\|data_import.dart\|exportCsv\|exportJson\|importJson" lib test` (or use the Grep tool).

Expected: only the four files about to be deleted appear in the results. If anything else references them, fix that reference before continuing — do not delete code that's still in use.

- [ ] **Step 2: Delete the four files**

```bash
rm lib/services/data_export.dart
rm lib/services/data_import.dart
rm test/services/data_export_test.dart
rm test/services/data_import_test.dart
```

- [ ] **Step 3: Remove old l10n keys**

From `lib/l10n/app_zh_Hant.arb`, `lib/l10n/app_en.arb`, and `lib/l10n/app_zh_Hans.arb`, **delete** these key entries (including their `@key` metadata blocks):

- `settingsExportJson`
- `settingsExportCsv`
- `settingsImportJson`
- `settingsExportSuccess` + `@settingsExportSuccess`
- `settingsImportSuccess` + `@settingsImportSuccess`
- `settingsImportFailed` + `@settingsImportFailed`

- [ ] **Step 4: Re-generate l10n**

Run: `flutter gen-l10n`
Expected: succeeds; generated files in `lib/l10n/generated/` no longer expose the removed keys.

- [ ] **Step 5: Verify analyze + test pass**

Run: `flutter analyze`
Expected: `No issues found!` (if anything still references removed keys, fix it.)

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
dart format lib/l10n/
git add -u lib/services/data_export.dart lib/services/data_import.dart \
            test/services/data_export_test.dart test/services/data_import_test.dart \
            lib/l10n/app_zh_Hant.arb lib/l10n/app_en.arb lib/l10n/app_zh_Hans.arb \
            lib/l10n/generated/
git commit -m "$(cat <<'EOF'
refactor: remove obsolete per-account export/import code and l10n

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9 — Final verification

**Files:** none — this task only runs the project quality gates from `CLAUDE.md`.

- [ ] **Step 1: Format**

Run: `dart format lib/ test/`
Expected: no errors. (Do NOT pass `.` — that would touch `rust_builder/`.)

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Test**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: Confirm the eight commits are stacked**

Run: `git log --oneline -10`
Expected: the most recent commits are (newest first):

```
refactor: remove obsolete per-account export/import code and l10n
feat(settings-page): switch data management to export/import all accounts
feat(l10n): add strings for export/import all accounts flow
feat(repo): add importAllAccounts with per-UID overwrite and partial failure
feat(settings): add applyImportedPreferences for atomic import write
feat(services): add importAllAccounts parser with strict validation
feat(services): add exportAllAccounts that bundles every account into one JSON
feat(models): add AllAccountsBundle for export/import payload
```

If any commit is missing, return to the corresponding task and resolve.

- [ ] **Step 5: Report**

State explicitly which of the three gates pass and whether Task 7 Step 4 (Windows UI smoke) was actually performed. Do not claim feature complete unless either the smoke ran successfully or you flagged it as skipped.

---

## Summary

8 commits, ~9 task files touched (5 new, 4 deleted; modifications to 5 existing files), full TDD: every commit has tests, every commit leaves the suite green. Atomic per-feature commits make for easy bisect if anything regresses.
