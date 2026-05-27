# 多帳號管理（持久化最後切換、自訂排序、別名）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 切換帳號時持久化 `lastActiveUid`、Settings「帳號管理」區塊支援拖曳排序與別名編輯，UidIndicator 與 Settings 都呈現別名。

**Architecture:** 偏好全部進既有的 `SettingsStorage`（SharedPreferences）；`WishRepository` 在 bootstrap / 切換 / 刪除 / 匯入 / 抓取完成時同步寫入 `SettingsNotifier`。UI 共用純函式 `mergeUidOrder` 計算最終顯示順序。

**Tech Stack:** Flutter / Riverpod (`Notifier`) / SharedPreferences / 既有 i18n（`flutter gen-l10n`）／既有 `showConfirmTypeDialog`。

---

## 與 Spec 的偏差說明（探索後修正）

撰寫 spec 時未仔細掃描 `lib/pages/settings_page.dart`，下列項目在 plan 中以「實際既有狀況」為準：

1. **不新建 `lib/widgets/cards/account_manager_section.dart`**。`lib/pages/settings_page.dart` 內已有 private 的 `_AccountManagement` widget（行 312-438），實作了 UID 清單、設為活躍、移除、重新攔截。本 plan 改為**抽出 `_AccountManagement` 成為獨立檔案 `lib/widgets/cards/account_management.dart` 並轉為 public**（Task 9），再在它上面加排序與別名（Task 11, 12）。
2. **不新增** `accountManagementEmpty` / `accountManagementTitle` / `accountDeleteConfirmTitle` / `accountDeleteConfirmMessage` i18n key — 重用既有 `accountListEmpty` / `settingsAccountManagement` / `confirmTitle` / `confirmClearActiveBody`。
3. 刪除帳號流程使用既有的 `showConfirmTypeDialog`（強驗證：要輸入 UID 才能刪除），非 spec 隨手寫的 `ConfirmDialog`。

其餘設計（資料模型、`mergeUidOrder`、`WishRepository` 整合、啟動 fallback 行為、`UidIndicator` 顯示策略）與 spec 完全一致。

---

## Task 0: 確認測試 baseline

執行一次完整檢查作為 baseline。

- [ ] **Step 1: 跑完整檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

預期：format 無更動、analyze 輸出 `No issues found!`、test 輸出 `All tests passed!`。

若失敗，先停下並回報；不要繼續往下。

---

## Task 1: 純函式 `mergeUidOrder`

**Files:**
- Create: `lib/services/uid_ordering.dart`
- Test: `test/services/uid_ordering_test.dart`

無依賴；先寫測試再寫實作。

- [ ] **Step 1: 寫失敗測試**

建立 `test/services/uid_ordering_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';

void main() {
  DateTime t(int day) => DateTime.utc(2026, 5, day);

  group('mergeUidOrder', () {
    test('空 customOrder → 全部按 lastUpdated desc', () {
      final result = mergeUidOrder(
        knownUids: const ['A', 'B', 'C'],
        customOrder: const [],
        lastUpdatedOf: (u) => {'A': t(1), 'B': t(3), 'C': t(2)}[u]!,
      );
      expect(result, ['B', 'C', 'A']);
    });

    test('customOrder 全部覆蓋 → 維持 customOrder', () {
      final result = mergeUidOrder(
        knownUids: const ['A', 'B', 'C'],
        customOrder: const ['C', 'A', 'B'],
        lastUpdatedOf: (_) => t(1),
      );
      expect(result, ['C', 'A', 'B']);
    });

    test('customOrder 含已不存在的 UID → 過濾掉', () {
      final result = mergeUidOrder(
        knownUids: const ['A', 'B'],
        customOrder: const ['C', 'A', 'D', 'B'],
        lastUpdatedOf: (_) => t(1),
      );
      expect(result, ['A', 'B']);
    });

    test('customOrder 部分覆蓋 → 已排序的優先、新 UID 接尾端按 lastUpdated desc', () {
      final result = mergeUidOrder(
        knownUids: const ['A', 'B', 'C', 'D'],
        customOrder: const ['C', 'A'],
        lastUpdatedOf: (u) => {'A': t(1), 'B': t(2), 'C': t(3), 'D': t(4)}[u]!,
      );
      expect(result, ['C', 'A', 'D', 'B']);
    });

    test('knownUids 為空 → 回傳空 list', () {
      final result = mergeUidOrder(
        knownUids: const <String>[],
        customOrder: const ['A', 'B'],
        lastUpdatedOf: (_) => t(1),
      );
      expect(result, isEmpty);
    });
  });
}
```

- [ ] **Step 2: 跑測試驗證失敗**

```bash
flutter test test/services/uid_ordering_test.dart
```

預期：FAIL（檔案不存在）。

- [ ] **Step 3: 實作 `mergeUidOrder`**

建立 `lib/services/uid_ordering.dart`：

```dart
/// 把使用者自訂排序與目前已知 UID 合併成最終顯示順序。
///
/// 1. [customOrder] 中仍存在於 [knownUids] 的 → 保留順序
/// 2. [knownUids] 中不在 [customOrder] 的 → 按 [lastUpdatedOf] desc 接在後面
List<String> mergeUidOrder({
  required Iterable<String> knownUids,
  required List<String> customOrder,
  required DateTime Function(String uid) lastUpdatedOf,
}) {
  final knownSet = knownUids.toSet();
  final inCustom = customOrder.where(knownSet.contains).toList();
  final inCustomSet = inCustom.toSet();
  final rest = knownUids.where((u) => !inCustomSet.contains(u)).toList()
    ..sort((a, b) => lastUpdatedOf(b).compareTo(lastUpdatedOf(a)));
  return [...inCustom, ...rest];
}
```

- [ ] **Step 4: 跑測試驗證通過**

```bash
flutter test test/services/uid_ordering_test.dart
```

預期：PASS（5 個測試）。

- [ ] **Step 5: 全套檢查 + commit**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

預期：format 無新動到既有檔、analyze `No issues found!`、test `All tests passed!`。

```bash
git add lib/services/uid_ordering.dart test/services/uid_ordering_test.dart
git commit -m "feat(uid_ordering): add mergeUidOrder helper for UID list ordering

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `AppSettings` 與 `SettingsStorage` 擴充三個欄位

**Files:**
- Modify: `lib/services/settings_storage.dart`
- Test: `test/services/settings_storage_test.dart`

新增 `lastActiveUid` / `uidAliases` / `uidOrder`，序列化用 JSON。

- [ ] **Step 1: 寫失敗測試（補強 settings_storage_test.dart）**

把以下測試**追加**到既有 `test/services/settings_storage_test.dart` 的 `group('SettingsStorage', () { ... })` 內：

```dart
test('新欄位預設為 null / 空 map / 空 list', () async {
  final s = await SettingsStorage.load();
  expect(s.lastActiveUid, isNull);
  expect(s.uidAliases, isEmpty);
  expect(s.uidOrder, isEmpty);
});

test('lastActiveUid round-trip', () async {
  await SettingsStorage.save(
    const AppSettings(
      themeMode: AppThemeMode.system,
      locale: AppLocale.system,
      lastActiveUid: '123456789',
    ),
  );
  final s = await SettingsStorage.load();
  expect(s.lastActiveUid, '123456789');
});

