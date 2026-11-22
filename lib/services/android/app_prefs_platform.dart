import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';

/// App 內設定與 Android 系統設定的橋接（Kotlin `AppPrefsChannel`）。
///
/// - 主題：啟動畫面由系統在 App 執行前畫，讀不到 App 設定；Android 12 起用
///   `UiModeManager.setApplicationNightMode` 告訴系統，下次畫啟動畫面時套用。
/// - 語言：Android 13 起系統設定有「應用程式語言」，用 `LocaleManager` 讀寫，與 App 內
///   「語言」雙向同步。
///
/// 所有方法遇到平台錯誤或不支援都只記 warning，不往外丟。
class AppPrefsPlatform {
  /// 與 Kotlin 端約定的 channel 名稱。
  static const channelName = 'tw.reh.genshin.gacha/app_prefs';

  /// 平台 channel。
  static const _channel = MethodChannel(channelName);

  /// 本包裝的 logger。
  static final _log = Logger('app.prefs');

  /// 呼叫 [method]，失敗時記 warning 並回 null。
  static Future<T?> _call<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      _log.warning(
        '$method failed args=$args code=${e.code} message=${e.message}',
      );
    } on MissingPluginException {
      _log.warning('$method unavailable: no platform implementation');
    }
    return null;
  }

  /// 把主題 [mode] 告訴系統（Android 11 以下 Kotlin 端略過）。
  static Future<void> setNightMode(AppThemeMode mode) async {
    final applied = await _call<bool>('setNightMode', {'mode': mode.name});
    _log.info('night mode synced mode=${mode.name} applied=$applied');
  }

  /// 系統端的 App 語言標籤；空字串代表「系統預設」，null 代表不支援（Android 12 以下）或失敗。
  static Future<String?> getLocale() => _call<String>('getLocale', const {});

  /// 設定系統端的 App 語言；空字串代表回到「系統預設」。
  static Future<void> setLocale(String tag) async {
    final applied = await _call<bool>('setLocale', {'tag': tag});
    _log.info('app locale pushed tag=$tag applied=$applied');
  }
}

/// App 內語言偏好在系統端的標籤；「跟隨系統」為空字串。
///
/// 繁中在 App 內是不帶字集的 `zh`（ARB 範本），送給系統要寫成 `zh-Hant`，系統清單才會標成
/// 繁體、也才對得上 `locales_config.xml` 的項目。
String systemLocaleTagOf(LanguagePreference pref) => switch (pref) {
  SystemLanguage() => '',
  LocaleLanguage(:final code) => code == 'zh' ? 'zh-Hant' : code,
};

/// 系統端標籤 [tag] 對應的 App 內語言偏好；空字串為「跟隨系統」，[released] 裡沒有的語言回 null。
///
/// 中文的字集與地區對應沿用 [localeListResolution]（`zh-Hant-*`、`zh-TW` → 繁中），其餘交給
/// Flutter 預設比對。
LanguagePreference? languagePreferenceOfSystemTag(
  String tag,
  List<Locale> released,
) {
  if (tag.isEmpty) return const SystemLanguage();
  final requested = _localeOfTag(tag);
  final resolved =
      localeListResolution([requested], released) ??
      basicLocaleListResolution([requested], released);
  if (resolved.languageCode != requested.languageCode) return null;
  return LocaleLanguage(resolved.toLanguageTag());
}

/// 把 BCP-47 標籤（例如 `zh-Hant-TW`、`pt-BR`）拆成 [Locale]：4 字元為字集，其餘為地區。
Locale _localeOfTag(String tag) {
  final parts = tag.split(RegExp('[-_]'));
  String? script;
  String? country;
  for (final part in parts.skip(1)) {
    if (part.length == 4) {
      script ??= part;
    } else {
      country ??= part;
    }
  }
  return Locale.fromSubtags(
    languageCode: parts.first,
    scriptCode: script,
    countryCode: country,
  );
}
