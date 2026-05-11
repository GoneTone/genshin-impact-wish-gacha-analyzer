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
