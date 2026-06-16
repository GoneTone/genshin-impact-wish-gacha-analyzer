import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 應用程式的外觀主題設定。
enum AppThemeMode {
  /// 跟隨系統明暗模式。
  system,

  /// 強制深色模式。
  dark,

  /// 強制淺色模式。
  light,
}

/// 使用者偏好的語言：跟隨系統（[SystemLanguage]）或指定 BCP-47 locale
/// （[LocaleLanguage]，例如 "zh-Hans"、"pt-BR"、"ja"）。
sealed class LanguagePreference {
  const LanguagePreference();

  /// 從 [toCode] 序列化字串還原偏好設定。
  factory LanguagePreference.fromCode(String code) =>
      code == 'system' ? const SystemLanguage() : LocaleLanguage(code);

  /// 序列化字串（給 SharedPreferences 用），可被 [fromCode] 還原。
  String toCode();
}

/// 跟隨系統語言。
class SystemLanguage extends LanguagePreference {
  /// 建立 [SystemLanguage]。
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

/// 指定 BCP-47 locale 的語言偏好。
class LocaleLanguage extends LanguagePreference {
  /// 建立 [LocaleLanguage]，需提供 BCP-47 [code]。
  const LocaleLanguage(this.code);

  /// BCP-47 code，例如 "zh-Hans"、"pt-BR"、"ja"。
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

/// 應用程式全域使用者偏好設定的快照。
@immutable
class AppSettings {
  /// 建立 [AppSettings]。
  const AppSettings({
    required this.themeMode,
    required this.locale,
    this.lastActiveUid,
    this.uidAliases = const {},
    this.uidOrder = const [],
    this.skippedReleaseTag,
    this.maskUidInUi = false,
    this.dataLanguage,
    this.dataLanguageSeeded = false,
  });

  /// 外觀主題。
  final AppThemeMode themeMode;

  /// 語言偏好。
  final LanguagePreference locale;

  /// 最近一次使用的 UID。
  final String? lastActiveUid;

  /// UID 別名對應，key = uid。
  final Map<String, String> uidAliases;

  /// 使用者自訂的 UID 顯示順序。
  final List<String> uidOrder;

  /// 使用者選擇跳過的 release tag（已讀過不再提示）。
  final String? skippedReleaseTag;

  /// 是否在介面中遮蔽 UID（前 3 碼搭配 `•`）；資料檔與刪除確認框不受影響。
  final bool maskUidInUi;

  /// 資料語言代碼（如 `ja-jp`）；null 代表未設定（停用轉換）。獨立於 App UI 語言。
  final String? dataLanguage;

  /// 資料語言是否已初始化（自動播種或使用者明確選擇過）。false 代表可被自動播種。
  final bool dataLanguageSeeded;

  /// 預設設定值（跟隨系統主題與語言）。
  static const defaults = AppSettings(
    themeMode: AppThemeMode.system,
    locale: SystemLanguage(),
  );

  /// 回傳以指定欄位覆寫的新 [AppSettings]；
  /// 傳 `clearLastActiveUid: true` 或 `clearSkippedReleaseTag: true` 可將對應欄位清為 null。
  AppSettings copyWith({
    AppThemeMode? themeMode,
    LanguagePreference? locale,
    String? lastActiveUid,
    bool clearLastActiveUid = false,
    Map<String, String>? uidAliases,
    List<String>? uidOrder,
    String? skippedReleaseTag,
    bool clearSkippedReleaseTag = false,
    bool? maskUidInUi,
    String? dataLanguage,
    bool clearDataLanguage = false,
    bool? dataLanguageSeeded,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
    lastActiveUid: clearLastActiveUid
        ? null
        : (lastActiveUid ?? this.lastActiveUid),
    uidAliases: uidAliases ?? this.uidAliases,
    uidOrder: uidOrder ?? this.uidOrder,
    skippedReleaseTag: clearSkippedReleaseTag
        ? null
        : (skippedReleaseTag ?? this.skippedReleaseTag),
    maskUidInUi: maskUidInUi ?? this.maskUidInUi,
    dataLanguage: clearDataLanguage ? null : (dataLanguage ?? this.dataLanguage),
    dataLanguageSeeded: dataLanguageSeeded ?? this.dataLanguageSeeded,
  );
}

/// [AppSettings] 的 SharedPreferences 讀寫工具類別。
abstract final class SettingsStorage {
  /// Logger 實例（設定存取）。
  static final _log = Logger('settings');

