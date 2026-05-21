import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

/// 語言的顯示名稱與翻譯者資訊。
@immutable
class LocaleMetadata {
  /// 建立 [LocaleMetadata]。
  const LocaleMetadata({required this.nativeName, required this.translator});

  /// 該 locale 的母語名稱，例如 "日本語"、"Português (Brasil)"。
  final String nativeName;

  /// 該 locale 的翻譯者署名（逗號分隔），原始語言為空字串。
  final String translator;
}

/// 從 [all] 過濾出「已釋出」的 locale：保留 [template] 自身，以及 `nativeName`
/// 不等於 [templateNativeName] 的 locale。
///
/// gen-l10n 對漏翻 `localeNativeName` 的語系會 fallback 成模板（裸 `zh` = 繁體
/// 中文）的顯示名，這類「空殼／半翻譯」語系的 `nativeName` 會等於
/// [templateNativeName]，據此排除；模板自身則明確保留。[nativeNameOf] 提供
/// 各 locale 的 `localeNativeName`，方便以合成資料做單元測試。
List<Locale> filterReleasedLocales({
  required Iterable<Locale> all,
  required Locale template,
  required String templateNativeName,
  required String Function(Locale) nativeNameOf,
}) {
  return [
    for (final locale in all)
      if (locale == template || nativeNameOf(locale) != templateNativeName)
        locale,
  ];
}

/// 一次性 load 所有 [AppLocalizations.supportedLocales] 的 metadata；
/// Settings 語言選單與 About / Contributors 區塊讀此 provider。
///
/// `delegate.load` 對 gen_l10n 編譯後的 const 內容回傳 [SynchronousFuture]，
/// 所以 `.then` callback 在同個 stack frame 內同步觸發、無 microtask 跳轉，
/// 也就不會多畫一個 `AsyncLoading` frame（避免設定頁進入時的 spinner 閃）。
///
/// 註：此 provider 的同步性依賴 gen_l10n 對 const 內容回 SynchronousFuture
/// 的實作慣例。若未來 gen_l10n 改變 (例如改 async load asset)，此 provider
/// 內 `result` 會空，需退回 FutureProvider。
///
/// 每個 supported locale 都是可選的真實語言（裸 `zh` = 繁體中文，
/// `zh_Hans` = 簡體中文），不再有重複的空殼 base，故全部納入。
final localeMetadataProvider = Provider<Map<String, LocaleMetadata>>((ref) {
  final all = AppLocalizations.supportedLocales;
  final result = <String, LocaleMetadata>{};
  for (final locale in all) {
    AppLocalizations.delegate.load(locale).then((l) {
      result[locale.toLanguageTag()] = LocaleMetadata(
        nativeName: l.localeNativeName,
        translator: l.localeTranslator,
      );
    });
  }
  return result;
});

/// `MaterialApp.localeListResolutionCallback`：補足 Flutter
/// `basicLocaleListResolution` 在中文 region-only locale（例如 OS 只回
/// `zh-CN` / `zh-TW` 而沒帶 scriptCode）時無法區分繁簡的問題。
///
/// 映射：CN / SG / MY → `zh-Hans`；TW / HK / MO → 裸 `zh`（繁體中文）。
/// 對其他語言、或 Chinese 已帶 scriptCode 的情況一律回傳 null，
/// 落到 Flutter 預設邏輯處理（會正確尊重使用者偏好順序）。
///
/// 演算法概念：對每個偏好 locale，若 Flutter 預設能精確匹配
/// （exact / lang+script / lang+country）就回 null 讓它處理；
/// 否則若是 Chinese region-only 就介入；否則若 lang-only 可匹配
/// 也回 null（尊重偏好順序）；都不行才換下一個偏好 locale。
Locale? localeListResolution(
  List<Locale>? systemLocales,
  Iterable<Locale> supportedLocales,
) {
  if (systemLocales == null || systemLocales.isEmpty) return null;

  bool hasExact(Locale u) => supportedLocales.any(
    (s) =>
        s.languageCode == u.languageCode &&
        s.scriptCode == u.scriptCode &&
        s.countryCode == u.countryCode,
  );
  bool hasLangScript(Locale u) =>
      u.scriptCode != null &&
      supportedLocales.any(
        (s) => s.languageCode == u.languageCode && s.scriptCode == u.scriptCode,
      );
  bool hasLangCountry(Locale u) =>
      u.countryCode != null &&
      supportedLocales.any(
        (s) =>
            s.languageCode == u.languageCode && s.countryCode == u.countryCode,
      );
  bool hasLang(Locale u) =>
      supportedLocales.any((s) => s.languageCode == u.languageCode);

  const simplifiedRegions = {'CN', 'SG', 'MY'};

  for (final user in systemLocales) {
    if (hasExact(user) || hasLangScript(user) || hasLangCountry(user)) {
      return null;
    }
    if (user.languageCode == 'zh' &&
        user.scriptCode == null &&
        user.countryCode != null) {
      final wanted = simplifiedRegions.contains(user.countryCode)
          ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')
          : const Locale('zh');
      if (supportedLocales.contains(wanted)) return wanted;
    }
    if (hasLang(user)) return null;
  }
  return null;
}

/// 將 `localeMetadataProvider` 的結果依 `nativeName` 字典序排序，
/// `SettingsPage._LocaleDropdown` 與 `ContributorsPage._LanguageList` 共用。
List<MapEntry<String, LocaleMetadata>> sortedLocaleMetadata(
  Map<String, LocaleMetadata> meta,
) =>
    meta.entries.toList()
      ..sort((a, b) => a.value.nativeName.compareTo(b.value.nativeName));
