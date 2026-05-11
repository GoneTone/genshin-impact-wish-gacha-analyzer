// lib/state/localization_metadata.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

@immutable
class LocaleMetadata {
  const LocaleMetadata({required this.nativeName, required this.translator});

  /// 該 locale 的母語名稱，例如 "日本語"、"Português (Brasil)"。
  final String nativeName;

  /// 該 locale 的翻譯者署名（逗號分隔），原始語言為空字串。
  final String translator;
}

/// 一次性 load 所有 [AppLocalizations.supportedLocales] 的 metadata；
/// Settings 語言選單與 About 區塊讀此 provider。
///
/// `delegate.load` 對 gen_l10n 編譯後的 const 內容回傳 [SynchronousFuture]，
/// 所以 FutureProvider 幾乎沒有等待時間（同 microtask 內完成）。
///
/// 自動排除 gen_l10n 為支援 script/country 變體而生成的「裸」base locale
/// （如 `zh` 是 `zh_Hant` + `zh_Hans` 的 fallback base、`pt` 是 `pt_BR` 的
/// fallback base）——這些 bare locale 沒有獨立的 `localeNativeName`，在
/// dropdown 會跟具體變體重複顯示。
final localeMetadataProvider = FutureProvider<Map<String, LocaleMetadata>>((
  ref,
) async {
  final all = AppLocalizations.supportedLocales;
  final result = <String, LocaleMetadata>{};
  for (final locale in all) {
    if (_isBareBaseOfSpecificVariant(locale, all)) continue;
    final l = await AppLocalizations.delegate.load(locale);
    result[locale.toLanguageTag()] = LocaleMetadata(
      nativeName: l.localeNativeName,
      translator: l.localeTranslator,
    );
  }
  return result;
});

bool _isBareBaseOfSpecificVariant(Locale locale, List<Locale> all) {
  if (locale.scriptCode != null || locale.countryCode != null) return false;
  return all.any(
    (other) =>
        other.languageCode == locale.languageCode &&
        (other.scriptCode != null || other.countryCode != null),
  );
}
