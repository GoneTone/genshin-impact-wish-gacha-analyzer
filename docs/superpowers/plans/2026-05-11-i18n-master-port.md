# i18n: 沿用 master 多國語言翻譯 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把舊版 master 分支 31 種語言的翻譯（透過離線一次性腳本）匯入 flutter-rewrite 的 ARB 結構（其中 3 種已存在、1 種空檔跳過 → 新增 27 個 ARB）；把 Settings 語言選單從寫死 4 項擴充成「跟隨系統 + 30 種語言」的動態選單，並在 About 區塊顯示翻譯者署名。

**Architecture:** `AppLocale` enum 重構為 `LanguagePreference` sealed class（`SystemLanguage` / `LocaleLanguage(code)`），BCP-47 code 字串為資料來源；每個 ARB 自帶 `localeNativeName` 與 `localeTranslator` 兩個 metadata key，UI 完全資料驅動。新 key → 舊 key 映射由本地（`.gitignored`）的 Dart 腳本驅動，跑完即用即丟。缺 key 靠 Flutter `gen_l10n` 自動 fallback 到 template ARB (`app_zh_Hant.arb`)。

**Tech Stack:** Flutter / `flutter_localizations` / `gen_l10n` / `flutter_riverpod` / `shared_preferences` / Dart sealed classes

**Spec:** `docs/superpowers/specs/2026-05-11-i18n-master-port-design.md`

**Pre-flight check (Claude before Task 1):**
- 已 verify `master:src/locales/sr_SP.json` 為 `{}` → sr 跳過。
- 已 verify `lib/l10n/generated/` 為 tracked（IDE 自動產出但 commit）。
- 已 verify `/docs/superpowers/` 在 `.gitignore` → plan 寫好不 commit，留本地。

---

## File Structure

### 新增（committed）
- `lib/state/localization_metadata.dart` — `LocaleMetadata` model + `localeMetadataProvider` (FutureProvider，一次性 load 所有 supported locale 的 metadata)
- `test/state/locale_provider_test.dart` — `localeProvider` 解析測試
- `test/l10n/locale_metadata_test.dart` — 每個 ARB 的 `localeNativeName` 非空、原始語言 `localeTranslator` 為空
- `lib/l10n/app_af.arb`、`app_ar.arb` … 共 27 個 ARB（pt 拆 BR/PT；無 sr）— **腳本生成**
- `lib/l10n/generated/app_localizations_<lang>.dart` 共 28 個（unique 語言代碼：en, zh, af, ar, ca, cs, da, de, el, es, fi, fr, he, hu, it, ja, ko, nl, no, pl, pt, ro, ru, sv, th, tr, uk, vi；zh 含 Hant/Hans、pt 含 BR/PT 共用同一 Dart 檔）— **gen_l10n 自動產**

### 修改（committed）
- `lib/services/settings_storage.dart` — `AppLocale` enum → `LanguagePreference` sealed class
- `lib/state/settings.dart` — `setLocale` 參數型別、`localeProvider` 解析邏輯
- `lib/pages/settings_page.dart` — `_LocaleDropdown` 動態列表 + `_AboutContent` 加 translator 顯示
- `lib/l10n/app_zh_Hant.arb` — 加 `localeNativeName` / `localeTranslator`；移除 `settingsLocaleZhHant` / `Hans` / `En` 三個 key
- `lib/l10n/app_zh_Hans.arb` — 同上
- `lib/l10n/app_en.arb` — 同上
- `lib/l10n/generated/app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart` — gen_l10n 重新產出
- `test/services/settings_storage_test.dart` — 既有 `AppLocale.xxx` references 改成 `LanguagePreference` 對應形式
- `test/state/settings_test.dart` — 既有 `AppLocale.system` reference 改成 `const SystemLanguage()`
- `.gitignore` — 加 `tool/i18n_port/`

### 本地（never committed，跑完即可手動清掉）
- `tool/i18n_port/port.dart` — 腳本本體
- `tool/i18n_port/key_mappings.dart` — 新 key → 舊 key 映射（Dart const data，不用 YAML 避免增加 deps）
- `tool/i18n_port/locale_mappings.dart` — 舊 locale code → ARB 檔名 + Flutter Locale code
- `tool/i18n_port/README.md` — 怎麼跑、為什麼不進版控

---

## Task 1: 重構 AppLocale 為 LanguagePreference sealed class

**Files:**
- Modify: `lib/services/settings_storage.dart`
- Modify: `lib/state/settings.dart`
- Modify: `lib/pages/settings_page.dart` (lines 112-149，`_LocaleDropdown`)
- Modify: `test/services/settings_storage_test.dart`
- Modify: `test/state/settings_test.dart`
- Create: `test/state/locale_provider_test.dart`

### Step 1.1: 寫 LanguagePreference 單元測試（先擴充 settings_storage_test.dart）

- [ ] **替換 `test/services/settings_storage_test.dart` 全部內容**

把整個檔案改成：

```dart
// test/services/settings_storage_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LanguagePreference', () {
    test('fromCode("system") 回傳 SystemLanguage', () {
      expect(LanguagePreference.fromCode('system'), isA<SystemLanguage>());
    });

    test('fromCode("zh-Hant") 回傳 LocaleLanguage("zh-Hant")', () {
      final pref = LanguagePreference.fromCode('zh-Hant');
      expect(pref, isA<LocaleLanguage>());
      expect((pref as LocaleLanguage).code, 'zh-Hant');
    });

    test('fromCode("pt-BR") 回傳 LocaleLanguage("pt-BR")', () {
      final pref = LanguagePreference.fromCode('pt-BR');
      expect((pref as LocaleLanguage).code, 'pt-BR');
    });

    test('toCode roundtrip 在 system / zh-Hant / zh-Hans / en / pt-BR / ja 都保持原值', () {
      for (final code in ['system', 'zh-Hant', 'zh-Hans', 'en', 'pt-BR', 'ja']) {
        expect(LanguagePreference.fromCode(code).toCode(), code);
      }
    });

    test('SystemLanguage 相等比較', () {
      expect(const SystemLanguage() == const SystemLanguage(), isTrue);
      expect(const SystemLanguage() == const LocaleLanguage('en'), isFalse);
    });

    test('LocaleLanguage 依 code 相等', () {
      expect(
        const LocaleLanguage('zh-Hant') == const LocaleLanguage('zh-Hant'),
        isTrue,
      );
      expect(
        const LocaleLanguage('zh-Hant') == const LocaleLanguage('zh-Hans'),
        isFalse,
      );
    });

    test('hashCode 與 == 一致', () {
      expect(
        const LocaleLanguage('ja').hashCode,
        const LocaleLanguage('ja').hashCode,
      );
      expect(const SystemLanguage().hashCode, const SystemLanguage().hashCode);
    });
  });

  group('SettingsStorage', () {
    test('預設回傳 system theme 與 SystemLanguage locale', () async {
      final s = await SettingsStorage.load();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.locale, const SystemLanguage());
    });

    test('save 後 load 回得到相同值', () async {
      await SettingsStorage.save(
        const AppSettings(
          themeMode: AppThemeMode.dark,
          locale: LocaleLanguage('en'),
        ),
      );
      final s = await SettingsStorage.load();
      expect(s.themeMode, AppThemeMode.dark);
      expect(s.locale, const LocaleLanguage('en'));
    });

    test('未知 themeMode 降級為 system；任意非 system locale 字串為 LocaleLanguage', () async {
      SharedPreferences.setMockInitialValues({
        'pref.themeMode': 'rainbow',
        'pref.locale': 'ja',
      });
      final s = await SettingsStorage.load();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.locale, const LocaleLanguage('ja'));
    });

    test('舊資料 "zh-Hant" 仍能正確解析（向後相容）', () async {
      SharedPreferences.setMockInitialValues({'pref.locale': 'zh-Hant'});
      final s = await SettingsStorage.load();
      expect(s.locale, const LocaleLanguage('zh-Hant'));
    });

    test('locale = "system" 字串 解析為 SystemLanguage', () async {
      SharedPreferences.setMockInitialValues({'pref.locale': 'system'});
      final s = await SettingsStorage.load();
      expect(s.locale, const SystemLanguage());
    });

    test('locale 缺欄位（null）解析為 SystemLanguage', () async {
      final s = await SettingsStorage.load();
      expect(s.locale, const SystemLanguage());
    });

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
          locale: SystemLanguage(),
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
          locale: SystemLanguage(),
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
          locale: SystemLanguage(),
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
      SharedPreferences.setMockInitialValues({'pref.uidOrder': '{not-a-list}'});
      final s = await SettingsStorage.load();
      expect(s.uidOrder, isEmpty);
    });
  });
}
```