test('uidAliases round-trip', () async {
  await SettingsStorage.save(
    const AppSettings(
      themeMode: AppThemeMode.system,
      locale: AppLocale.system,
      uidAliases: {'A': '主帳', 'B': '小號'},
    ),
  );
  final s = await SettingsStorage.load();
  expect(s.uidAliases, {'A': '主帳', 'B': '小號'});
});

test('uidOrder round-trip', () async {
  await SettingsStorage.save(
    const AppSettings(
      themeMode: AppThemeMode.system,
      locale: AppLocale.system,
      uidOrder: ['C', 'A', 'B'],
    ),
  );
  final s = await SettingsStorage.load();
  expect(s.uidOrder, ['C', 'A', 'B']);
});

test('uidAliases JSON 壞掉 → fallback 為空 map', () async {
  SharedPreferences.setMockInitialValues({
    'pref.uidAliases': 'not-json-at-all',
  });
  final s = await SettingsStorage.load();
  expect(s.uidAliases, isEmpty);
});

test('uidOrder JSON 壞掉 → fallback 為空 list', () async {
  SharedPreferences.setMockInitialValues({
    'pref.uidOrder': '{not-a-list}',
  });
  final s = await SettingsStorage.load();
  expect(s.uidOrder, isEmpty);
});
```

- [ ] **Step 2: 跑測試驗證失敗**

```bash
flutter test test/services/settings_storage_test.dart
```

預期：FAIL（`AppSettings` 沒有 `lastActiveUid` / `uidAliases` / `uidOrder` 欄位）。

- [ ] **Step 3: 修改 `lib/services/settings_storage.dart`**

整個檔案改寫為：

```dart
// lib/services/settings_storage.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, dark, light }

enum AppLocale { system, zhHant, zhHans, en }

@immutable
class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.locale,
    this.lastActiveUid,
    this.uidAliases = const {},
    this.uidOrder = const [],
  });

  final AppThemeMode themeMode;
  final AppLocale locale;
  final String? lastActiveUid;
  final Map<String, String> uidAliases;
  final List<String> uidOrder;

  static const defaults = AppSettings(
    themeMode: AppThemeMode.system,
    locale: AppLocale.system,
  );

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppLocale? locale,
    String? lastActiveUid,
    bool clearLastActiveUid = false,
    Map<String, String>? uidAliases,
    List<String>? uidOrder,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
    lastActiveUid:
        clearLastActiveUid ? null : (lastActiveUid ?? this.lastActiveUid),
    uidAliases: uidAliases ?? this.uidAliases,
    uidOrder: uidOrder ?? this.uidOrder,
  );
}

abstract final class SettingsStorage {
  static const _kThemeMode = 'pref.themeMode';
  static const _kLocale = 'pref.locale';
  static const _kLastActiveUid = 'pref.lastActiveUid';
  static const _kUidAliases = 'pref.uidAliases';
  static const _kUidOrder = 'pref.uidOrder';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      themeMode: _parseThemeMode(prefs.getString(_kThemeMode)),
      locale: _parseLocale(prefs.getString(_kLocale)),
      lastActiveUid: prefs.getString(_kLastActiveUid),
      uidAliases: _parseAliases(prefs.getString(_kUidAliases)),
      uidOrder: _parseOrder(prefs.getString(_kUidOrder)),
    );
  }

  static Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, _themeModeToString(s.themeMode));
    await prefs.setString(_kLocale, _localeToString(s.locale));
    if (s.lastActiveUid == null) {
      await prefs.remove(_kLastActiveUid);
    } else {
      await prefs.setString(_kLastActiveUid, s.lastActiveUid!);
    }
    await prefs.setString(_kUidAliases, jsonEncode(s.uidAliases));
    await prefs.setString(_kUidOrder, jsonEncode(s.uidOrder));
  }

  static AppThemeMode _parseThemeMode(String? raw) => switch (raw) {
    'dark' => AppThemeMode.dark,
    'light' => AppThemeMode.light,
    _ => AppThemeMode.system,
  };

  static String _themeModeToString(AppThemeMode m) => switch (m) {
    AppThemeMode.dark => 'dark',
    AppThemeMode.light => 'light',
    AppThemeMode.system => 'system',
  };

  static AppLocale _parseLocale(String? raw) => switch (raw) {
    'zh-Hant' => AppLocale.zhHant,
    'zh-Hans' => AppLocale.zhHans,
    'en' => AppLocale.en,
    _ => AppLocale.system,
  };

  static String _localeToString(AppLocale l) => switch (l) {
    AppLocale.zhHant => 'zh-Hant',
    AppLocale.zhHans => 'zh-Hans',
    AppLocale.en => 'en',
    AppLocale.system => 'system',
  };

  static Map<String, String> _parseAliases(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return const {};
    }
  }

  static List<String> _parseOrder(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => e.toString()).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
```

- [ ] **Step 4: 跑測試驗證通過**

```bash
flutter test test/services/settings_storage_test.dart
```

預期：PASS（既有 3 個 + 新增 6 個 = 9 個測試）。

- [ ] **Step 5: 全套檢查 + commit**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

```bash
git add lib/services/settings_storage.dart test/services/settings_storage_test.dart
git commit -m "feat(settings_storage): add lastActiveUid, uidAliases, uidOrder fields

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `SettingsNotifier` 新增 API + 公開 `waitForLoad`

**Files:**
- Modify: `lib/state/settings.dart`
- Test: `test/state/settings_test.dart`

新增 4 個 API：`setLastActiveUid` / `setUidAlias` / `setUidOrder` / `removeUidFromSettings` / `clearAllUidPreferences`（共 5 個，spec 中提到 4 個 + 1 個 helper）。`waitForLoad` 已存在，把 `@visibleForTesting` 註解拿掉並改文件，因為 `WishRepository._bootstrapLoad` 將正式依賴。

- [ ] **Step 1: 寫失敗測試（追加到 settings_test.dart）**

在 `test/state/settings_test.dart` 內 `main()` 末端追加：

