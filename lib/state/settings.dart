import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/data_language.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';

/// App 設定的 Riverpod notifier，負責從磁碟讀寫 [AppSettings]。
class SettingsNotifier extends Notifier<AppSettings> {
  late Future<void> _loadFuture;

  @override
  AppSettings build() {
    _loadFuture = _load();
    return AppSettings.defaults;
  }

  /// 從磁碟載入設定並更新 state。
  Future<void> _load() async {
    final loaded = await SettingsStorage.load();
    if (!ref.mounted) return;
    state = loaded;
  }

  /// 等首次 `_load` 完成。
  ///
  /// `GachaRepository._bootstrapLoad` 會在讀 settings 前 await 此 future，
  /// 確保 `lastActiveUid` / `uidOrder` 等偏好已就緒；測試也用得到。
  Future<void> waitForLoad() => _loadFuture;

  /// 更新主題模式並持久化。
  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await SettingsStorage.save(state);
  }

  /// 更新語言偏好並持久化。
  Future<void> setLocale(LanguagePreference locale) async {
    state = state.copyWith(locale: locale);
    await SettingsStorage.save(state);
  }

  /// 設定資料語言並持久化；[code] 為 null 代表使用者明確選「未設定（不轉換）」。
  /// 任何呼叫都標記 `dataLanguageSeeded=true`，停止後續自動播種。
  Future<void> setDataLanguage(String? code) async {
    state = state.copyWith(
      dataLanguage: code,
      clearDataLanguage: code == null,
      dataLanguageSeeded: true,
    );
    await SettingsStorage.save(state);
    Logger('app.settings').info('dataLanguage set=${code ?? 'none'}');
  }

  /// 僅當尚未初始化（`!dataLanguageSeeded`）且 [code] 屬可選資料語言時，
  /// 以 [code] 自動播種並標記 seeded；否則 no-op（留待之後在有效語言下播種）。
  Future<void> seedDataLanguageIfUnset(String code) async {
    if (state.dataLanguageSeeded) return;
    if (!isSupportedDataLanguage(code)) return;
    state = state.copyWith(dataLanguage: code, dataLanguageSeeded: true);
    await SettingsStorage.save(state);
    Logger('app.settings').info('dataLanguage seeded=$code');
  }

  /// 更新最後作用中 UID 並持久化；[uid] 為 null 時清除。
  Future<void> setLastActiveUid(String? uid) async {
    state = state.copyWith(lastActiveUid: uid, clearLastActiveUid: uid == null);
    await SettingsStorage.save(state);
  }

  /// 設定指定 UID 的別名；[alias] 為 null 或空白時刪除別名。
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

  /// 更新 UID 排列順序並持久化。
  Future<void> setUidOrder(List<String> order) async {
    state = state.copyWith(uidOrder: List.unmodifiable(order));
    await SettingsStorage.save(state);
  }

  /// 設定跳過版本的 tag；[tag] 為 null 時清除。
  Future<void> setSkippedReleaseTag(String? tag) async {
    state = state.copyWith(
      skippedReleaseTag: tag,
      clearSkippedReleaseTag: tag == null,
    );
    await SettingsStorage.save(state);
  }

  /// 切換「遮蔽介面 UID」設定並持久化；變更值同步寫入 log。
  Future<void> setMaskUidInUi(bool value) async {
    state = state.copyWith(maskUidInUi: value);
    await SettingsStorage.save(state);
    Logger('app.settings').info('maskUidInUi toggled=$value');
  }

  /// 從 aliases 與 uidOrder 中移除指定 UID 並持久化。
  Future<void> removeUidFromSettings(String uid) async {
    final aliases = Map<String, String>.from(state.uidAliases)..remove(uid);
    final order = state.uidOrder.where((u) => u != uid).toList();
    state = state.copyWith(uidAliases: aliases, uidOrder: order);
    await SettingsStorage.save(state);
  }

  /// 清除所有 UID 相關偏好（aliases、uidOrder、lastActiveUid）並持久化。
  Future<void> clearAllUidPreferences() async {
    state = state.copyWith(
      clearLastActiveUid: true,
      uidAliases: const {},
      uidOrder: const [],
    );
    await SettingsStorage.save(state);
  }

  /// 一次性把匯入後的偏好寫入：aliases、uidOrder、lastActiveUid。
  /// 三個欄位合併寫入單次 [SettingsStorage.save]，避免中途失敗造成裂腦狀態。
  Future<void> applyImportedPreferences({
    required Map<String, String> aliases,
    required List<String> uidOrder,
    required String? lastActiveUid,
  }) async {
    state = state.copyWith(
      uidAliases: Map.unmodifiable(aliases),
      uidOrder: List.unmodifiable(uidOrder),
      lastActiveUid: lastActiveUid,
      clearLastActiveUid: lastActiveUid == null,
    );
    await SettingsStorage.save(state);
  }

  /// 記錄已連結的雲端帳號 email，並把自動同步重設為預設開啟。
  Future<void> setCloudAccount(String email) async {
    state = state.copyWith(
      cloudAccountEmail: email,
      cloudAutoSyncEnabled: true,
    );
    await SettingsStorage.save(state);
    Logger('cloudsync.auth').info('cloud account linked');
  }

  /// 清除雲端帳號連結（email、上次同步時間），autoSync 重設為 true。
  ///
  /// 待移除清單刻意**保留**：刪帳號的意圖在重新連結後仍應補刪。
  Future<void> clearCloudAccount() async {
    state = state.copyWith(
      clearCloudAccountEmail: true,
      clearCloudLastSyncedAt: true,
      cloudAutoSyncEnabled: true,
    );
    await SettingsStorage.save(state);
    Logger('cloudsync.auth').info('cloud account unlinked');
  }

  /// 切換自動雲端同步開關並持久化。
  Future<void> setCloudAutoSyncEnabled(bool value) async {
    state = state.copyWith(cloudAutoSyncEnabled: value);
    await SettingsStorage.save(state);
    Logger('cloudsync.sync').info('autoSync toggled=$value');
  }

  /// 記錄上次雲端同步成功時間並持久化。
  Future<void> setCloudLastSyncedAt(DateTime at) async {
    state = state.copyWith(cloudLastSyncedAt: at.toUtc());
    await SettingsStorage.save(state);
  }

  /// 把 [uid] 排入待雲端移除清單（去重）並持久化。
  Future<void> addCloudPendingRemoval(String uid) async {
    if (state.cloudPendingRemovals.contains(uid)) return;
    state = state.copyWith(
      cloudPendingRemovals: List.unmodifiable([
        ...state.cloudPendingRemovals,
        uid,
      ]),
    );
    await SettingsStorage.save(state);
  }

  /// 從待雲端移除清單移除 [uids]（同步成功後呼叫）並持久化。
  Future<void> removeCloudPendingRemovals(List<String> uids) async {
    if (uids.isEmpty) return;
    final remove = uids.toSet();
    state = state.copyWith(
      cloudPendingRemovals: List.unmodifiable(
        state.cloudPendingRemovals.where((u) => !remove.contains(u)),
      ),
    );
    await SettingsStorage.save(state);
  }
}

