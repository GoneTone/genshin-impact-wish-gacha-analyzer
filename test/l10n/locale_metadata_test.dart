// test/l10n/locale_metadata_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';

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

    test('裸 zh（繁中）/ zh_Hans 的 localeTranslator 為空字串', () async {
      final zh = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(zh.localeTranslator, isEmpty);

      final hans = await AppLocalizations.delegate.load(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
      expect(hans.localeTranslator, isEmpty);
    });

    test('裸 zh localeNativeName = "繁體中文"', () async {
      final zh = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(zh.localeNativeName, '繁體中文');
    });

    test('日文 localeNativeName = "日本語"', () async {
      final ja = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(ja.localeNativeName, '日本語');
    });

    test('葡萄牙文 localeNativeName 含 "Portugu"', () async {
      final pt = await AppLocalizations.delegate.load(const Locale('pt'));
      expect(
        pt.localeNativeName.toLowerCase(),
        contains('portugu'),
        reason: 'pt localeNativeName 看起來不像葡萄牙文',
      );
    });

    test('裸 zh 提供全部 contributors keys（模板必填）', () async {
      final l = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(l.navContributors, isNotEmpty);
      expect(l.contributorsTitle, isNotEmpty);
      expect(l.contributorsSubtitle, isNotEmpty);
      expect(l.contributorsProjectLeader, isNotEmpty);
      expect(l.contributorsTesters, isNotEmpty);
      expect(l.contributorsGithubContributors, isNotEmpty);
      expect(l.contributorsTranslationReviewer, isNotEmpty);
      expect(l.contributorsTranslatedLanguages, isNotEmpty);
      expect(l.contributorsHelpTranslate, isNotEmpty);
      expect(l.contributorsProjectLicense, isNotEmpty);
    });

    test('supportedLocales 包含 zh / zh-Hans / en / ja / pt，且不含 zh-Hant', () {
      final tags = AppLocalizations.supportedLocales
          .map((l) => l.toLanguageTag())
          .toSet();
      expect(tags, contains('zh'));
      expect(tags, contains('zh-Hans'));
      expect(tags, isNot(contains('zh-Hant')));
      expect(tags, contains('en'));
      expect(tags, contains('ja'));
      expect(tags, contains('pt'));
    });

    test(
      'localeTranslatorLabel 帶 placeholder:每個 supported locale 都非空且含代入值',
      () async {
        for (final locale in AppLocalizations.supportedLocales) {
          final l = await AppLocalizations.delegate.load(locale);
          final out = l.localeTranslatorLabel('__TESTER__');
          expect(
            out,
            isNotEmpty,
            reason: '${locale.toLanguageTag()} 的 localeTranslatorLabel 不能為空',
          );
          expect(
            out,
            contains('__TESTER__'),
            reason:
                '${locale.toLanguageTag()} 的 localeTranslatorLabel 必須代入 {translator}',
          );
        }
      },
    );

    test('裸 zh（繁中）localeTranslatorLabel = "翻譯者：X"', () async {
      final zh = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(zh.localeTranslatorLabel('X'), '翻譯者：X');
    });

    test('日文 localeTranslatorLabel = "翻訳者：X"', () async {
      final ja = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(ja.localeTranslatorLabel('X'), '翻訳者：X');
    });
  });

  group('localeMetadataProvider', () {
    test('裸 zh（繁中）與 zh-Hans 都保留，無重複空殼被排除', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final metadata = container.read(localeMetadataProvider);
      final tags = metadata.keys.toSet();

      expect(tags, containsAll(<String>['zh', 'zh-Hans']));
      expect(tags, isNot(contains('zh-Hant')));
      expect(tags, contains('pt'));
      expect(tags, containsAll(<String>['en', 'ja', 'es', 'fr', 'th', 'vi']));
    });

    test('每個保留的 locale 都有非空的 nativeName', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final metadata = container.read(localeMetadataProvider);
      for (final entry in metadata.entries) {
        expect(
          entry.value.nativeName,
          isNotEmpty,
          reason: '${entry.key} 的 nativeName 不能為空',
        );
      }
    });
  });

  group('localeListResolution', () {
    // 代表性 supportedLocales：裸 zh（繁中）、zh-Hans、單一 pt、其他 bare。
    const supported = <Locale>[
      Locale('en'),
      Locale('es'),
      Locale('fr'),
      Locale('ja'),
      Locale('pt'),
      Locale('th'),
      Locale('vi'),
      Locale('zh'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    ];

    test('zh-CN → zh-Hans（region 大陸映射到簡體）', () {
      final result = localeListResolution([
        const Locale('zh', 'CN'),
      ], supported);
      expect(
        result,
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
    });

    test('zh-SG / zh-MY → zh-Hans', () {
      expect(
        localeListResolution([const Locale('zh', 'SG')], supported),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
      expect(
        localeListResolution([const Locale('zh', 'MY')], supported),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
    });

    test('zh-TW / zh-HK / zh-MO → 裸 zh（繁體中文）', () {
      for (final region in ['TW', 'HK', 'MO']) {
        expect(
          localeListResolution([Locale('zh', region)], supported),
          const Locale('zh'),
          reason: 'zh-$region 應映射到裸 zh（繁中）',
        );
      }
    });

    test('zh-Hant-TW (帶 scriptCode) → null，交給 Flutter 預設邏輯', () {
      final result = localeListResolution([
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'TW',
        ),
      ], supported);
      expect(result, isNull);
    });

    test('en-US (其他語言) → null', () {
      expect(
        localeListResolution([const Locale('en', 'US')], supported),
        isNull,
      );
    });

    test('ja-JP / pt-BR / de-DE (其他語言) → null', () {
      expect(
        localeListResolution([const Locale('ja', 'JP')], supported),
        isNull,
      );
      expect(
        localeListResolution([const Locale('pt', 'BR')], supported),
        isNull,
      );
      expect(
        localeListResolution([const Locale('de', 'DE')], supported),
        isNull,
      );
    });

    test('使用者偏好順序：[en-US, zh-CN] → null（en 先匹配到，尊重順序）', () {
      final result = localeListResolution([
        const Locale('en', 'US'),
        const Locale('zh', 'CN'),
      ], supported);
      expect(result, isNull);
    });

    test('[yue-HK, zh-CN] → zh-Hans (yue 不支援，繼續處理 zh-CN)', () {
      final result = localeListResolution([
        const Locale('yue', 'HK'),
        const Locale('zh', 'CN'),
      ], supported);
      expect(
        result,
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
    });

    test('裸 zh (no script no country) → null', () {
      // 沒有 region 資訊無法判定，交給 Flutter 預設（會 fallback 到裸 zh = 繁中）
      expect(localeListResolution([const Locale('zh')], supported), isNull);
    });

    test('空 / null systemLocales → null', () {
      expect(localeListResolution(null, supported), isNull);
      expect(localeListResolution(const [], supported), isNull);
    });

    test('完全不支援的語言 [ko-KR] → null', () {
      expect(
        localeListResolution([const Locale('ko', 'KR')], supported),
        isNull,
      );
    });
  });

  group('sortedLocaleMetadata', () {
    test('依 nativeName 字典序排列', () {
      final input = <String, LocaleMetadata>{
        'b': const LocaleMetadata(nativeName: 'Banana', translator: ''),
        'a': const LocaleMetadata(nativeName: 'Apple', translator: ''),
        'c': const LocaleMetadata(nativeName: 'Cherry', translator: ''),
      };
      final sorted = sortedLocaleMetadata(input);
      expect(sorted.map((e) => e.value.nativeName), [
        'Apple',
        'Banana',
        'Cherry',
      ]);
    });

    test('空 Map → 空 List', () {
      expect(sortedLocaleMetadata(const {}), isEmpty);
    });
  });
}