```dart
test('setLastActiveUid 寫入 state 與 prefs', () async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).waitForLoad();

  await container.read(settingsProvider.notifier).setLastActiveUid('UID1');
  expect(container.read(settingsProvider).lastActiveUid, 'UID1');
  final reloaded = await SettingsStorage.load();
  expect(reloaded.lastActiveUid, 'UID1');
});

test('setLastActiveUid(null) 清掉 state 與 prefs', () async {
  SharedPreferences.setMockInitialValues({'pref.lastActiveUid': 'UID1'});
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).waitForLoad();
  expect(container.read(settingsProvider).lastActiveUid, 'UID1');

  await container.read(settingsProvider.notifier).setLastActiveUid(null);
  expect(container.read(settingsProvider).lastActiveUid, isNull);
  final reloaded = await SettingsStorage.load();
  expect(reloaded.lastActiveUid, isNull);
});

test('setUidAlias 新增與覆蓋', () async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).waitForLoad();

  await container.read(settingsProvider.notifier).setUidAlias('A', '主帳');
  expect(container.read(settingsProvider).uidAliases, {'A': '主帳'});

  await container.read(settingsProvider.notifier).setUidAlias('A', '新名字');
  expect(container.read(settingsProvider).uidAliases, {'A': '新名字'});
});

test('setUidAlias trim 後為空字串 → 移除', () async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).waitForLoad();
  await container.read(settingsProvider.notifier).setUidAlias('A', '主帳');

  await container.read(settingsProvider.notifier).setUidAlias('A', '   ');
  expect(container.read(settingsProvider).uidAliases, isEmpty);

  await container.read(settingsProvider.notifier).setUidAlias('A', '主帳');
  await container.read(settingsProvider.notifier).setUidAlias('A', null);
  expect(container.read(settingsProvider).uidAliases, isEmpty);
});

test('setUidOrder 寫入並持久化', () async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).waitForLoad();

  await container.read(settingsProvider.notifier).setUidOrder(['C', 'A', 'B']);
  expect(container.read(settingsProvider).uidOrder, ['C', 'A', 'B']);
  final reloaded = await SettingsStorage.load();
  expect(reloaded.uidOrder, ['C', 'A', 'B']);
});

test('removeUidFromSettings 同時清 alias 與 order，不動 lastActiveUid', () async {
  SharedPreferences.setMockInitialValues({
    'pref.lastActiveUid': 'A',
    'pref.uidAliases': '{"A":"主帳","B":"小號"}',
    'pref.uidOrder': '["B","A","C"]',
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).waitForLoad();

  await container.read(settingsProvider.notifier).removeUidFromSettings('A');
  final s = container.read(settingsProvider);
  expect(s.uidAliases, {'B': '小號'});
  expect(s.uidOrder, ['B', 'C']);
  expect(s.lastActiveUid, 'A'); // 不動
});

test('clearAllUidPreferences 一次清三個欄位', () async {
  SharedPreferences.setMockInitialValues({
    'pref.lastActiveUid': 'A',
    'pref.uidAliases': '{"A":"主帳"}',
    'pref.uidOrder': '["A","B"]',
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).waitForLoad();

  await container.read(settingsProvider.notifier).clearAllUidPreferences();
  final s = container.read(settingsProvider);
  expect(s.lastActiveUid, isNull);
  expect(s.uidAliases, isEmpty);
  expect(s.uidOrder, isEmpty);
});
```

- [ ] **Step 2: 跑測試驗證失敗**

```bash
flutter test test/state/settings_test.dart
```

預期：FAIL（API 不存在）。

- [ ] **Step 3: 修改 `lib/state/settings.dart`**

整個檔案改寫為：

```dart
// lib/state/settings.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';

class SettingsNotifier extends Notifier<AppSettings> {
  late Future<void> _loadFuture;

  @override
  AppSettings build() {
    _loadFuture = _load();
    return AppSettings.defaults;
  }

  Future<void> _load() async {
    final loaded = await SettingsStorage.load();
    if (!ref.mounted) return;
    state = loaded;
  }

  /// 等首次 `_load` 完成。
  ///
  /// `WishRepository._bootstrapLoad` 會在讀 settings 前 await 此 future，
  /// 確保 `lastActiveUid` / `uidOrder` 等偏好已就緒；測試也用得到。
  Future<void> waitForLoad() => _loadFuture;

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await SettingsStorage.save(state);
  }

  Future<void> setLocale(AppLocale locale) async {
    state = state.copyWith(locale: locale);
    await SettingsStorage.save(state);
  }

  Future<void> setLastActiveUid(String? uid) async {
    state = state.copyWith(
      lastActiveUid: uid,
      clearLastActiveUid: uid == null,
    );
    await SettingsStorage.save(state);
  }

  Future<void> setUidAlias(String uid, String? alias) async {
    final trimmed = alias?.trim();
    final next = Map<String, String>.from(state.uidAliases);
    if (trimmed == null || trimmed.isEmpty) {
      next.remove(uid);
    } else {
      next[uid] = trimmed;
    }
    state = state.copyWith(uidAliases: next);
    await SettingsStorage.save(state);
  }

  Future<void> setUidOrder(List<String> order) async {
    state = state.copyWith(uidOrder: List.unmodifiable(order));
    await SettingsStorage.save(state);
  }

  Future<void> removeUidFromSettings(String uid) async {
    final aliases = Map<String, String>.from(state.uidAliases)..remove(uid);
    final order = state.uidOrder.where((u) => u != uid).toList();
    state = state.copyWith(uidAliases: aliases, uidOrder: order);
    await SettingsStorage.save(state);
  }

  Future<void> clearAllUidPreferences() async {
    state = state.copyWith(
      clearLastActiveUid: true,
      uidAliases: const {},
      uidOrder: const [],
    );
    await SettingsStorage.save(state);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// 給 MaterialApp 直接吃的 ThemeMode（system → ThemeMode.system）
final themeModeProvider = Provider<ThemeMode>((ref) {
  final mode = ref.watch(settingsProvider).themeMode;
  return switch (mode) {
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.system => ThemeMode.system,
  };
});

/// 給 MaterialApp 直接吃的 Locale?（system → null）
final localeProvider = Provider<Locale?>((ref) {
  final locale = ref.watch(settingsProvider).locale;
  return switch (locale) {
    AppLocale.zhHant => const Locale('zh', 'Hant'),
    AppLocale.zhHans => const Locale('zh', 'Hans'),
    AppLocale.en => const Locale('en'),
    AppLocale.system => null,
  };
});
```

注意：`@visibleForTesting` 已拿掉、`waitForLoad` 變為正式 API；`import 'package:flutter/foundation.dart'` 因為不再用 `@visibleForTesting`，**仍可保留**因為其他地方可能用到，但在此檔內若無其他用途可移除（讓 analyzer 提示後再決定）。先嘗試保留，跑 analyze 看會不會抱怨未使用 import；若會，再刪掉。

- [ ] **Step 4: 跑測試驗證通過**

```bash
flutter test test/state/settings_test.dart
```

預期：PASS（既有 3 + 新增 7 = 10 個測試）。

- [ ] **Step 5: 全套檢查 + commit**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

若 analyze 抱怨 `package:flutter/foundation.dart` 未使用，刪掉該 import 再跑一次。

```bash
git add lib/state/settings.dart test/state/settings_test.dart
git commit -m "feat(settings): add UID preference APIs and promote waitForLoad

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `WishRepository._bootstrapLoad` 改用 `settings.lastActiveUid`

**Files:**
- Modify: `lib/state/wish_repository.dart`
- Test: `test/state/wish_repository_test.dart`

依賴 Task 1（`mergeUidOrder`）與 Task 3（`SettingsNotifier`）。

- [ ] **Step 1: 寫失敗測試**

在 `test/state/wish_repository_test.dart` 開頭新增 import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
```

然後在 `setUp` 內補上 SharedPreferences 重置（在既有 `tempDir = ...` 之前或之後都可，建議之後）：

```dart
SharedPreferences.setMockInitialValues({});
```

接著在 `main()` 內既有測試之後追加：

