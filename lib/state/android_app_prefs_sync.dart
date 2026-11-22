import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/app_prefs_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

/// 把 App 內的主題與語言和 Android 系統設定同步（只在 Android 上啟動）。
///
/// - 主題：App → 系統單向（系統只拿來畫啟動畫面）。
/// - 語言：雙向。系統設定「應用程式語言」改了 App 跟著改，App 內改了也寫回系統。
///   開機時系統端有值就以系統為準（App 關著時可能在系統設定改過）；系統端是「預設」時，
///   只有第一次（[migratedKey] 尚未記錄）才把 App 內既有的選擇推給系統，之後一律代表
///   「跟隨系統」，免得把使用者在系統設定改回預設的動作蓋掉。
class AndroidAppPrefsSync with WidgetsBindingObserver {
  /// 建立 [AndroidAppPrefsSync]。
  AndroidAppPrefsSync(this._ref);

  /// SharedPreferences key：是否已把 App 內語言遷移到系統端。
  static const migratedKey = 'pref.localeSyncedToSystem';

  /// 讀寫設定用的 Riverpod ref。
  final Ref _ref;

  /// 本類別的 logger。
  static final _log = Logger('app.prefs');

  /// 系統支援 App 語言（Android 13 以上）時才為 true，[start] 時判定。
  bool _localeSupported = false;

  /// 是否已加入 [WidgetsBinding] 觀察者。
  bool _observing = false;

  /// 等設定載入後開始同步；載入前不送，免得先把預設值（跟隨系統）推給系統。
  Future<void> start() async {
    final notifier = _ref.read(settingsProvider.notifier);
    await notifier.waitForLoad();
    if (!_ref.mounted) return;

    _ref.listen(
      settingsProvider.select((s) => s.themeMode),
      (_, mode) => unawaited(AppPrefsPlatform.setNightMode(mode)),
      fireImmediately: true,
    );

    final systemTag = await AppPrefsPlatform.getLocale();
    if (systemTag == null || !_ref.mounted) return;
    _localeSupported = true;
    await _reconcileStartup(systemTag);
    if (!_ref.mounted) return;

    _ref.listen(
      settingsProvider.select((s) => s.locale),
      (_, pref) => unawaited(_pushLocale(pref)),
    );
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  /// 開機時對齊兩端語言；規則見類別說明。
  Future<void> _reconcileStartup(String systemTag) async {
    final prefs = await SharedPreferences.getInstance();
    final migrated = prefs.getBool(migratedKey) ?? false;
    final current = _ref.read(settingsProvider).locale;
    if (systemTag.isEmpty && !migrated && current is LocaleLanguage) {
      _log.info('app locale migrated to system code=${current.code}');
      await _pushLocale(current);
    } else {
      await _adoptSystemTag(systemTag);
    }
    await prefs.setBool(migratedKey, true);
  }

  /// 系統端語言變了（含系統設定與本身推送造成的設定變更）：讀回並更新 App 內設定。
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (!_localeSupported) return;
    unawaited(() async {
      final systemTag = await AppPrefsPlatform.getLocale();
      if (systemTag == null || !_ref.mounted) return;
      await _adoptSystemTag(systemTag);
    }());
  }

  /// 把系統端標籤套成 App 內語言；相同或對不到 App 開放的語言時不動。
  Future<void> _adoptSystemTag(String systemTag) async {
    final pref = languagePreferenceOfSystemTag(
      systemTag,
      _ref.read(releasedLocalesProvider),
    );
    if (pref == null) {
      _log.warning('app locale from system not offered tag=$systemTag');
      return;
    }
    if (pref == _ref.read(settingsProvider).locale) return;
    _log.info('app locale adopted from system tag=$systemTag pref=$pref');
    await _ref.read(settingsProvider.notifier).setLocale(pref);
  }

  /// 把 App 內語言 [pref] 寫回系統；系統端已是同一個語言時不送，避免來回觸發設定變更。
  Future<void> _pushLocale(LanguagePreference pref) async {
    final systemTag = await AppPrefsPlatform.getLocale();
    if (systemTag == null) return;
    final systemPref = languagePreferenceOfSystemTag(
      systemTag,
      _ref.read(releasedLocalesProvider),
    );
    if (systemPref == pref) return;
    await AppPrefsPlatform.setLocale(systemLocaleTagOf(pref));
  }

  /// 移除 [WidgetsBinding] 觀察者。
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
  }
}

/// [AndroidAppPrefsSync] 的單例；由 `MainApp` 在 Android 上呼叫 [AndroidAppPrefsSync.start]。
final androidAppPrefsSyncProvider = Provider<AndroidAppPrefsSync>((ref) {
  final sync = AndroidAppPrefsSync(ref);
  ref.onDispose(sync.dispose);
  return sync;
});