- [ ] **執行：`flutter test test/services/settings_storage_test.dart`**

Expected: **FAIL** — `LanguagePreference` / `SystemLanguage` / `LocaleLanguage` 不存在。

### Step 1.2: 改 `lib/services/settings_storage.dart`

- [ ] **整個檔案改成**：

```dart
// lib/services/settings_storage.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, dark, light }

/// 使用者偏好的語言：跟隨系統（[SystemLanguage]）或指定 BCP-47 locale
/// （[LocaleLanguage]，例如 "zh-Hant"、"pt-BR"、"ja"）。
sealed class LanguagePreference {
  const LanguagePreference();

  factory LanguagePreference.fromCode(String code) =>
      code == 'system' ? const SystemLanguage() : LocaleLanguage(code);

  /// 序列化字串（給 SharedPreferences 用），可被 [fromCode] 還原。
  String toCode();
}

class SystemLanguage extends LanguagePreference {
  const SystemLanguage();

  @override
  String toCode() => 'system';

  @override
  bool operator ==(Object other) => other is SystemLanguage;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'SystemLanguage';
}

class LocaleLanguage extends LanguagePreference {
  const LocaleLanguage(this.code);

  /// BCP-47 code，例如 "zh-Hant"、"pt-BR"、"ja"。
  final String code;

  @override
  String toCode() => code;

  @override
  bool operator ==(Object other) =>
      other is LocaleLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'LocaleLanguage($code)';
}

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
  final LanguagePreference locale;
  final String? lastActiveUid;
  final Map<String, String> uidAliases;
  final List<String> uidOrder;

  static const defaults = AppSettings(
    themeMode: AppThemeMode.system,
    locale: SystemLanguage(),
  );

  AppSettings copyWith({
    AppThemeMode? themeMode,
    LanguagePreference? locale,
    String? lastActiveUid,
    bool clearLastActiveUid = false,
    Map<String, String>? uidAliases,
    List<String>? uidOrder,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
    lastActiveUid: clearLastActiveUid
        ? null
        : (lastActiveUid ?? this.lastActiveUid),
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
    await prefs.setString(_kLocale, s.locale.toCode());
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

  static LanguagePreference _parseLocale(String? raw) =>
      (raw == null || raw.isEmpty)
      ? const SystemLanguage()
      : LanguagePreference.fromCode(raw);

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

- [ ] **執行：`flutter test test/services/settings_storage_test.dart`**

Expected: **PASS** (所有 16 個 test)。

### Step 1.3: 改 `lib/state/settings.dart`

- [ ] **整個檔案改成**：

```dart
// lib/state/settings.dart
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

  Future<void> setLocale(LanguagePreference locale) async {
    state = state.copyWith(locale: locale);
    await SettingsStorage.save(state);
  }

  Future<void> setLastActiveUid(String? uid) async {
    state = state.copyWith(lastActiveUid: uid, clearLastActiveUid: uid == null);
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

/// 給 MaterialApp 直接吃的 Locale?（system → null；其他 BCP-47 code 解析為 Locale）
final localeProvider = Provider<Locale?>((ref) {
  final pref = ref.watch(settingsProvider).locale;
  return switch (pref) {
    SystemLanguage() => null,
    LocaleLanguage(:final code) => _localeFromCode(code),
  };
});

/// 把 BCP-47 dash-form (e.g. "zh-Hant", "pt-BR", "ja") 轉成 Flutter [Locale]。
Locale _localeFromCode(String code) {
  final parts = code.split('-');
  return parts.length == 1 ? Locale(parts[0]) : Locale(parts[0], parts[1]);
}
```

### Step 1.4: 改 `test/state/settings_test.dart` 內 `AppLocale` 引用

- [ ] **改 line 22**：

把
```dart
expect(s.locale, AppLocale.system);
```
改成
```dart
expect(s.locale, const SystemLanguage());
```

(其他行不需改，沒有用到 `AppLocale`。)

### Step 1.5: 新增 `test/state/locale_provider_test.dart`

- [ ] **新建檔案內容**：

```dart
// test/state/locale_provider_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> makeContainer(LanguagePreference initial) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    await container.read(settingsProvider.notifier).setLocale(initial);
    return container;
  }

  test('SystemLanguage → null', () async {
    final c = await makeContainer(const SystemLanguage());
    expect(c.read(localeProvider), isNull);
  });

  test('LocaleLanguage("zh-Hant") → Locale("zh", "Hant")', () async {
    final c = await makeContainer(const LocaleLanguage('zh-Hant'));
    expect(c.read(localeProvider), const Locale('zh', 'Hant'));
  });

  test('LocaleLanguage("zh-Hans") → Locale("zh", "Hans")', () async {
    final c = await makeContainer(const LocaleLanguage('zh-Hans'));
    expect(c.read(localeProvider), const Locale('zh', 'Hans'));
  });

  test('LocaleLanguage("pt-BR") → Locale("pt", "BR")', () async {
    final c = await makeContainer(const LocaleLanguage('pt-BR'));
    expect(c.read(localeProvider), const Locale('pt', 'BR'));
  });

  test('LocaleLanguage("pt-PT") → Locale("pt", "PT")', () async {
    final c = await makeContainer(const LocaleLanguage('pt-PT'));
    expect(c.read(localeProvider), const Locale('pt', 'PT'));
  });

  test('LocaleLanguage("ja") → Locale("ja")', () async {
    final c = await makeContainer(const LocaleLanguage('ja'));
    expect(c.read(localeProvider), const Locale('ja'));
  });

  test('LocaleLanguage("en") → Locale("en")', () async {
    final c = await makeContainer(const LocaleLanguage('en'));
    expect(c.read(localeProvider), const Locale('en'));
  });
}
```

### Step 1.6: 改 `lib/pages/settings_page.dart` `_LocaleDropdown`

- [ ] **取代 lines 112-150（整個 `_LocaleDropdown` class）**：

```dart
class _LocaleDropdown extends StatelessWidget {
  const _LocaleDropdown({
    required this.current,
    required this.onChanged,
    required this.l,
  });
  final LanguagePreference current;
  final ValueChanged<LanguagePreference> onChanged;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<LanguagePreference>(
      initialValue: current,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        DropdownMenuItem(
          value: const SystemLanguage(),
          child: Text(l.settingsLocaleSystem),
        ),
        DropdownMenuItem(
          value: const LocaleLanguage('zh-Hant'),
          child: Text(l.settingsLocaleZhHant),
        ),
        DropdownMenuItem(
          value: const LocaleLanguage('zh-Hans'),
          child: Text(l.settingsLocaleZhHans),
        ),
        DropdownMenuItem(
          value: const LocaleLanguage('en'),
          child: Text(l.settingsLocaleEn),
        ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
```

注意：這階段 dropdown 仍 hardcoded 4 個選項，下一階段（Task 6）才動態化。`onChanged` 接收的是 `LanguagePreference`，呼叫 `notifier.setLocale(LanguagePreference)`，與 Task 1.3 的 `setLocale` 簽章一致。

### Step 1.7: 跑全套驗證

- [ ] **執行：`dart format lib/ test/`**

Expected: 印出修改檔案，正常 exit。

- [ ] **執行：`flutter analyze`**

Expected: `No issues found!`

- [ ] **執行：`flutter test`**

Expected: `All tests passed!`

### Step 1.8: Commit

- [ ] **執行：**

```bash
git add lib/services/settings_storage.dart \
        lib/state/settings.dart \
        lib/pages/settings_page.dart \
        test/services/settings_storage_test.dart \
        test/state/settings_test.dart \
        test/state/locale_provider_test.dart
git commit -m "$(cat <<'EOF'
feat(i18n): refactor AppLocale to LanguagePreference sealed class

把寫死 4 值的 AppLocale enum 換成 LanguagePreference sealed class
(SystemLanguage / LocaleLanguage(code))，以 BCP-47 code 字串作為資料來源，
為後續擴充 27 個新語言鋪路。SharedPreferences 內舊值（"zh-Hant" / "en" 等）
仍可正確解析，不需遷移程式碼。Settings dropdown 暫時保持 hardcoded 4 項，
Task 6 才動態化。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: 加 `.gitignore` 排除一次性腳本目錄

**Files:**
- Modify: `.gitignore`

### Step 2.1: 編輯 `.gitignore`

- [ ] **在 `/docs/superpowers/` 區塊下加一條規則**：

把
```
# Local design specs / brainstorming notes (not tracked)
/docs/superpowers/
/.superpowers/
```

改成
```
# Local design specs / brainstorming notes (not tracked)
/docs/superpowers/
/.superpowers/

# One-shot porting tool (run once, then discard locally — not tracked)
/tool/i18n_port/
```

### Step 2.2: 驗證 `.gitignore` 規則生效

- [ ] **執行：`mkdir -p tool/i18n_port && echo placeholder > tool/i18n_port/test.txt && git check-ignore -v tool/i18n_port/test.txt`**

Expected: 印出 `.gitignore:NN:/tool/i18n_port/  tool/i18n_port/test.txt`（路徑被正確 ignore）。

- [ ] **執行：`rm tool/i18n_port/test.txt`**（清掉測試檔；保留空目錄）

### Step 2.3: Commit

- [ ] **執行：**

```bash
git add .gitignore
git commit -m "$(cat <<'EOF'
chore(tool): ignore i18n port working dir

新增 /tool/i18n_port/ 到 .gitignore。下一階段會在這個目錄建立一次性
ARB 生成腳本與映射表，跑完即用即丟，不進版控。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: 建立一次性腳本骨架（本地，不 commit）

**Files (all local, not committed):**
- Create: `tool/i18n_port/locale_mappings.dart`
- Create: `tool/i18n_port/port.dart`
- Create: `tool/i18n_port/README.md`

### Step 3.1: 建 `tool/i18n_port/locale_mappings.dart`

- [ ] **新建檔案**：

```dart
// tool/i18n_port/locale_mappings.dart
//
// 舊 master locale code（src/locales/<oldCode>.json）→ 新 ARB 配置。
//
// `arbSuffix` 是 ARB 檔名 prefix `app_` 後面接的部分 + `.arb`，
// 同時是 @@locale 內的值。
// 例如 arbSuffix = "zh_Hant" → app_zh_Hant.arb，@@locale = "zh_Hant"。
//
// 注意：sr_SP.json 已 verify 為空檔 {}，不在此清單。

class LocaleEntry {
  const LocaleEntry({required this.oldCode, required this.arbSuffix});
  final String oldCode;    // master 端的 src/locales/<oldCode>.json
  final String arbSuffix;  // 新版 ARB 檔名中的 locale 部分
}

const List<LocaleEntry> localeEntries = [
  // 已存在的 3 個 ARB 也列在這（腳本可選擇覆寫 metadata key，
  // 不一定要重生整檔——見 port.dart 的 --skip-existing flag）
  LocaleEntry(oldCode: 'en_US',  arbSuffix: 'en'),
  LocaleEntry(oldCode: 'zh_CN',  arbSuffix: 'zh_Hans'),
  LocaleEntry(oldCode: 'zh_TW',  arbSuffix: 'zh_Hant'),

  // 27 個新增（pt 拆 BR/PT；無 sr）
  LocaleEntry(oldCode: 'af_ZA',  arbSuffix: 'af'),
  LocaleEntry(oldCode: 'ar_SA',  arbSuffix: 'ar'),
  LocaleEntry(oldCode: 'ca_ES',  arbSuffix: 'ca'),
  LocaleEntry(oldCode: 'cs_CZ',  arbSuffix: 'cs'),
  LocaleEntry(oldCode: 'da_DK',  arbSuffix: 'da'),
  LocaleEntry(oldCode: 'de_DE',  arbSuffix: 'de'),
  LocaleEntry(oldCode: 'el_GR',  arbSuffix: 'el'),
  LocaleEntry(oldCode: 'es_ES',  arbSuffix: 'es'),
  LocaleEntry(oldCode: 'fi_FI',  arbSuffix: 'fi'),
  LocaleEntry(oldCode: 'fr_FR',  arbSuffix: 'fr'),
  LocaleEntry(oldCode: 'he_IL',  arbSuffix: 'he'),
  LocaleEntry(oldCode: 'hu_HU',  arbSuffix: 'hu'),
  LocaleEntry(oldCode: 'it_IT',  arbSuffix: 'it'),
  LocaleEntry(oldCode: 'ja_JP',  arbSuffix: 'ja'),
  LocaleEntry(oldCode: 'ko_KR',  arbSuffix: 'ko'),
  LocaleEntry(oldCode: 'nl_NL',  arbSuffix: 'nl'),
  LocaleEntry(oldCode: 'no_NO',  arbSuffix: 'no'),
  LocaleEntry(oldCode: 'pl_PL',  arbSuffix: 'pl'),
  LocaleEntry(oldCode: 'pt_BR',  arbSuffix: 'pt_BR'),
  LocaleEntry(oldCode: 'pt_PT',  arbSuffix: 'pt_PT'),
  LocaleEntry(oldCode: 'ro_RO',  arbSuffix: 'ro'),
  LocaleEntry(oldCode: 'ru_RU',  arbSuffix: 'ru'),
  LocaleEntry(oldCode: 'sv_SE',  arbSuffix: 'sv'),
  LocaleEntry(oldCode: 'th_TH',  arbSuffix: 'th'),
  LocaleEntry(oldCode: 'tr_TR',  arbSuffix: 'tr'),
  LocaleEntry(oldCode: 'uk_UA',  arbSuffix: 'uk'),
  LocaleEntry(oldCode: 'vi_VN',  arbSuffix: 'vi'),
];
```

### Step 3.2: 建 `tool/i18n_port/port.dart` (script skeleton)

- [ ] **新建檔案**（key_mappings 部分將在 Task 4 填入）：

```dart
// tool/i18n_port/port.dart
//
// 一次性腳本：把舊 master src/locales/<code>.json 透過 key_mappings.dart 內
// 的映射表轉成 lib/l10n/app_<arbSuffix>.arb。
//
// 跑法：dart run tool/i18n_port/port.dart [--dry-run] [--only=ja,ko]
//
// 跑完後：手動執行 `flutter gen-l10n` 重新產出 lib/l10n/generated/。

import 'dart:convert';
import 'dart:io';

import 'key_mappings.dart';
import 'locale_mappings.dart';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final onlyArg = args.firstWhere(
    (a) => a.startsWith('--only='),
    orElse: () => '',
  );
  final onlyFilter = onlyArg.isEmpty
      ? null
      : onlyArg.substring('--only='.length).split(',').toSet();

  // 確保 git 在 master 分支上可達 src/locales/
  _ensureMasterAccessible();

  for (final entry in localeEntries) {
    if (onlyFilter != null && !onlyFilter.contains(entry.arbSuffix)) continue;

    stdout.writeln('→ Processing ${entry.oldCode} → app_${entry.arbSuffix}.arb');
    final oldJson = _readOldLocale(entry.oldCode);
    if (oldJson == null) {
      stderr.writeln('  ! skipped: master:src/locales/${entry.oldCode}.json not found');
      continue;
    }

    final arb = <String, dynamic>{
      '@@locale': entry.arbSuffix,
    };

    // localeNativeName / localeTranslator 直接從舊 lang.name / lang.translator 帶入
    arb['localeNativeName'] = (oldJson['lang.name'] as String?)?.trim().isNotEmpty == true
        ? oldJson['lang.name']
        : entry.arbSuffix;
    arb['localeTranslator'] = oldJson['lang.translator'] as String? ?? '';

    // 套映射表
    for (final m in keyMappings) {
      final oldValue = oldJson[m.oldKey];
      if (oldValue is! String) continue;
      arb[m.newKey] = _applyPlaceholderRenames(oldValue, m.placeholders);
    }

    final encoded = const JsonEncoder.withIndent('  ').convert(arb);
    final outPath = 'lib/l10n/app_${entry.arbSuffix}.arb';
    if (dryRun) {
      stdout.writeln('  (dry-run) would write ${arb.length} keys to $outPath');
    } else {
      File(outPath).writeAsStringSync('$encoded\n');
      stdout.writeln('  wrote ${arb.length} keys to $outPath');
    }
  }

  stdout.writeln('\nDone. Now run: flutter gen-l10n');
}

void _ensureMasterAccessible() {
  final result = Process.runSync('git', ['rev-parse', '--verify', 'master']);
  if (result.exitCode != 0) {
    stderr.writeln('Error: git ref "master" not found. This script reads '
        'old locales via "git show master:src/locales/<code>.json".');
    exit(1);
  }
}

Map<String, dynamic>? _readOldLocale(String oldCode) {
  final result = Process.runSync(
    'git',
    ['show', 'master:src/locales/$oldCode.json'],
    stdoutEncoding: utf8,
  );
  if (result.exitCode != 0) return null;
  final raw = result.stdout as String;
  if (raw.trim().isEmpty || raw.trim() == '{}') return null;
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// 把字串內 `{oldName}` 替換成 `{newName}`。
/// `placeholders` map: key = new name, value = old name。
String _applyPlaceholderRenames(
  String input,
  Map<String, String> placeholders,
) {
  var out = input;
  for (final e in placeholders.entries) {
    if (e.key == e.value) continue;
    out = out.replaceAll('{${e.value}}', '{${e.key}}');
  }
  return out;
}
```

### Step 3.3: 建 `tool/i18n_port/README.md`

- [ ] **新建檔案**：

```markdown
# i18n_port (one-shot)

把 master 分支 `src/locales/*.json` 的翻譯透過 `key_mappings.dart` 映射表
匯入 flutter-rewrite 的 `lib/l10n/app_<locale>.arb`。

## 一次性，不進版控

整個 `tool/i18n_port/` 在 `.gitignore` 內。跑完即可手動 `rm -rf tool/i18n_port/`。

## 跑法

```bash
# 預演（不實際寫檔）
dart run tool/i18n_port/port.dart --dry-run

# 全部跑
dart run tool/i18n_port/port.dart

# 只跑某幾個
dart run tool/i18n_port/port.dart --only=ja,ko

# 跑完後重新產生 Dart code
flutter gen-l10n
```

## 依賴

腳本透過 `git show master:src/locales/<code>.json` 讀舊翻譯，所以
working tree 需要在 git repo 內且 master ref 可達。
```

### Step 3.4: 驗證腳本骨架沒語法錯

- [ ] **執行：`dart analyze tool/i18n_port/`**

Expected: 因為 `key_mappings.dart` 還不存在，會報「Target of URI doesn't exist: 'key_mappings.dart'」。**這是預期的** — Task 4 才補上。

**Checkpoint**：此 Task 不 commit（檔案皆在 `tool/i18n_port/` 內被 ignore）。`git status` 應顯示 working tree clean。

---

## Task 4: 寫 key 映射表（本地，user review）

**Files (local, not committed):**
- Create: `tool/i18n_port/key_mappings.dart`

### Step 4.1: 寫 `tool/i18n_port/key_mappings.dart`

執行此 step 的程序（procedure，不是「fill in later」）：

1. **讀兩個來源檔**：
   - `lib/l10n/app_zh_Hant.arb`（新版 100+ keys）
   - `git show master:src/locales/zh_TW.json | head -300`（舊版 ~130 keys；只用 zh_TW 作為「中文對中文」的語意對照基準，其他 30 個舊 JSON 結構相同，內容是翻譯）
2. **逐 key 走過新版 ARB**，順序由上到下：
   - 對每個新 key，在舊 JSON 找語意對應（兩邊中文翻譯描述同一個 UI 元素或概念）。
   - 找到 → 加一條 `KeyMapping(newKey: '...', oldKey: '...')`。
   - 含 placeholder 且名稱不同 → 加 `placeholders: {'newName': 'oldName'}`。
   - 找不到、或語意不確定 → **不加 mapping**，把它記到檔尾「Review Notes」段落說明為什麼跳過。
3. **產出** `tool/i18n_port/key_mappings.dart`，結構如下面 starter 範例。
4. 結束後跳到 Step 4.2 寫 review notes、Step 4.3 請 user review。

> **這 step 的本質是 authoring（人工/LLM 翻譯對照工作），不是 coding**。所以沒有 unit test；產出由 Step 4.3 的 user review + Step 5 的 spot check 把關。

- [ ] **新建 `tool/i18n_port/key_mappings.dart`**。以下是 starter 範例（已對照 zh_Hant.arb + zh_TW.json 列出的「明確 1:1 對應」）；執行者應在此基礎上繼續補完剩下的新 key（procedure 詳見上面）。

```dart
// tool/i18n_port/key_mappings.dart
//
// 新版 ARB key → 舊版 vue-i18n key 的映射表。
//
// placeholders: 新版 placeholder name → 舊版 placeholder name
// （字串內 `{old}` 會被換成 `{new}`）
//
// 沒在這份 list 內的新版 key（如 progress* / pity* / timeline* / account* /
// confirm* / settingsExport* / settingsImport* 等大多數）→ 腳本直接省略，
// 27 個新 ARB 缺這些 key 時 Flutter gen_l10n 會自動 fallback 到 template
// (app_zh_Hant.arb)。

class KeyMapping {
  const KeyMapping({
    required this.newKey,
    required this.oldKey,
    this.placeholders = const {},
  });
  final String newKey;
  final String oldKey;
  final Map<String, String> placeholders;
}

const List<KeyMapping> keyMappings = [
  // ===== App name =====
  KeyMapping(newKey: 'appName', oldKey: 'app.name'),

  // ===== Actions =====
  KeyMapping(newKey: 'actionUpdate',   oldKey: 'ui.text.update_data'),
  KeyMapping(newKey: 'actionClose',    oldKey: 'ui.text.close_msg'),
  KeyMapping(newKey: 'actionPrevPage', oldKey: 'ui.text.table.data_table.paginate.previous'),
  KeyMapping(newKey: 'actionNextPage', oldKey: 'ui.text.table.data_table.paginate.next'),
  // actionCancel: 舊版只有 "ui.text.lightbox.close_buttonTitle" / "ui.text.lightbox.close_buttonAriaLabel"，
  //               或 "ui.text.update.title" 但語意不對；直接不映射，靠 fallback。

  // ===== Navigation =====
  KeyMapping(newKey: 'navOverview',  oldKey: 'ui.text.comprehensive'),
  KeyMapping(newKey: 'navCharacter', oldKey: 'ui.text.character'),
  KeyMapping(newKey: 'navWeapon',    oldKey: 'ui.text.weapon'),
  // navChronicled: 舊版無「集錄」概念，不映射
  // navStandard:   舊版用 "ui.text.various_gacha"（各類卡池）語意太遠，不映射
  // navBeginner:   舊版無新手卡池單獨字串，不映射
  // navSettings:   舊版用 "ui.text.about"/"ui.text.other" 都不準，不映射

  // ===== Gacha types =====
  // 舊版的 gacha 名稱在 src/data/*.json 而非 locales/，且不是翻譯字串；不映射

  // ===== Footer =====
  KeyMapping(
    newKey: 'footerLastUpdated',
    oldKey: 'ui.text.data_update_time',
    placeholders: {'time': 'time'},
  ),
  // footerNotSynced: 舊版無此狀態，不映射

  // ===== Stats =====
  // statsTotal:                舊版 "ui.text.table.total_of_draws"（總抽數），語意一致
  KeyMapping(newKey: 'statsTotal', oldKey: 'ui.text.table.total_of_draws'),
  // statsFiveStarCount:        舊版 "ui.text.count_of_win_by_five_rank"（5星中獎數）
  KeyMapping(newKey: 'statsFiveStarCount', oldKey: 'ui.text.count_of_win_by_five_rank'),
  // statsFourStarCount:        舊版 "ui.text.count_of_win_by_four_rank"
  KeyMapping(newKey: 'statsFourStarCount', oldKey: 'ui.text.count_of_win_by_four_rank'),
  // statsShareOfTotal:         舊版無「占總抽 X%」字串，不映射
  // statsRarityDistribution:   舊版 "ui.text.chance_of_win_by_rank"（級別中獎率）語意接近但
  //                            不完全相同；保守起見不映射，讓 fallback 顯示繁中。
  // statsItemTypeDistribution: 同上，"ui.text.chance_of_win_by_character_and_weapon" 太具體，不映射
  // statsNoData:               舊版 "ui.text.table.data_table.info_empty"（沒有任何資料）語意接近
  KeyMapping(newKey: 'statsNoData', oldKey: 'ui.text.table.data_table.info_empty'),

  // ===== Item kind =====
  KeyMapping(newKey: 'kindCharacter', oldKey: 'ui.text.character'),
  KeyMapping(newKey: 'kindWeapon',    oldKey: 'ui.text.weapon'),
  // kindUnknown: 舊版無，不映射

  // ===== Table =====
  KeyMapping(newKey: 'tableTime',              oldKey: 'ui.text.table.get_time'),
  KeyMapping(newKey: 'tableName',              oldKey: 'ui.text.table.name'),
  KeyMapping(newKey: 'tableKind',              oldKey: 'ui.text.table.type'),
  KeyMapping(newKey: 'tableRarity',            oldKey: 'ui.text.table.rank'),
  KeyMapping(newKey: 'tableTotalIndex',        oldKey: 'ui.text.table.total_of_draws'),
  KeyMapping(newKey: 'tableFiveStarPity',      oldKey: 'ui.text.table.draws_count_in_win'),
  // tableFiveStarPityTooltip: 舊版無 tooltip 概念，不映射
  // sortDirection*: 舊版無 sort UI，不映射

  // ===== Progress / Pity / Timeline / Filter / Confirm / Empty / Error / Account =====
  // 這些都是新版才有的功能，舊版完全沒對應字串。
  // 全部不映射，靠 Flutter 自動 fallback 到 zh_Hant template。

  // ===== Page headers =====
  KeyMapping(newKey: 'pageOverviewTitle',  oldKey: 'ui.text.title.home'),
  // pageBannerRecordList: 舊版 "ui.text.title.history"（歷史紀錄）語意接近，
  //                       但「卡池紀錄列表」vs「歷史紀錄」不完全等價；保守不映射。

  // ===== Settings =====
  KeyMapping(newKey: 'settingsTitle',           oldKey: 'ui.text.settings'),
  // 注意：舊版可能無 "ui.text.settings" key（待 Claude 在實作前 grep 確認）。
  // 若無，改成不映射，fallback。
  KeyMapping(newKey: 'settingsLanguage',        oldKey: 'ui.text.language'),
  // settingsLocaleSystem 保留 hardcoded（Task 6 內也是「跟隨系統」這個概念，
  //   舊版若沒對應就 fallback）。
  // settingsAbout:        舊版 "ui.text.about"
  KeyMapping(newKey: 'settingsAbout', oldKey: 'ui.text.about'),
  // settingsAppearance / settingsTheme / settingsThemeSystem / settingsThemeDark / settingsThemeLight:
  //   舊版無，不映射
  // settingsLocaleZhHant / Hans / En: 這 3 個 key Task 6 會從 ARB 中移除；
  //   不映射也沒差。
  // settingsDataManagement / settingsAccountManagement: 舊版無，不映射
  // settingsExport*/Import*: 舊版有 "ui.text.export_excel" 但不夠對應，不映射
  // settingsClear*: 舊版無，不映射
  // settingsAboutVersion:
  KeyMapping(
    newKey: 'settingsAboutVersion',
    oldKey: 'ui.text.update.title',  // "有新版本可以更新！ ({version})"
    placeholders: {'version': 'version'},
  ),
  // (注意上面這個映射不完美——舊 key 是更新提示文案。實作前 Claude 可選擇不映射、
  //  讓 fallback 顯示繁中「版本 {version}」。請在 Review 階段討論。)

  // 上面為 starter 範例。執行者依 Step 4.1 procedure 繼續走過 zh_Hant.arb
  // 內所有 key（progress*, pity*, timeline*, filter*, confirm*, empty*,
  // error*, account*, uid*, settingsExport*, settingsImport* 等），逐一
  // 判斷是否在 zh_TW.json 內有語意對應。
  //
  // 預期最終 mapping 條目數約 20-40 條（新版 100+ key 內，大多數為新功能、
  // 在 zh_TW.json 無對應；保守起見只映射「明確 1:1」的字串，其餘靠 Flutter
  // 自動 fallback 到 app_zh_Hant.arb template）。
];
```

### Step 4.2: 撰寫「映射表 review notes」

- [ ] **在 `tool/i18n_port/key_mappings.dart` 檔尾以 `/* */` 多行註解附 review note**，列出有爭議的對應：

```dart
/*
========== Mapping Review Notes ==========

【保守決策（不映射、靠 fallback）】
- statsRarityDistribution / statsItemTypeDistribution:
    舊版 "chance_of_win_by_rank" 跟 "by_character_and_weapon" 語意接近但
    描述的是「中獎率」而非「分布」。不映射，新版顯示繁中。
- navStandard ("常駐"):
    舊版 "various_gacha"（各類卡池）涵蓋更廣，不映射。
- pageBannerRecordList ("紀錄列表"):
    舊版 "title.history"（歷史紀錄）語意接近但範圍不同。

【placeholder 重命名（已在 mapping 內標明）】
- footerLastUpdated{time} ← data_update_time{time}（剛好同名）
- settingsAboutVersion{version} ← update.title{version}（舊版字串含「有新版本可以更新！」
  前綴，不適合用作版本顯示。建議不映射，這條 mapping 待 user review 後再決定要不要保留）

【完全無對應（不映射）】
- 所有 progress* / pity* / timeline* / filter* / confirm* / empty* /
  error* / account* / uid* / kindUnknown / gachaType* 等新版獨有 key
- statsShareOfTotal / sortDirection* / tableFiveStarPityTooltip

【舊版有翻譯但新版用不到（直接丟）】
- ui.text.title.web_signin / teyvat_interactive_map / contribution_list
- ui.text.lightbox.*
- ui.text.table.data_table.*（length_menu / zero_records / search 等 DataTable 細項）
- ui.text.loading.wait_proxy_get_gacha_history_url
- ui.text.draws_info.*
- ui.text.update.download / release
- ui.text.donate_*
- ui.text.help_translate*
*/
```

### Step 4.3: User checkpoint — review key_mappings

- [ ] **Claude 完成 `key_mappings.dart` 後，停下來告訴 user**：

> 「映射表草稿寫在 `tool/i18n_port/key_mappings.dart`，共 ~XX 條 mapping。
> 主要的判斷在檔尾的 Review Notes 段落，特別是：
> 1. `settingsAboutVersion` 是否該映射到舊版的 `update.title`（含「有新版本可更新」前綴）
> 2. 是否該保守對「stats 分布類」key 不映射
>
> 請 review 後告訴我要不要動。OK 就跑 Task 5。」

- [ ] **等 user 回應後**才進 Task 5。若 user 提出修改，先改 `key_mappings.dart` 再跑 Task 5。

**Checkpoint**：本 Task 不 commit。`git status` 仍應 clean。

---

## Task 5: 跑腳本 + commit ARB 結果

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`（加 metadata key）
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_en.arb`
- Create: `lib/l10n/app_<27 個>.arb`（腳本生成）
- Modify: `lib/l10n/generated/app_localizations.dart`（gen_l10n 重新產出）
- Modify: `lib/l10n/generated/app_localizations_zh.dart`
- Modify: `lib/l10n/generated/app_localizations_en.dart`
- Create / Modify: `lib/l10n/generated/app_localizations_<lang>.dart` × 28 (28 unique language codes)

### Step 5.1: 替既有 3 個 ARB 加 metadata key

- [ ] **改 `lib/l10n/app_zh_Hant.arb`**：在 `"appName": "原神祈願卡池分析",` 上方插入：

```json
  "localeNativeName": "繁體中文",
  "localeTranslator": "",

  "@localeNativeName": {
    "description": "Native name of this locale, shown in language picker."
  },
  "@localeTranslator": {
    "description": "Comma-separated list of translators for this locale. Empty = original language (no credit row shown)."
  },

```

（注意：`@localeNativeName` / `@localeTranslator` 只放 template ARB，其他 ARB 不放 metadata。）

- [ ] **改 `lib/l10n/app_zh_Hans.arb`**：在 `"appName": ...` 上方插入：

```json
  "localeNativeName": "简体中文",
  "localeTranslator": "",

```

- [ ] **改 `lib/l10n/app_en.arb`**：先讀 `master:src/locales/en_US.json` 取出 `lang.translator` 的值（範例：`"Zanah_68, pan93412, Lemon7777"`），然後在 `"appName": ...` 上方插入：

```json
  "localeNativeName": "English",
  "localeTranslator": "<從 master en_US.json 的 lang.translator 抓>",

```

> **執行注意**：抓 translator 名單用 `git show master:src/locales/en_US.json` 然後 jq 或人工找 `lang.translator` 欄位。

### Step 5.2: 跑腳本生成 27 個新 ARB

- [ ] **dry run 先看**：

```bash
dart run tool/i18n_port/port.dart --dry-run --only=ja,pt_BR
```

Expected: stdout 印出 `→ Processing ja_JP → app_ja.arb` 跟 `(dry-run) would write NN keys to lib/l10n/app_ja.arb`，沒有 stderr。

- [ ] **全部跑**（不含 dry-run）：

```bash
dart run tool/i18n_port/port.dart
```

Expected: 27 個 `app_<arbSuffix>.arb` 寫入 `lib/l10n/`。stdout 印 `Done. Now run: flutter gen-l10n`。

> 注意：腳本對 en_US / zh_CN / zh_TW 三個既有 entry 也會跑（因為 `locale_mappings.dart` 也列了它們），這會**覆寫**已有的 `app_en.arb` / `app_zh_Hans.arb` / `app_zh_Hant.arb`。**這不是我們想要的**——這三個檔在 Step 5.1 已手動加好 metadata，且內容由 GoneTone 親自精修。
>
> 解法：跑全集前先 `--only` 排除這三個。改用：
>
> ```bash
> dart run tool/i18n_port/port.dart --only=af,ar,ca,cs,da,de,el,es,fi,fr,he,hu,it,ja,ko,nl,no,pl,pt_BR,pt_PT,ro,ru,sv,th,tr,uk,vi
> ```

- [ ] **手動 spot check 3 個輸出**：

```bash
head -10 lib/l10n/app_ja.arb
head -10 lib/l10n/app_pt_BR.arb
head -10 lib/l10n/app_de.arb
```

Expected：每個檔頭應該是 `@@locale` + `localeNativeName` + `localeTranslator` + 翻譯字串。

### Step 5.3: 跑 `flutter gen-l10n` 重新產出 Dart code

- [ ] **執行**：

```bash
flutter gen-l10n
```

Expected: 重新產出 `lib/l10n/generated/app_localizations.dart` + `app_localizations_<lang>.dart` × 28（en, zh, af, ar, ca, cs, da, de, el, es, fi, fr, he, hu, it, ja, ko, nl, no, pl, pt, ro, ru, sv, th, tr, uk, vi 共 28 個 unique 語言代碼；zh 含 Hant/Hans、pt 含 BR/PT 各共用一檔）。

可能印 warning：「Locale 'xx' missing key 'progressFetchingBanner', falling back to template」之類——**這是預期的**。

- [ ] **如果 gen_l10n 失敗**（例如某個 ARB 內有 placeholder 字串但 placeholder 名跟 template 不一致），修 `tool/i18n_port/key_mappings.dart` 內 placeholder 重命名規則，然後 Step 5.2 重跑 → Step 5.3 重跑。

### Step 5.4: 跑全套驗證

- [ ] **執行：`dart format lib/ test/`**
- [ ] **執行：`flutter analyze`** → Expected: `No issues found!`
- [ ] **執行：`flutter test`** → Expected: `All tests passed!`

### Step 5.5: Commit

- [ ] **執行**：

```bash
git add lib/l10n/
git commit -m "$(cat <<'EOF'
feat(i18n): import master translations and add locale metadata

從 master 分支 src/locales 匯入 27 個新語言翻譯（pt 拆 BR/PT；sr 因
源檔為空 {} 跳過；en/zh_Hant/zh_Hans 已存在不重生）。每個 ARB 新增
localeNativeName 與 localeTranslator 兩個 metadata key，作為動態語言
選單與翻譯者署名的資料來源。

既有 zh_Hant/zh_Hans/en 三個 ARB 同步補上 metadata 並維持原內容；
新增的 27 語靠 Flutter gen_l10n 自動 fallback 到 app_zh_Hant.arb
template 處理缺 key 的情況（progress* / pity* / timeline* / account*
等新版獨有字串）。

新→舊 key 映射表由本地 tool/i18n_port/key_mappings.dart 驅動，使用後
依 .gitignore 規則自動排除。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: 動態語言選單 + 移除 hardcoded settings key

**Files:**
- Create: `lib/state/localization_metadata.dart`
- Modify: `lib/pages/settings_page.dart` (`_LocaleDropdown` 段落)
- Modify: `lib/l10n/app_zh_Hant.arb`（移除 3 個 `settingsLocaleZhHant` / `Hans` / `En`）
- Modify: `lib/l10n/app_zh_Hans.arb`（同）
- Modify: `lib/l10n/app_en.arb`（同）
- Modify: `lib/l10n/generated/app_localizations.dart`（gen_l10n 重產）
- Modify: `lib/l10n/generated/app_localizations_zh.dart`
- Modify: `lib/l10n/generated/app_localizations_en.dart`
- Create: `test/l10n/locale_metadata_test.dart`

### Step 6.1: 寫 metadata test（先 fail）

- [ ] **新建 `test/l10n/locale_metadata_test.dart`**：

```dart
// test/l10n/locale_metadata_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

void main() {
  group('AppLocalizations locale metadata', () {
    test('每個 supported locale 都能 load', () async {
      for (final locale in AppLocalizations.supportedLocales) {
        final l = await AppLocalizations.delegate.load(locale);
        expect(
          l.localeNativeName,
          isNotEmpty,
          reason: '${locale.toLanguageTag()} 的 localeNativeName 不能為空',
        );
      }
    });

    test('zh_Hant / zh_Hans 的 localeTranslator 為空字串', () async {
      final hant = await AppLocalizations.delegate.load(
        const Locale('zh', 'Hant'),
      );
      expect(hant.localeTranslator, isEmpty);

      final hans = await AppLocalizations.delegate.load(
        const Locale('zh', 'Hans'),
      );
      expect(hans.localeTranslator, isEmpty);
    });

    test('日文 localeNativeName = "日本語"', () async {
      final ja = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(ja.localeNativeName, '日本語');
    });

    test('巴西葡萄牙文 localeNativeName 含 "Brasil" 或 "Portugu"', () async {
      final pt = await AppLocalizations.delegate.load(
        const Locale('pt', 'BR'),
      );
      expect(
        pt.localeNativeName.toLowerCase(),
        anyOf(contains('brasil'), contains('portugu')),
        reason: 'pt-BR localeNativeName 看起來不像葡萄牙文',
      );
    });

    test('supportedLocales 包含 zh_Hant / zh_Hans / en / ja / pt_BR / pt_PT', () {
      final tags = AppLocalizations.supportedLocales
          .map((l) => l.toLanguageTag())
          .toSet();
      expect(tags, contains('zh-Hant'));
      expect(tags, contains('zh-Hans'));
      expect(tags, contains('en'));
      expect(tags, contains('ja'));
      expect(tags, contains('pt-BR'));
      expect(tags, contains('pt-PT'));
    });
  });
}
```

- [ ] **執行：`flutter test test/l10n/locale_metadata_test.dart`** → Expected: **PASS**（因為 Task 5 已經寫好 metadata；test 是為了 lock 行為）。

### Step 6.2: 新增 `lib/state/localization_metadata.dart`

- [ ] **新建檔案**：

```dart
// lib/state/localization_metadata.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

@immutable
class LocaleMetadata {
  const LocaleMetadata({required this.nativeName, required this.translator});

  /// 該 locale 的母語名稱，例如 "日本語"、"Português (Brasil)"。
  final String nativeName;

  /// 該 locale 的翻譯者署名（逗號分隔），原始語言為空字串。
  final String translator;
}

/// 一次性 load 所有 [AppLocalizations.supportedLocales] 的 metadata；
/// Settings 語言選單與 About 區塊讀此 provider。
///
/// `delegate.load` 對 gen_l10n 編譯後的 const 內容回傳 [SynchronousFuture]，
/// 所以 FutureProvider 幾乎沒有等待時間（同 microtask 內完成）。
final localeMetadataProvider = FutureProvider<Map<String, LocaleMetadata>>(
  (ref) async {
    final result = <String, LocaleMetadata>{};
    for (final locale in AppLocalizations.supportedLocales) {
      final l = await AppLocalizations.delegate.load(locale);
      result[locale.toLanguageTag()] = LocaleMetadata(
        nativeName: l.localeNativeName,
        translator: l.localeTranslator,
      );
    }
    return result;
  },
);
```

### Step 6.3: 改 `lib/pages/settings_page.dart` `_LocaleDropdown` 為動態

- [ ] **取代 `_LocaleDropdown` 整個 class**（替 Task 1.6 寫的版本）：

```dart
class _LocaleDropdown extends ConsumerWidget {
  const _LocaleDropdown({
    required this.current,
    required this.onChanged,
    required this.l,
  });
  final LanguagePreference current;
  final ValueChanged<LanguagePreference> onChanged;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncMeta = ref.watch(localeMetadataProvider);
    return asyncMeta.when(
      data: (metadata) {
        final sorted = metadata.entries.toList()
          ..sort((a, b) => a.value.nativeName.compareTo(b.value.nativeName));
        return DropdownButtonFormField<LanguagePreference>(
          initialValue: current,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: [
            DropdownMenuItem(
              value: const SystemLanguage(),
              child: Text(l.settingsLocaleSystem),
            ),
            for (final entry in sorted)
              DropdownMenuItem(
                value: LocaleLanguage(entry.key),
                child: Text(entry.value.nativeName),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        );
      },
      loading: () => const SizedBox(
        height: 56,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Text('Failed to load locale metadata: $e'),
    );
  }
}
```

- [ ] **檔頂 import 加上**：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';
```

### Step 6.4: 從既有 3 ARB 移除 `settingsLocaleZhHant` / `Hans` / `En`

- [ ] **改 `lib/l10n/app_zh_Hant.arb`**：刪除這三行：

```json
  "settingsLocaleZhHant": "繁體中文",
  "settingsLocaleZhHans": "简体中文",
  "settingsLocaleEn": "English",
```

`settingsLocaleSystem` 保留。

- [ ] **改 `lib/l10n/app_zh_Hans.arb`**：刪除同三個 key 行。

- [ ] **改 `lib/l10n/app_en.arb`**：刪除同三個 key 行。

### Step 6.5: 跑 gen_l10n 與全套驗證

- [ ] **執行：`flutter gen-l10n`**
- [ ] **執行：`dart format lib/ test/`**
- [ ] **執行：`flutter analyze`** → Expected: `No issues found!`
- [ ] **執行：`flutter test`** → Expected: `All tests passed!`

### Step 6.6: Commit

- [ ] **執行**：

```bash
git add lib/l10n/ \
        lib/pages/settings_page.dart \
        lib/state/localization_metadata.dart \
        test/l10n/locale_metadata_test.dart
git commit -m "$(cat <<'EOF'
feat(settings): dynamic language picker with native names

Settings 語言選單從 hardcoded 4 項擴成 system + 30 種語言（依 ARB 自帶的
localeNativeName 排序）。新增 localeMetadataProvider 一次性 load 所有
supported locale 的 metadata，由 gen_l10n 編譯後的 const 提供，無 I/O cost。

移除 zh_Hant / zh_Hans / en 三個 ARB 內 settingsLocaleZhHant / Hans / En
三個過時 key，這些已被 localeNativeName 取代。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: About 區塊顯示翻譯者署名

**Files:**
- Modify: `lib/pages/settings_page.dart`（`_AboutContent` 段落，line 152-159）

### Step 7.1: 改 `_AboutContent`

- [ ] **取代 `_AboutContent` 整個 class**：

```dart
class _AboutContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final version = ref.watch(appVersionProvider);
    final translator = l.localeTranslator;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.settingsAboutVersion(version)),
        if (translator.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Icon(
                Icons.translate,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  translator,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
```

### Step 7.2: 跑全套驗證

- [ ] **執行：`dart format lib/ test/`**
- [ ] **執行：`flutter analyze`** → Expected: `No issues found!`
- [ ] **執行：`flutter test`** → Expected: `All tests passed!`

### Step 7.3: 手動驗證（UI 測試）

- [ ] **執行：`flutter run -d windows`**（或當前 dev platform）

- [ ] **打開 app → Settings → About**：

  - 預設 (system → zh_Hant)：只看到「版本 1.0.0+1」，**沒有**翻譯者 row（因為 zh_Hant 的 `localeTranslator` 為空字串）。
  - 切到日文：「版本 1.0.0+1」+ 一行 `🌐 Akashi (天月), Stardrop`（或舊版實際填的譯者）。
  - 切到 zh_Hans：只有版本，無譯者 row（zh_Hans `localeTranslator` 也空）。
  - 切到 en：版本 + 譯者 row（en 從舊 en_US.json 的 lang.translator 帶入）。

- [ ] **手動切 5 個不同語言**驗證 dropdown 顯示母語名稱、切換後 UI 立即更新、About 譯者 row 行為符合上述。

### Step 7.4: Commit

- [ ] **執行**：

```bash
git add lib/pages/settings_page.dart
git commit -m "$(cat <<'EOF'
feat(about): show locale translator credit

About 區塊新增一行翻譯者署名：Icon(Icons.translate) + localeTranslator。
原始語言（zh_Hant / zh_Hans）localeTranslator 為空字串時整 row 不顯示。
不引入 "Translator:" 標籤字串避免跨 27 個新增語沒翻譯的 fallback 困擾，icon
普世表達語意。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Step 7.5: 收尾 — 移除本地 tool/i18n_port/

- [ ] **執行**：

```bash
rm -rf tool/i18n_port/
git status
```

Expected: working tree clean（`tool/i18n_port/` 在 `.gitignore` 內，移除不會影響任何 tracked 檔）。

---

## Final Verification Checklist

實作全部完成後，做以下端到端檢查：

- [ ] `git log --oneline -7` 應看到 5 個新 commit：
  ```
  feat(about): show locale translator credit
  feat(settings): dynamic language picker with native names
  feat(i18n): import master translations and add locale metadata
  chore(tool): ignore i18n port working dir
  feat(i18n): refactor AppLocale to LanguagePreference sealed class
  ```
- [ ] `flutter analyze` 印 `No issues found!`
- [ ] `flutter test` 印 `All tests passed!`
- [ ] `dart format --output=none --set-exit-if-changed lib/ test/` exit 0
- [ ] `ls lib/l10n/*.arb | wc -l` → 30（en + zh_Hant + zh_Hans + 27 新增）
- [ ] `ls lib/l10n/generated/app_localizations_*.dart | wc -l` → 28（28 unique 語言代碼）
- [ ] `git ls-files tool/` → 空（tool/i18n_port 在 ignore 內）
- [ ] Settings 語言選單在 zh_Hant 介面下：第一項「跟隨系統」，其後依母語名稱字母順序排列 30 個 locale（如 `Català`, `Dansk`, `Deutsch`, `English`, ..., `Tiếng Việt`, `Türkçe`, `Українська`, ...）。