```dart
test('bootstrap：lastActiveUid 命中 → 用它（不用最新）', () async {
  final storage = WishStorage(tempDir);
  await storage.save(
    BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 1, 1),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  await storage.save(
    BannerStorage(
      uid: 'B',
      lastUpdated: DateTime.utc(2026, 5, 9), // 較新
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  SharedPreferences.setMockInitialValues({'pref.lastActiveUid': 'A'});

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
  expect(container.read(wishRepositoryProvider).activeUid, 'A');
});

test('bootstrap：lastActiveUid 失效 → fallback 為 mergeUidOrder.first 並寫回', () async {
  final storage = WishStorage(tempDir);
  await storage.save(
    BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 1, 1),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  await storage.save(
    BannerStorage(
      uid: 'B',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  SharedPreferences.setMockInitialValues({'pref.lastActiveUid': 'GHOST'});

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
  expect(container.read(wishRepositoryProvider).activeUid, 'B'); // 較新
  // 寫回 settings
  final reloaded = await SettingsStorage.load();
  expect(reloaded.lastActiveUid, 'B');
});

test('bootstrap：lastActiveUid 為 null → fallback 為最新並寫回', () async {
  final storage = WishStorage(tempDir);
  await storage.save(
    BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );

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
  expect(container.read(wishRepositoryProvider).activeUid, 'A');
  final reloaded = await SettingsStorage.load();
  expect(reloaded.lastActiveUid, 'A');
});

test('bootstrap：uidOrder 影響 fallback 順序', () async {
  final storage = WishStorage(tempDir);
  await storage.save(
    BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 1, 1),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  await storage.save(
    BannerStorage(
      uid: 'B',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  SharedPreferences.setMockInitialValues({
    'pref.uidOrder': '["A","B"]', // 自訂 A 在前
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
  // lastActiveUid 為 null → fallback 走 mergeUidOrder.first → 自訂順序的第一個 = A
  expect(container.read(wishRepositoryProvider).activeUid, 'A');
});
```

並確認原本「bootstrap load 有 2 個 UID 檔 → activeUid = 較新者」測試的命題：當 `lastActiveUid` 為 null 時 fallback 為 mergeUidOrder.first；當 customOrder 為空時等於 lastUpdated 最新者。**該既有測試不必改**（兩個條件都成立：B 較新、customOrder 空）。

- [ ] **Step 2: 跑測試驗證失敗**

```bash
flutter test test/state/wish_repository_test.dart
```

預期：FAIL（fallback 行為錯誤、`settingsProvider` 互動沒接好）。

- [ ] **Step 3: 修改 `WishRepository._bootstrapLoad`**

在 `lib/state/wish_repository.dart` 開頭新增 import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
```

把 `_bootstrapLoad` 整個替換為：

```dart
Future<void> _bootstrapLoad() async {
  final storage = ref.read(wishStorageProvider);
  final settingsNotifier = ref.read(settingsProvider.notifier);
  await settingsNotifier.waitForLoad();
  if (!ref.mounted) return;

  final uids = await storage.listKnownUids();
  if (!ref.mounted) return;

  final byUid = <String, BannerStorage>{};
  for (final uid in uids) {
    final data = await storage.load(uid);
    if (!ref.mounted) return;
    if (data != null) byUid[uid] = data;
  }

  if (byUid.isEmpty) {
    state = state.copyWith(byUid: byUid, isBootstrapping: false);
    return;
  }

  final settings = ref.read(settingsProvider);
  final ordered = mergeUidOrder(
    knownUids: byUid.keys,
    customOrder: settings.uidOrder,
    lastUpdatedOf: (u) => byUid[u]!.lastUpdated,
  );

  final saved = settings.lastActiveUid;
  final activeUid = (saved != null && byUid.containsKey(saved))
      ? saved
      : ordered.first;

  state = state.copyWith(
    byUid: byUid,
    activeUid: activeUid,
    isBootstrapping: false,
  );

  if (saved != activeUid) {
    await settingsNotifier.setLastActiveUid(activeUid);
  }
}
```

- [ ] **Step 4: 跑測試驗證通過**

```bash
flutter test test/state/wish_repository_test.dart
```

預期：所有測試（既有 + 新增 4 個）PASS。

- [ ] **Step 5: 全套檢查 + commit**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

```bash
git add lib/state/wish_repository.dart test/state/wish_repository_test.dart
git commit -m "feat(wish_repository): restore lastActiveUid on bootstrap

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `WishRepository.setActiveUid` 持久化

**Files:**
- Modify: `lib/state/wish_repository.dart`
- Test: `test/state/wish_repository_test.dart`

- [ ] **Step 1: 寫失敗測試**

追加到 `test/state/wish_repository_test.dart`：

```dart
test('setActiveUid 寫入 settings.lastActiveUid', () async {
  final storage = WishStorage(tempDir);
  await storage.save(
    BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 1, 1),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  await storage.save(
    BannerStorage(
      uid: 'B',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );

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

  await container.read(wishRepositoryProvider.notifier).setActiveUid('A');
  expect(container.read(wishRepositoryProvider).activeUid, 'A');
  final reloaded = await SettingsStorage.load();
  expect(reloaded.lastActiveUid, 'A');
});

test('setActiveUid 不存在的 UID → 不變、不寫 settings', () async {
  final storage = WishStorage(tempDir);
  await storage.save(
    BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );

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

  final beforeReload = await SettingsStorage.load();
  await container.read(wishRepositoryProvider.notifier).setActiveUid('GHOST');
  expect(container.read(wishRepositoryProvider).activeUid, 'A'); // 不變
  final afterReload = await SettingsStorage.load();
  expect(afterReload.lastActiveUid, beforeReload.lastActiveUid);
});
```

- [ ] **Step 2: 跑測試驗證失敗**

```bash
flutter test test/state/wish_repository_test.dart -p vm --name "setActiveUid"
```

預期：FAIL（lastActiveUid 沒被寫入）。

- [ ] **Step 3: 修改 `setActiveUid`**

把 `lib/state/wish_repository.dart` 中的 `setActiveUid` 替換為：

```dart
Future<void> setActiveUid(String uid) async {
  if (!state.byUid.containsKey(uid)) return;
  state = state.copyWith(activeUid: uid);
  await ref.read(settingsProvider.notifier).setLastActiveUid(uid);
}
```

- [ ] **Step 4: 跑測試驗證通過**

```bash
flutter test test/state/wish_repository_test.dart
```

預期：所有測試 PASS。

- [ ] **Step 5: 全套檢查 + commit**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