  /// SharedPreferences key：外觀主題。
  static const _kThemeMode = 'pref.themeMode';

  /// SharedPreferences key：語言偏好。
  static const _kLocale = 'pref.locale';

  /// SharedPreferences key：最近使用 UID。
  static const _kLastActiveUid = 'pref.lastActiveUid';

  /// SharedPreferences key：UID 別名 JSON。
  static const _kUidAliases = 'pref.uidAliases';

  /// SharedPreferences key：UID 排序 JSON。
  static const _kUidOrder = 'pref.uidOrder';

  /// SharedPreferences key：使用者跳過的 release tag。
  static const _kSkippedReleaseTag = 'pref.skippedReleaseTag';

  /// SharedPreferences key：是否在介面中遮蔽 UID。
  static const _kMaskUidInUi = 'pref.maskUidInUi';

  /// SharedPreferences key：資料語言（語言碼／`"none"`／不存在 三態）。
  static const _kDataLanguage = 'pref.dataLanguage';

  /// 從 SharedPreferences 讀取設定，欄位缺漏時回退到預設值。
  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final dataLangRaw = prefs.getString(_kDataLanguage);
    return AppSettings(
      themeMode: _parseThemeMode(prefs.getString(_kThemeMode)),
      locale: _parseLocale(prefs.getString(_kLocale)),
      lastActiveUid: prefs.getString(_kLastActiveUid),
      uidAliases: _parseAliases(prefs.getString(_kUidAliases)),
      uidOrder: _parseOrder(prefs.getString(_kUidOrder)),
      skippedReleaseTag: prefs.getString(_kSkippedReleaseTag),
      maskUidInUi: prefs.getBool(_kMaskUidInUi) ?? false,
      dataLanguage: dataLangRaw == null || dataLangRaw == 'none' ? null : dataLangRaw,
      dataLanguageSeeded: dataLangRaw != null,
    );
  }

  /// 將 [s] 持久化到 SharedPreferences。
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
    if (s.skippedReleaseTag == null) {
      await prefs.remove(_kSkippedReleaseTag);
    } else {
      await prefs.setString(_kSkippedReleaseTag, s.skippedReleaseTag!);
    }
    await prefs.setBool(_kMaskUidInUi, s.maskUidInUi);
    if (!s.dataLanguageSeeded) {
      await prefs.remove(_kDataLanguage);
    } else {
      await prefs.setString(_kDataLanguage, s.dataLanguage ?? 'none');
    }
  }

  /// 解析主題設定字串，未知值回退到 [AppThemeMode.system]。
  static AppThemeMode _parseThemeMode(String? raw) => switch (raw) {
    'dark' => AppThemeMode.dark,
    'light' => AppThemeMode.light,
    _ => AppThemeMode.system,
  };

  /// 序列化主題設定為字串。
  static String _themeModeToString(AppThemeMode m) => switch (m) {
    AppThemeMode.dark => 'dark',
    AppThemeMode.light => 'light',
    AppThemeMode.system => 'system',
  };

  /// 解析語言偏好字串，空值或 null 回退到 [SystemLanguage]。
  static LanguagePreference _parseLocale(String? raw) =>
      (raw == null || raw.isEmpty)
      ? const SystemLanguage()
      : LanguagePreference.fromCode(raw);

  /// 解析 UID 別名 JSON，格式錯誤時 log 警告並回傳空 map。
  static Map<String, String> _parseAliases(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (e, st) {
      _log.warning('uidAliases corrupt, resetting to empty', e, st);
      return const {};
    }
  }

  /// 解析 UID 排序 JSON，格式錯誤時 log 警告並回傳空列表。
  static List<String> _parseOrder(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => e.toString()).toList(growable: false);
    } catch (e, st) {
      _log.warning('uidOrder corrupt, resetting to empty', e, st);
      return const [];
    }
  }
}
