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

  group('localeMetadataProvider', () {
    test('排除 bare zh / pt（已有 script/country 變體存在）', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final metadata = await container.read(localeMetadataProvider.future);
      final tags = metadata.keys.toSet();

      // bare base locale 應被過濾掉
      expect(
        tags,
        isNot(contains('zh')),
        reason: 'bare zh 跟 zh_Hant / zh_Hans 重複，應排除',
      );
      expect(tags, isNot(contains('pt')), reason: 'bare pt 跟 pt_BR 重複，應排除');

      // 具體變體仍在
      expect(tags, containsAll(<String>['zh-Hant', 'zh-Hans', 'pt-BR']));

      // 沒有變體的單一語言（en/ja/...）保留
      expect(tags, containsAll(<String>['en', 'ja', 'es', 'fr', 'th', 'vi']));
    });

    test('每個保留的 locale 都有非空的 nativeName', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final metadata = await container.read(localeMetadataProvider.future);
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
    // 模擬一份代表性的 supportedLocales：含 bare zh、zh-Hant、zh-Hans、pt-BR、
    // 以及若干其他 bare locale。
    const supported = <Locale>[
      Locale('en'),
      Locale('es'),
      Locale('fr'),
      Locale('ja'),
      Locale('pt'),
      Locale('pt', 'BR'),
      Locale('th'),
      Locale('vi'),
      Locale('zh'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
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

    test('zh-TW / zh-HK / zh-MO → zh-Hant', () {
      for (final region in ['TW', 'HK', 'MO']) {
        expect(
          localeListResolution([Locale('zh', region)], supported),
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
          reason: 'zh-$region 應映射到 zh-Hant',
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
      // 沒有 region 資訊無法判定，交給 Flutter 預設（會 fallback 到 bare zh / template）
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
}