```bash
git add lib/state/wish_repository.dart test/state/wish_repository_test.dart
git commit -m "feat(wish_repository): persist lastActiveUid on setActiveUid

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `removeUid` / `clearActive` 同步 settings

**Files:**
- Modify: `lib/state/wish_repository.dart`
- Test: `test/state/wish_repository_test.dart`

刪除任一 UID 時清掉它在 `uidAliases` / `uidOrder` 內的資料；若刪的是 active UID，計算新的 active 並寫回 `lastActiveUid`。`clearActive()` 委派給 `removeUid(state.activeUid)`。

- [ ] **Step 1: 寫失敗測試**

追加：

```dart
test('removeUid（非 active）→ 清 alias/order，lastActiveUid 不變', () async {
  final storage = WishStorage(tempDir);
  await storage.save(
    BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  await storage.save(
    BannerStorage(
      uid: 'B',
      lastUpdated: DateTime.utc(2026, 1, 1),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  SharedPreferences.setMockInitialValues({
    'pref.lastActiveUid': 'A',
    'pref.uidAliases': '{"A":"主","B":"小"}',
    'pref.uidOrder': '["A","B"]',
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

  await container.read(wishRepositoryProvider.notifier).removeUid('B');
  expect(container.read(wishRepositoryProvider).activeUid, 'A');
  final s = await SettingsStorage.load();
  expect(s.lastActiveUid, 'A');
  expect(s.uidAliases, {'A': '主'});
  expect(s.uidOrder, ['A']);
});

test('removeUid（active）→ fallback 新 active 並寫回 lastActiveUid', () async {
  final storage = WishStorage(tempDir);
  await storage.save(
    BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  await storage.save(
    BannerStorage(
      uid: 'B',
      lastUpdated: DateTime.utc(2026, 1, 1),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  SharedPreferences.setMockInitialValues({'pref.lastActiveUid': 'A'});

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

  await container.read(wishRepositoryProvider.notifier).removeUid('A');
  expect(container.read(wishRepositoryProvider).activeUid, 'B');
  final s = await SettingsStorage.load();
  expect(s.lastActiveUid, 'B');
});

test('removeUid（最後一個）→ activeUid = null 且 lastActiveUid = null', () async {
  final storage = WishStorage(tempDir);
  await storage.save(
    BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  SharedPreferences.setMockInitialValues({'pref.lastActiveUid': 'A'});

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

  await container.read(wishRepositoryProvider.notifier).removeUid('A');
  expect(container.read(wishRepositoryProvider).activeUid, isNull);
  final s = await SettingsStorage.load();
  expect(s.lastActiveUid, isNull);
});

test('clearActive 委派給 removeUid', () async {
  final storage = WishStorage(tempDir);
  await storage.save(
    BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  await storage.save(
    BannerStorage(
      uid: 'B',
      lastUpdated: DateTime.utc(2026, 1, 1),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  SharedPreferences.setMockInitialValues({'pref.lastActiveUid': 'A'});

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

  await container.read(wishRepositoryProvider.notifier).clearActive();
  expect(container.read(wishRepositoryProvider).activeUid, 'B');
  final s = await SettingsStorage.load();
  expect(s.lastActiveUid, 'B');
});
```

- [ ] **Step 2: 跑測試驗證失敗**

```bash
flutter test test/state/wish_repository_test.dart
```

預期：FAIL。

- [ ] **Step 3: 修改 `removeUid` 與 `clearActive`**

把 `lib/state/wish_repository.dart` 中：

- **新增 private helper** `_pickFallbackActive`：

```dart
String? _pickFallbackActive(Map<String, BannerStorage> byUid) {
  if (byUid.isEmpty) return null;
  final order = ref.read(settingsProvider).uidOrder;
  return mergeUidOrder(
    knownUids: byUid.keys,
    customOrder: order,
    lastUpdatedOf: (u) => byUid[u]!.lastUpdated,
  ).first;
}
```

- **替換 `removeUid`**：

```dart
Future<void> removeUid(String uid) async {
  final storage = ref.read(wishStorageProvider);
  final settingsNotifier = ref.read(settingsProvider.notifier);

  await storage.delete(uid);
  if (!ref.mounted) return;
  await settingsNotifier.removeUidFromSettings(uid);
  if (!ref.mounted) return;

  final newByUid = Map<String, BannerStorage>.from(state.byUid)..remove(uid);
  if (state.activeUid == uid) {
    final next = _pickFallbackActive(newByUid);
    state = next == null
        ? state.copyWith(byUid: newByUid, clearActiveUid: true)
        : state.copyWith(byUid: newByUid, activeUid: next);
    await settingsNotifier.setLastActiveUid(next);
  } else {
    state = state.copyWith(byUid: newByUid);
  }
}
```

- **替換 `clearActive`**：

```dart
Future<void> clearActive() async {
  final uid = state.activeUid;
  if (uid == null) return;
  await removeUid(uid);
}
```

- [ ] **Step 4: 跑測試驗證通過**

```bash
flutter test test/state/wish_repository_test.dart
```

預期：所有測試 PASS。

- [ ] **Step 5: 全套檢查 + commit**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

```bash
git add lib/state/wish_repository.dart test/state/wish_repository_test.dart
git commit -m "feat(wish_repository): sync settings on removeUid/clearActive

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: `clearAll` / `importData` / `_fetchAllBanners` 同步 settings

**Files:**
- Modify: `lib/state/wish_repository.dart`
- Test: `test/state/wish_repository_test.dart`

- [ ] **Step 1: 寫失敗測試**

追加：

```dart
test('clearAll 清掉所有 UID 偏好', () async {
  final storage = WishStorage(tempDir);
  await storage.save(
    BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  SharedPreferences.setMockInitialValues({
    'pref.lastActiveUid': 'A',
    'pref.uidAliases': '{"A":"主"}',
    'pref.uidOrder': '["A"]',
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

  await container.read(wishRepositoryProvider.notifier).clearAll();
  expect(container.read(wishRepositoryProvider).activeUid, isNull);
  final s = await SettingsStorage.load();
  expect(s.lastActiveUid, isNull);
  expect(s.uidAliases, isEmpty);
  expect(s.uidOrder, isEmpty);
});

test('importData 把 lastActiveUid 寫到新 UID', () async {
  final storage = WishStorage(tempDir);

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

  await container.read(wishRepositoryProvider.notifier).importData(
        BannerStorage(
          uid: 'NEW',
          lastUpdated: DateTime.utc(2026, 5, 11),
          banners: const {
            '301': [], '302': [], '500': [], '200': [], '100': []
          },
        ),
      );
  expect(container.read(wishRepositoryProvider).activeUid, 'NEW');
  final s = await SettingsStorage.load();
  expect(s.lastActiveUid, 'NEW');
});
```

`_fetchAllBanners` 的 settings 同步行為已被「fetch 完整 banner → activeUid = uid」的副作用覆蓋；本任務不另寫 `_fetchAllBanners` 專屬測試（既有的 `AuthExpired` 流程測試覆蓋了 fetch 路徑沒崩潰；fetch 完整成功路徑用 widget 整合層級驗證較划算，本 plan 不展開）。

- [ ] **Step 2: 跑測試驗證失敗**

```bash
flutter test test/state/wish_repository_test.dart
```

預期：FAIL。

- [ ] **Step 3: 修改 `clearAll` / `importData` / `_fetchAllBanners`**

在 `lib/state/wish_repository.dart` 中：

- **替換 `clearAll`**：

```dart
Future<void> clearAll() async {
  final storage = ref.read(wishStorageProvider);
  await storage.clearAll();
  if (!ref.mounted) return;
  await ref.read(settingsProvider.notifier).clearAllUidPreferences();
  if (!ref.mounted) return;
  state = const WishState(isBootstrapping: false);
}
```

- **替換 `importData`**：

```dart
Future<void> importData(BannerStorage data) async {
  final storage = ref.read(wishStorageProvider);
  await storage.save(data);
  if (!ref.mounted) return;
  final newByUid = Map<String, BannerStorage>.from(state.byUid)
    ..[data.uid] = data;
  state = state.copyWith(byUid: newByUid, activeUid: data.uid);
  await ref.read(settingsProvider.notifier).setLastActiveUid(data.uid);
}
```

- **在 `_fetchAllBanners` 末端**（既有 `state = state.copyWith(...)` 設定 `activeUid: uid` 之後）追加：

```dart
await ref.read(settingsProvider.notifier).setLastActiveUid(uid);
```

具體位置：找到既有

```dart
state = state.copyWith(
  byUid: newByUid,
  activeUid: uid,
  progress: UpdateCompleted(
    totalNewRecords: totalNew,
    failedBanners: failed,
    updatedAt: updatedAt,
  ),
);
```

之後加一行：

```dart
await ref.read(settingsProvider.notifier).setLastActiveUid(uid);
```

- [ ] **Step 4: 跑測試驗證通過**

```bash
flutter test test/state/wish_repository_test.dart
```

預期：所有測試 PASS。

- [ ] **Step 5: 全套檢查 + commit**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

```bash
git add lib/state/wish_repository.dart test/state/wish_repository_test.dart
git commit -m "feat(wish_repository): sync settings on clearAll/import/fetch

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: i18n 新增別名相關字串

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_en.arb`
- Generated: `lib/l10n/generated/*`（自動，不手寫）

新增 3 個 key：

| key | zh_Hant | zh_Hans | en |
|---|---|---|---|
| `accountAliasLabel` | 別名 | 别名 | Alias |
| `accountAliasHint` | 為此帳號取一個好記的名稱 | 为此账号取一个好记的名字 | A friendly name for this account |
| `accountDragHandleTooltip` | 拖曳排序 | 拖动排序 | Drag to reorder |

- [ ] **Step 1: 修改 `lib/l10n/app_zh_Hant.arb`**

在既有 `accountRecapture` 之後（檔尾右大括號前合適位置）追加：

```json
"accountAliasLabel": "別名",
"accountAliasHint": "為此帳號取一個好記的名稱",
"accountDragHandleTooltip": "拖曳排序",
```

- [ ] **Step 2: 修改 `lib/l10n/app_zh.arb`**

對應位置追加（簡體用「主流」翻譯）：

```json
"accountAliasLabel": "别名",
"accountAliasHint": "为此账号取一个好记的名字",
"accountDragHandleTooltip": "拖动排序",
```

- [ ] **Step 3: 修改 `lib/l10n/app_zh_Hans.arb`**

讀檔確認既有結構後，比照 `app_zh.arb` 追加同樣三個 key。若 `app_zh_Hans.arb` 與 `app_zh.arb` 是同份內容副本（檢查既有檔案），就保持一致即可。

- [ ] **Step 4: 修改 `lib/l10n/app_en.arb`**

對應位置追加：

```json
"accountAliasLabel": "Alias",
"accountAliasHint": "A friendly name for this account",
"accountDragHandleTooltip": "Drag to reorder",
```

- [ ] **Step 5: 重新產生 generated**

```bash
flutter gen-l10n
```

預期：`lib/l10n/generated/app_localizations*.dart` 被重寫；分析器看到三個新 getter。

- [ ] **Step 6: 全套檢查 + commit**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

```bash
git add lib/l10n/
git commit -m "i18n: add alias and drag handle strings for account management

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: 抽出 `_AccountManagement` 為獨立 public widget（純 refactor，不加新功能）

**Files:**
- Create: `lib/widgets/cards/account_management.dart`
- Modify: `lib/pages/settings_page.dart`

這是 surgical refactor — 為後面加排序與別名 + 寫 widget test 鋪路。**行為完全不變**。

- [ ] **Step 1: 建立 `lib/widgets/cards/account_management.dart`**

整個檔案內容：

```dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';

class AccountManagement extends ConsumerWidget {
  const AccountManagement({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final state = ref.watch(wishRepositoryProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final uids = state.byUid.keys.toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (uids.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
            child: Text(
              l.accountListEmpty,
              style: TextStyle(color: tokens.textMuted),
            ),
          )
        else
          for (final uid in uids)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              uid,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            if (uid == state.activeUid) ...[
                              const SizedBox(width: AppSpacing.s),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.s,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.accentPrimary.withValues(
                                    alpha: 0.18,
                                  ),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  l.accountActiveTag,
                                  style: TextStyle(
                                    color: tokens.accentPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l.accountLastUpdated(
                            DateFormat(
                              'yyyy-MM-dd HH:mm',
                            ).format(state.byUid[uid]!.lastUpdated.toLocal()),
                          ),
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (uid != state.activeUid)
                    TextButton(
                      onPressed: () => notifier.setActiveUid(uid),
                      child: Text(l.accountSetActive),
                    ),
                  TextButton(
                    onPressed: () => _remove(context, ref, uid),
                    child: Text(
                      l.accountRemove,
                      style: TextStyle(color: tokens.stateDanger),
                    ),
                  ),
                ],
              ),
            ),
        const Divider(),
        const SizedBox(height: AppSpacing.s),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => notifier.forceRecaptureAndUpdate(),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l.accountRecapture),
          ),
        ),
      ],
    );
  }

  Future<void> _remove(BuildContext ctx, WidgetRef ref, String uid) async {
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
    await ref.read(wishRepositoryProvider.notifier).removeUid(uid);
  }
}
```

- [ ] **Step 2: 修改 `lib/pages/settings_page.dart`**

1. 在頂部 import 區追加：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/account_management.dart';
```

2. 把 `SectionCard(title: l.settingsAccountManagement, child: const _AccountManagement())` 改為：

```dart
SectionCard(
  title: l.settingsAccountManagement,
  child: const AccountManagement(),
),
```

3. **整個 `class _AccountManagement extends ConsumerWidget { ... }` 與其 `_remove` 方法刪掉**（從第 312 行起的 `class _AccountManagement` 到該類別結尾的 `}`）。

4. 移除 settings_page.dart 中因刪除 `_AccountManagement` 而不再使用的 import（用 analyze 提示找出）：
   - `import 'package:intl/intl.dart' show DateFormat;`（若 settings_page.dart 其他地方沒用 DateFormat）
   - `import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';`（**注意：仍可能用於 SectionCard / AppSpacing**，跑 analyze 確認後再決定）
   - `import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';`（**注意：`_clearActive` / `_clearAll` 仍使用 showConfirmTypeDialog，必須保留**）

策略：先儲存、跑 analyze、根據警告刪除無用 import；保守做法 — 不主動刪 import，由 analyzer 警告為唯一依據。

- [ ] **Step 3: 跑全套檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

預期：所有原本通過的測試持續通過、analyze 無新警告。

- [ ] **Step 4: 手動煙霧測試（可選但建議）**

如果你能跑 `flutter run`，啟動 app 進 Settings → 帳號管理區塊，確認看起來跟以前一樣（這是純 refactor）。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/account_management.dart lib/pages/settings_page.dart
git commit -m "refactor(account_management): extract to standalone widget

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: `UidIndicator` 用別名顯示 + 依排序顯示

**Files:**
- Modify: `lib/widgets/uid_indicator.dart`

- [ ] **Step 1: 修改 `lib/widgets/uid_indicator.dart`**

整個檔案替換為：

```dart
// lib/widgets/uid_indicator.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class UidIndicator extends ConsumerWidget {
  const UidIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wishRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final activeUid = state.activeUid;
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    final orderedUids = state.byUid.isEmpty
        ? const <String>[]
        : mergeUidOrder(
            knownUids: state.byUid.keys,
            customOrder: settings.uidOrder,
            lastUpdatedOf: (u) => state.byUid[u]!.lastUpdated,
          );

    String displayName(String uid) {
      final alias = settings.uidAliases[uid];
      return alias == null ? uid : '$alias ($uid)';
    }

    return PopupMenuButton<String>(
      tooltip: l.uidSwitchTooltip,
      onSelected: (key) async {
        if (key == '__recapture__') {
          await notifier.forceRecaptureAndUpdate();
        } else {
          await notifier.setActiveUid(key);
        }
      },
      itemBuilder: (context) => [
        for (final uid in orderedUids)
          PopupMenuItem<String>(
            value: uid,
            child: Row(
              children: [
                Icon(
                  uid == activeUid ? Icons.check : Icons.radio_button_unchecked,
                  size: 16,
                  color: uid == activeUid
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                ),
                const SizedBox(width: AppSpacing.s),
                Text(displayName(uid)),
                if (uid == activeUid) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    l.uidActiveSuffix,
                    style: TextStyle(fontSize: 11, color: tokens.textMuted),
                  ),
                ],
              ],
            ),
          ),
        if (orderedUids.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: '__recapture__',
          child: Row(
            children: [
              const Icon(Icons.refresh, size: 16),
              const SizedBox(width: AppSpacing.s),
              Text(l.uidRecapture),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Text(activeUid == null ? l.uidNotSynced : displayName(activeUid)),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 全套檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

預期：format 無改、analyze 無警告、所有測試持續通過。

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/uid_indicator.dart
git commit -m "feat(uid_indicator): display alias and use custom order

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: `AccountManagement` 加拖曳排序

**Files:**
- Modify: `lib/widgets/cards/account_management.dart`
- Create: `test/widgets/cards/account_management_test.dart`

把既有的 `for (uid in uids)` 換成 `ReorderableListView`，按 `mergeUidOrder` 排序，拖曳完寫入 `setUidOrder`。

- [ ] **Step 1: 寫失敗測試**

建立 `test/widgets/cards/account_management_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/account_management.dart';

class _NullCapture implements WishCapture {
  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(null), cancel: () async {});
}

Future<ProviderContainer> _setupContainer({
  required WishStorage storage,
  Map<String, dynamic> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(Map<String, Object>.from(prefs));
  final container = ProviderContainer(
    overrides: [
      wishStorageProvider.overrideWithValue(storage),
      wishCaptureProvider.overrideWithValue(_NullCapture()),
      cancellableHttpClientFactoryProvider.overrideWithValue(
        () => CancellableHttpClient(
          client: MockClient((_) async => http.Response('{}', 200)),
          cancel: () {},
        ),
      ),
    ],
  );
  await container.read(settingsProvider.notifier).waitForLoad();
  container.read(wishRepositoryProvider);
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
        home: const Scaffold(body: AccountManagement()),
      ),
    );

void main() {
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('acct_mgmt_test_');
  });
  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('依 uidOrder 顯示順序', (tester) async {
    final storage = WishStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: 'A',
        lastUpdated: DateTime.utc(2026, 1, 1),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.save(
      BannerStorage(
        uid: 'B',
        lastUpdated: DateTime.utc(2026, 5, 9),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    final container = await _setupContainer(
      storage: storage,
      prefs: {'pref.uidOrder': '["A","B"]'},
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    final textsA = tester.getTopLeft(find.text('A')).dy;
    final textsB = tester.getTopLeft(find.text('B')).dy;
    expect(textsA, lessThan(textsB), reason: 'A 應該在 B 之前（依自訂順序）');
  });

  testWidgets('拖曳 row → 呼叫 setUidOrder', (tester) async {
    final storage = WishStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: 'A',
        lastUpdated: DateTime.utc(2026, 5, 9),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.save(
      BannerStorage(
        uid: 'B',
        lastUpdated: DateTime.utc(2026, 1, 1),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    final container = await _setupContainer(storage: storage);
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    // 用 ReorderableListView 的內部 onReorder 直接觸發 — 比 tester.drag 穩定
    // 找到 ReorderableListView 並透過其 onReorder callback
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorder(0, 2); // 把第 0 個 (A) 移到第 1 個（之後）
    await tester.pumpAndSettle();

    final reloaded = await SettingsStorage.load();
    expect(reloaded.uidOrder, ['B', 'A']);
  });
}
```

- [ ] **Step 2: 跑測試驗證失敗**

```bash
flutter test test/widgets/cards/account_management_test.dart
```

預期：FAIL（沒有 ReorderableListView、順序也不是自訂）。

- [ ] **Step 3: 修改 `lib/widgets/cards/account_management.dart`**

整個檔案替換為（加上 settingsProvider watch 與 ReorderableListView）：

```dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';

class AccountManagement extends ConsumerWidget {
  const AccountManagement({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final state = ref.watch(wishRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final ordered = state.byUid.isEmpty
        ? const <String>[]
        : mergeUidOrder(
            knownUids: state.byUid.keys,
            customOrder: settings.uidOrder,
            lastUpdatedOf: (u) => state.byUid[u]!.lastUpdated,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ordered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
            child: Text(
              l.accountListEmpty,
              style: TextStyle(color: tokens.textMuted),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: ordered.length,
            onReorder: (oldIndex, newIndex) async {
              final next = [...ordered];
              final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
              final item = next.removeAt(oldIndex);
              next.insert(adjusted, item);
              await settingsNotifier.setUidOrder(next);
            },
            itemBuilder: (context, index) {
              final uid = ordered[index];
              return _Row(
                key: ValueKey(uid),
                uid: uid,
                index: index,
                lastUpdated: state.byUid[uid]!.lastUpdated,
                isActive: uid == state.activeUid,
                onSetActive: () => notifier.setActiveUid(uid),
                onRemove: () => _remove(context, ref, uid),
              );
            },
          ),
        const Divider(),
        const SizedBox(height: AppSpacing.s),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => notifier.forceRecaptureAndUpdate(),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l.accountRecapture),
          ),
        ),
      ],
    );
  }

  Future<void> _remove(BuildContext ctx, WidgetRef ref, String uid) async {
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
    await ref.read(wishRepositoryProvider.notifier).removeUid(uid);
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.uid,
    required this.index,
    required this.lastUpdated,
    required this.isActive,
    required this.onSetActive,
    required this.onRemove,
  });

  final String uid;
  final int index;
  final DateTime lastUpdated;
  final bool isActive;
  final VoidCallback onSetActive;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Tooltip(
              message: l.accountDragHandleTooltip,
              child: Icon(
                Icons.drag_handle,
                color: tokens.textMuted,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      uid,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: AppSpacing.s),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.accentPrimary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          l.accountActiveTag,
                          style: TextStyle(
                            color: tokens.accentPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  l.accountLastUpdated(
                    DateFormat('yyyy-MM-dd HH:mm').format(lastUpdated.toLocal()),
                  ),
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (!isActive)
            TextButton(onPressed: onSetActive, child: Text(l.accountSetActive)),
          TextButton(
            onPressed: onRemove,
            child: Text(
              l.accountRemove,
              style: TextStyle(color: tokens.stateDanger),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 跑測試驗證通過**

```bash
flutter test test/widgets/cards/account_management_test.dart
```

預期：2 個測試 PASS。

- [ ] **Step 5: 全套檢查 + commit**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

```bash
git add lib/widgets/cards/account_management.dart test/widgets/cards/account_management_test.dart
git commit -m "feat(account_management): support drag-to-reorder

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: `AccountManagement` 加別名 TextField

**Files:**
- Modify: `lib/widgets/cards/account_management.dart`
- Modify: `test/widgets/cards/account_management_test.dart`

別名 TextField 用 `StatefulWidget`（為了 controller / focus 行為），失焦或 Enter 時呼叫 `setUidAlias`。

- [ ] **Step 1: 寫失敗測試**

在 `test/widgets/cards/account_management_test.dart` 內 `main()` 末端追加：

```dart
testWidgets('編輯別名 onSubmitted → 寫入 setUidAlias', (tester) async {
  final storage = WishStorage(tempDir);
  await storage.save(
    BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  final container = await _setupContainer(storage: storage);
  addTearDown(container.dispose);

  await tester.pumpWidget(_wrap(container));
  await tester.pumpAndSettle();

  final field = find.byType(TextField).first;
  await tester.enterText(field, '主帳號');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();

  final reloaded = await SettingsStorage.load();
  expect(reloaded.uidAliases, {'A': '主帳號'});
});

testWidgets('別名空字串 → 移除', (tester) async {
  final storage = WishStorage(tempDir);
  await storage.save(
    BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
    ),
  );
  final container = await _setupContainer(
    storage: storage,
    prefs: {'pref.uidAliases': '{"A":"舊名"}'},
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(_wrap(container));
  await tester.pumpAndSettle();

  final field = find.byType(TextField).first;
  await tester.enterText(field, '   ');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();

  final reloaded = await SettingsStorage.load();
  expect(reloaded.uidAliases, isEmpty);
});
```

- [ ] **Step 2: 跑測試驗證失敗**

```bash
flutter test test/widgets/cards/account_management_test.dart
```

預期：兩個新測試 FAIL（沒有 TextField）。

- [ ] **Step 3: 修改 `lib/widgets/cards/account_management.dart`**

把 `_Row` 改為 `ConsumerStatefulWidget`（為了讀 settings、寫 setUidAlias），並在 UID/active tag 那一列下方插入 TextField。整個檔案改寫為：

```dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';

class AccountManagement extends ConsumerWidget {
  const AccountManagement({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final state = ref.watch(wishRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final ordered = state.byUid.isEmpty
        ? const <String>[]
        : mergeUidOrder(
            knownUids: state.byUid.keys,
            customOrder: settings.uidOrder,
            lastUpdatedOf: (u) => state.byUid[u]!.lastUpdated,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ordered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
            child: Text(
              l.accountListEmpty,
              style: TextStyle(color: tokens.textMuted),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: ordered.length,
            onReorder: (oldIndex, newIndex) async {
              final next = [...ordered];
              final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
              final item = next.removeAt(oldIndex);
              next.insert(adjusted, item);
              await settingsNotifier.setUidOrder(next);
            },
            itemBuilder: (context, index) {
              final uid = ordered[index];
              return _Row(
                key: ValueKey(uid),
                uid: uid,
                index: index,
                lastUpdated: state.byUid[uid]!.lastUpdated,
                isActive: uid == state.activeUid,
                alias: settings.uidAliases[uid] ?? '',
                onSetActive: () => notifier.setActiveUid(uid),
                onRemove: () => _remove(context, ref, uid),
                onAliasSubmit: (value) =>
                    settingsNotifier.setUidAlias(uid, value),
              );
            },
          ),
        const Divider(),
        const SizedBox(height: AppSpacing.s),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => notifier.forceRecaptureAndUpdate(),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l.accountRecapture),
          ),
        ),
      ],
    );
  }

  Future<void> _remove(BuildContext ctx, WidgetRef ref, String uid) async {
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
    await ref.read(wishRepositoryProvider.notifier).removeUid(uid);
  }
}

class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.uid,
    required this.index,
    required this.lastUpdated,
    required this.isActive,
    required this.alias,
    required this.onSetActive,
    required this.onRemove,
    required this.onAliasSubmit,
  });

  final String uid;
  final int index;
  final DateTime lastUpdated;
  final bool isActive;
  final String alias;
  final VoidCallback onSetActive;
  final VoidCallback onRemove;
  final ValueChanged<String> onAliasSubmit;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.alias);
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _Row oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部 alias 變了（例如其他 row 觸發 rebuild）才 sync
    if (widget.alias != oldWidget.alias && _ctrl.text != widget.alias) {
      _ctrl.text = widget.alias;
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) {
      widget.onAliasSubmit(_ctrl.text);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: Tooltip(
              message: l.accountDragHandleTooltip,
              child: Icon(
                Icons.drag_handle,
                color: tokens.textMuted,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.uid,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (widget.isActive) ...[
                      const SizedBox(width: AppSpacing.s),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.accentPrimary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          l.accountActiveTag,
                          style: TextStyle(
                            color: tokens.accentPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  l.accountLastUpdated(
                    DateFormat('yyyy-MM-dd HH:mm')
                        .format(widget.lastUpdated.toLocal()),
                  ),
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
                const SizedBox(height: AppSpacing.s),
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    textInputAction: TextInputAction.done,
                    onSubmitted: widget.onAliasSubmit,
                    decoration: InputDecoration(
                      labelText: l.accountAliasLabel,
                      hintText: l.accountAliasHint,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!widget.isActive)
            TextButton(
              onPressed: widget.onSetActive,
              child: Text(l.accountSetActive),
            ),
          TextButton(
            onPressed: widget.onRemove,
            child: Text(
              l.accountRemove,
              style: TextStyle(color: tokens.stateDanger),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 跑測試驗證通過**

```bash
flutter test test/widgets/cards/account_management_test.dart
```

預期：4 個測試全 PASS。

- [ ] **Step 5: 全套檢查 + commit**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

```bash
git add lib/widgets/cards/account_management.dart test/widgets/cards/account_management_test.dart
git commit -m "feat(account_management): support per-UID alias editing

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 13: 手動驗證

最後做一次 manual smoke test，確認整套行為：

- [ ] **Step 1: 啟動 app**

```bash
flutter run -d windows
```

- [ ] **Step 2: 驗證下列情境（自行勾選）**

   - [ ] 開啟 app，頂部 UidIndicator 顯示「（活躍）」UID（首次開啟時為最新者）
   - [ ] UidIndicator 下拉選擇另一個 UID → 切換成功
   - [ ] **關閉 app 重開** → 維持在剛剛切換的 UID（核心需求）
   - [ ] 進 Settings → 帳號管理區塊 → 拖曳排序 → 上下重排 → 重開 app 後 UidIndicator 下拉選單順序維持
   - [ ] 在某個帳號的別名欄位輸入「主帳」→ 按 Enter → UidIndicator 主按鈕顯示「主帳 (UID)」、下拉選單同樣顯示
   - [ ] 別名輸入空字串 + Enter → UidIndicator 回到只顯示 UID
   - [ ] 刪除某個帳號（要打 UID 確認）→ 帳號被移除、別名與排序中對應該 UID 的條目被清掉
   - [ ] 刪到只剩一個帳號 → 該帳號自動成為 active；刪到 0 → UidIndicator 顯示「未同步」
   - [ ] 匯入 JSON 一個新 UID → 自動成為 active，重開後維持

- [ ] **Step 3: 若一切 OK，無需 commit**

如果發現問題，停下並回報；不要嘗試「快速修一下」就 commit。

---

## Files Touched 總覽（執行完成後）

| 路徑 | 動作 |
|---|---|
| `lib/services/uid_ordering.dart` | 新增 |
| `lib/services/settings_storage.dart` | 修改 |
| `lib/state/settings.dart` | 修改 |
| `lib/state/wish_repository.dart` | 修改 |
| `lib/widgets/uid_indicator.dart` | 修改 |
| `lib/widgets/cards/account_management.dart` | 新增（含 refactor + 新功能） |
| `lib/pages/settings_page.dart` | 修改（移除內聯 `_AccountManagement`） |
| `lib/l10n/app_zh_Hant.arb` / `app_zh.arb` / `app_zh_Hans.arb` / `app_en.arb` | 修改 |
| `lib/l10n/generated/*` | 由 `flutter gen-l10n` 重產 |
| `test/services/uid_ordering_test.dart` | 新增 |
| `test/services/settings_storage_test.dart` | 修改（追加） |
| `test/state/settings_test.dart` | 修改（追加） |
| `test/state/wish_repository_test.dart` | 修改（追加） |
| `test/widgets/cards/account_management_test.dart` | 新增 |
