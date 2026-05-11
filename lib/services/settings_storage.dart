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
