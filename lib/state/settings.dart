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

  /// 給 test 用：等首次 load 完。
  @visibleForTesting
  Future<void> waitForLoad() => _loadFuture;

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await SettingsStorage.save(state);
  }

  Future<void> setLocale(AppLocale locale) async {
    state = state.copyWith(locale: locale);
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
