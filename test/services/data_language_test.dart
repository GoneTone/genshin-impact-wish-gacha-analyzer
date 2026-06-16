import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_language.dart';

void main() {
  test('has 15 options with unique codes', () {
    expect(kDataLanguageOptions.length, 15);
    final codes = kDataLanguageOptions.map((o) => o.code).toList();
    expect(codes.toSet().length, 15);
    expect(kDataLanguageCodes, codes.toSet());
  });

  test('isSupportedDataLanguage matches the option set', () {
    expect(isSupportedDataLanguage('zh-tw'), isTrue);
    expect(isSupportedDataLanguage('en-us'), isTrue);
    expect(isSupportedDataLanguage('ja-jp'), isTrue);
    expect(isSupportedDataLanguage('en'), isFalse);
    expect(isSupportedDataLanguage('xx-yy'), isFalse);
  });

  test('every label is non-empty', () {
    for (final o in kDataLanguageOptions) {
      expect(o.label.isNotEmpty, isTrue, reason: 'code=${o.code}');
    }
  });
}
