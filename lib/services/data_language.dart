/// 單一可選資料語言：HoYoWiki 對齊的 [code] 與母語顯示 [label]。
typedef DataLanguageOption = ({String code, String label});

/// 可選資料語言清單（顯示順序固定），代碼對齊 HoYoLab Wiki，與 App UI 語言獨立。
const List<DataLanguageOption> kDataLanguageOptions = [
  (code: 'zh-tw', label: '繁體中文'),
  (code: 'zh-cn', label: '简体中文'),
  (code: 'en-us', label: 'English'),
  (code: 'ja-jp', label: '日本語'),
  (code: 'ko-kr', label: '한국어'),
  (code: 'es-es', label: 'Español'),
  (code: 'fr-fr', label: 'Français'),
  (code: 'ru-ru', label: 'Русский'),
  (code: 'th-th', label: 'ภาษาไทย'),
  (code: 'vi-vn', label: 'Tiếng Việt'),
  (code: 'de-de', label: 'Deutsch'),
  (code: 'id-id', label: 'Bahasa Indonesia'),
  (code: 'pt-pt', label: 'Português'),
  (code: 'tr-tr', label: 'Türkçe'),
  (code: 'it-it', label: 'Italiano'),
];

/// 可選資料語言代碼集合（供 seeding 判定語言是否在選項內）。
final Set<String> kDataLanguageCodes = {
  for (final o in kDataLanguageOptions) o.code,
};

/// [code] 是否為可選資料語言（用於自動播種：落在選項外則維持未設定）。
bool isSupportedDataLanguage(String code) => kDataLanguageCodes.contains(code);
