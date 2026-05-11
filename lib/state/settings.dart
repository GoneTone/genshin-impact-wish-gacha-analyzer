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
///
/// 第二段若是 4 字元（BCP-47 script code 慣例，如 `Hant` / `Hans` / `Latn`）
/// 走 [Locale.fromSubtags] 設 `scriptCode`；否則當 region code 用一般建構式。
/// 這對應 Flutter `gen_l10n` 對 `app_zh_Hant.arb` / `app_zh_Hans.arb` 等
/// 檔名解析的方式——用 `Locale('zh', 'Hant')` 會把 `Hant` 放進 `countryCode`，
/// 跟 supportedLocales 內以 `scriptCode='Hant'` 註冊的 entry 不相等，導致
/// Flutter resolver fallback 到 template 並顯示錯誤語言。
Locale _localeFromCode(String code) {
  final parts = code.split('-');
  if (parts.length == 1) return Locale(parts[0]);
  if (parts[1].length == 4) {
    return Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]);
  }
  return Locale(parts[0], parts[1]);
}
