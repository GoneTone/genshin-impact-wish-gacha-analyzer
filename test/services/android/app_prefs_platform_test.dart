import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/app_prefs_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AppPrefsPlatform.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  /// 讓 Kotlin 端以 [handler] 回應。
  void respond(Object? Function(MethodCall call) handler) {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('night mode', () {
    for (final mode in AppThemeMode.values) {
      test('sends the ${mode.name} theme to the platform', () async {
        respond((_) => true);
        await AppPrefsPlatform.setNightMode(mode);
        expect(calls.single.method, 'setNightMode');
        expect(calls.single.arguments, {'mode': mode.name});
      });
    }

    test('platform errors are swallowed', () async {
      respond((_) => throw PlatformException(code: 'security'));
      await AppPrefsPlatform.setNightMode(AppThemeMode.dark);
      expect(calls, hasLength(1));
    });

    test('a missing platform implementation is swallowed', () async {
      await AppPrefsPlatform.setNightMode(AppThemeMode.light);
    });
  });

  group('app locale', () {
    test('reads the system tag, empty when none is set', () async {
      respond((_) => 'ja');
      expect(await AppPrefsPlatform.getLocale(), 'ja');
      respond((_) => '');
      expect(await AppPrefsPlatform.getLocale(), '');
    });

    test('null when unsupported or failing', () async {
      respond((_) => null);
      expect(await AppPrefsPlatform.getLocale(), isNull);
      respond((_) => throw PlatformException(code: 'x'));
      expect(await AppPrefsPlatform.getLocale(), isNull);
    });

    test('sends the tag to the platform', () async {
      respond((_) => true);
      await AppPrefsPlatform.setLocale('zh-Hant');
      expect(calls.single.method, 'setLocale');
      expect(calls.single.arguments, {'tag': 'zh-Hant'});
    });
  });

  group('tag mapping', () {
    const released = [
      Locale('zh'),
      Locale('en'),
      Locale('ja'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      Locale('pt', 'BR'),
      Locale('no'),
    ];

    test('preference to system tag', () {
      expect(systemLocaleTagOf(const SystemLanguage()), '');
      expect(systemLocaleTagOf(const LocaleLanguage('zh')), 'zh-Hant');
      expect(systemLocaleTagOf(const LocaleLanguage('zh-Hans')), 'zh-Hans');
      expect(systemLocaleTagOf(const LocaleLanguage('pt-BR')), 'pt-BR');
      expect(systemLocaleTagOf(const LocaleLanguage('ja')), 'ja');
      expect(systemLocaleTagOf(const LocaleLanguage('no')), 'nb');
    });

    test('system tag to preference', () {
      LanguagePreference? of(String tag) =>
          languagePreferenceOfSystemTag(tag, released);
      expect(of(''), const SystemLanguage());
      expect(of('zh-Hant'), const LocaleLanguage('zh'));
      expect(of('zh-Hant-TW'), const LocaleLanguage('zh'));
      expect(of('zh-TW'), const LocaleLanguage('zh'));
      expect(of('zh-Hans'), const LocaleLanguage('zh-Hans'));
      expect(of('zh-Hans-CN'), const LocaleLanguage('zh-Hans'));
      expect(of('zh-CN'), const LocaleLanguage('zh-Hans'));
      expect(of('ja'), const LocaleLanguage('ja'));
      expect(of('ja-JP'), const LocaleLanguage('ja'));
      expect(of('pt-BR'), const LocaleLanguage('pt-BR'));
      expect(of('en-US'), const LocaleLanguage('en'));
      expect(of('nb'), const LocaleLanguage('no'));
      expect(of('nb-NO'), const LocaleLanguage('no'));
      expect(of('nn'), const LocaleLanguage('no'));
      // 舊版送給系統的是 no。
      expect(of('no'), const LocaleLanguage('no'));
    });

    test('a language the app does not offer maps to nothing', () {
      expect(languagePreferenceOfSystemTag('ko', released), isNull);
      expect(languagePreferenceOfSystemTag('id', released), isNull);
    });

    test('every released locale round-trips through its system tag', () {
      for (final locale in released) {
        final pref = LocaleLanguage(locale.toLanguageTag());
        expect(
          languagePreferenceOfSystemTag(systemLocaleTagOf(pref), released),
          pref,
        );
      }
    });
  });
}
