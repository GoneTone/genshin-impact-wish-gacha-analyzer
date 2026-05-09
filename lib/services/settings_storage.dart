// lib/services/settings_storage.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, dark, light }

enum AppLocale { system, zhHant, zhHans, en }

@immutable
class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.locale,
  });

  final AppThemeMode themeMode;
  final AppLocale locale;

  static const defaults = AppSettings(
    themeMode: AppThemeMode.system,
    locale: AppLocale.system,
  );

  AppSettings copyWith({AppThemeMode? themeMode, AppLocale? locale}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
      );
}

abstract final class SettingsStorage {
  static const _kThemeMode = 'pref.themeMode';
  static const _kLocale = 'pref.locale';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      themeMode: _parseThemeMode(prefs.getString(_kThemeMode)),
      locale: _parseLocale(prefs.getString(_kLocale)),
    );
  }

  static Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, _themeModeToString(s.themeMode));
    await prefs.setString(_kLocale, _localeToString(s.locale));
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
}
