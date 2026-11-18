import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

/// 已釋出（`localeNativeName` 有實際翻譯、未 fallback 成模板繁中）的 locale 清單。
///
/// 餵給 `MaterialApp.supportedLocales` 與語言選單，使 OS 為某半翻譯語系的使用者
/// 不會被解析到 100% fallback 的空殼、選單也不會冒出多個「繁體中文」。
/// gate 邏輯見 [filterReleasedLocales]。
///
/// 同步性依賴與 [localeMetadataProvider] 相同：`delegate.load` 對 const 內容回
/// [SynchronousFuture]，故 `.then` 在同 stack frame 同步填妥 `names` 後，下一行
/// 才呼叫 [filterReleasedLocales]。若未來 gen_l10n 改為 async load，`names` 會空、
/// 此 provider 需退回 FutureProvider。
final releasedLocalesProvider = Provider<List<Locale>>((ref) {
  // 須對齊 l10n.yaml 的 template-arb-file（app_zh.arb）；模板換了這裡要跟著改，
  // 否則新模板會因 nativeName 與自身相等的判斷失準而被誤排除。
  const template = Locale('zh');
  final names = <Locale, String>{};
  for (final locale in AppLocalizations.supportedLocales) {
    AppLocalizations.delegate.load(locale).then((l) {
      names[locale] = l.localeNativeName;
    });
  }
  return filterReleasedLocales(
    all: AppLocalizations.supportedLocales,
    template: template,
    templateNativeName: names[template] ?? '',
    nativeNameOf: (l) => names[l] ?? '',
  );
});

/// 一次性 load 所有「已釋出」locale 的 metadata；Settings 語言選單與
/// About / Contributors 區塊讀此 provider。
///
/// `delegate.load` 對 gen_l10n 編譯後的 const 內容回傳 [SynchronousFuture]，
/// 所以 `.then` callback 在同個 stack frame 內同步觸發、無 microtask 跳轉，
/// 也就不會多畫一個 `AsyncLoading` frame（避免設定頁進入時的 spinner 閃）。
final localeMetadataProvider = Provider<Map<String, LocaleMetadata>>((ref) {
  final released = ref.watch(releasedLocalesProvider);
  final result = <String, LocaleMetadata>{};
  for (final locale in released) {
    AppLocalizations.delegate.load(locale).then((l) {
      result[locale.toLanguageTag()] = LocaleMetadata(
        nativeName: l.localeNativeName,
        translator: l.localeTranslator,
      );
    });
  }
  return result;
});

/// `MaterialApp.localizationsDelegates` 用的 delegate 清單：與
/// [AppLocalizations.localizationsDelegates] 相同，但 Material／Cupertino 內建文字
/// 在裸 `zh` 時改載繁中（見 [_BareZhAsHantDelegate]）。
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  _BareZhAsHantDelegate<MaterialLocalizations>(
    GlobalMaterialLocalizations.delegate,
  ),
  _BareZhAsHantDelegate<CupertinoLocalizations>(
    GlobalCupertinoLocalizations.delegate,
  ),
  GlobalWidgetsLocalizations.delegate,
];

/// 本 app 以裸 `zh` 代表繁中，但 flutter_localizations 對裸 `zh` 預設給簡中
/// （例如 tooltip 會顯示「关闭」）；這個 wrapper 在裸 `zh` 時改用 `zh-Hant-TW` 載入，
/// 其餘 locale 原樣轉交 [_inner]。
class _BareZhAsHantDelegate<T> extends LocalizationsDelegate<T> {
  /// 包住 [_inner]。
  const _BareZhAsHantDelegate(this._inner);

  /// 實際提供翻譯的 Flutter 內建 delegate。
  final LocalizationsDelegate<T> _inner;

  /// 裸 `zh` 改用的繁中 locale。
  static const _hant = Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hant',
    countryCode: 'TW',
  );

  @override
  bool isSupported(Locale locale) => _inner.isSupported(locale);

  @override
  Future<T> load(Locale locale) {
    final isBareZh =
        locale.languageCode == 'zh' &&
        locale.scriptCode == null &&
        locale.countryCode == null;
    return _inner.load(isBareZh ? _hant : locale);
  }

  @override
  bool shouldReload(_BareZhAsHantDelegate<T> old) => false;
}

/// `MaterialApp.localeListResolutionCallback`：補足 Flutter
/// `basicLocaleListResolution` 無法正確區分中文繁簡的兩種情況：
/// region-only locale（Windows 回 `zh-CN` / `zh-TW`，沒帶 scriptCode），以及
/// 帶 scriptCode 的 `zh-Hant-*`（Android 的格式；本 app 沒有 `zh_Hant`，
/// Flutter 預設只會記為「僅語言相符」並繼續往下找，可能被後面的 `zh-Hans-*` 搶走）。
///
/// 映射：CN / SG / MY → `zh-Hans`；TW / HK / MO → 裸 `zh`（繁體中文）；
/// `zh-Hant-*` → 裸 `zh`。
/// 對其他語言、或 `zh-Hans-*` 一律回傳 null，
/// 落到 Flutter 預設邏輯處理（會正確尊重使用者偏好順序）。
///
/// 演算法概念：對每個偏好 locale，若 Flutter 預設能精確匹配
/// （exact / lang+script / lang+country）就回 null 讓它處理；
/// 否則若是 `zh-Hant-*` 或 Chinese region-only 就介入；否則若 lang-only 可匹配
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
    // 繁中以裸 zh 提供（沒有 zh_Hant），Flutter 預設邏輯對 zh-Hant-* 只會記為「僅語言相符」
    // 並繼續往下找，遇到後面的 zh-Hans-* 就會選成簡中（Android 會回帶 scriptCode 的 locale）。
    if (user.languageCode == 'zh' && user.scriptCode == 'Hant') {
      if (supportedLocales.contains(const Locale('zh'))) {
        return const Locale('zh');
      }
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