/// [SettingsNotifier] 的 Riverpod provider。
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

/// 當前資料語言代碼（null = 未設定／停用轉換）。
final dataLanguageProvider = Provider<String?>(
  (ref) => ref.watch(settingsProvider.select((s) => s.dataLanguage)),
);

/// 給 MaterialApp 直接吃的 Locale?（system → null；其他 BCP-47 code 解析為 Locale）
final localeProvider = Provider<Locale?>((ref) {
  final pref = ref.watch(settingsProvider).locale;
  return switch (pref) {
    SystemLanguage() => null,
    LocaleLanguage(:final code) => _localeFromCode(code),
  };
});

/// 把 BCP-47 dash-form (e.g. "zh-Hans", "pt-BR", "ja") 轉成 Flutter [Locale]。
///
/// 第二段若是 4 字元（BCP-47 script code 慣例，如 `Hans` / `Hant` / `Latn`）
/// 走 [Locale.fromSubtags] 設 `scriptCode`；否則當 region code 用一般建構式。
/// 這對應 Flutter `gen_l10n` 對 `app_zh_Hans.arb` 等
/// 檔名解析的方式——用 `Locale('zh', 'Hans')` 會把 `Hans` 放進 `countryCode`，
/// 跟 supportedLocales 內以 `scriptCode='Hans'` 註冊的 entry 不相等，導致
/// Flutter resolver fallback 到 template 並顯示錯誤語言。
Locale _localeFromCode(String code) {
  final parts = code.split('-');
  if (parts.length == 1) return Locale(parts[0]);
  if (parts[1].length == 4) {
    return Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]);
  }
  return Locale(parts[0], parts[1]);
}
