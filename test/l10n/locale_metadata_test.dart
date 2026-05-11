// test/l10n/locale_metadata_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

void main() {
  group('AppLocalizations locale metadata', () {
    test('每個 supported locale 都能 load 且 localeNativeName 非空', () async {
      for (final locale in AppLocalizations.supportedLocales) {
        final l = await AppLocalizations.delegate.load(locale);
        expect(
          l.localeNativeName,
          isNotEmpty,
          reason: '${locale.toLanguageTag()} 的 localeNativeName 不能為空',
        );
      }
    });

    test('zh_Hant / zh_Hans 的 localeTranslator 為空字串', () async {
      final hant = await AppLocalizations.delegate.load(
        const Locale('zh', 'Hant'),
      );
      expect(hant.localeTranslator, isEmpty);

      final hans = await AppLocalizations.delegate.load(
        const Locale('zh', 'Hans'),
      );
      expect(hans.localeTranslator, isEmpty);
    });

    test('日文 localeNativeName = "日本語"', () async {
      final ja = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(ja.localeNativeName, '日本語');
    });

    test('巴西葡萄牙文 localeNativeName 含 "Brasil" 或 "Portugu"', () async {
      final pt = await AppLocalizations.delegate.load(const Locale('pt', 'BR'));
      expect(
        pt.localeNativeName.toLowerCase(),
        anyOf(contains('brasil'), contains('portugu')),
        reason: 'pt-BR localeNativeName 看起來不像葡萄牙文',
      );
    });

    test('supportedLocales 包含 zh_Hant / zh_Hans / en / ja / pt_BR', () {
      final tags = AppLocalizations.supportedLocales
          .map((l) => l.toLanguageTag())
          .toSet();
      expect(tags, contains('zh-Hant'));
      expect(tags, contains('zh-Hans'));
      expect(tags, contains('en'));
      expect(tags, contains('ja'));
      expect(tags, contains('pt-BR'));
    });
  });
}
