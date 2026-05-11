// test/state/locale_provider_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> makeContainer(LanguagePreference initial) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    await container.read(settingsProvider.notifier).setLocale(initial);
    return container;
  }

  test('SystemLanguage → null', () async {
    final c = await makeContainer(const SystemLanguage());
    expect(c.read(localeProvider), isNull);
  });

  test('LocaleLanguage("zh-Hant") → Locale("zh", "Hant")', () async {
    final c = await makeContainer(const LocaleLanguage('zh-Hant'));
    expect(c.read(localeProvider), const Locale('zh', 'Hant'));
  });

  test('LocaleLanguage("zh-Hans") → Locale("zh", "Hans")', () async {
    final c = await makeContainer(const LocaleLanguage('zh-Hans'));
    expect(c.read(localeProvider), const Locale('zh', 'Hans'));
  });

  test('LocaleLanguage("pt-BR") → Locale("pt", "BR")', () async {
    final c = await makeContainer(const LocaleLanguage('pt-BR'));
    expect(c.read(localeProvider), const Locale('pt', 'BR'));
  });

  test('LocaleLanguage("pt-PT") → Locale("pt", "PT")', () async {
    final c = await makeContainer(const LocaleLanguage('pt-PT'));
    expect(c.read(localeProvider), const Locale('pt', 'PT'));
  });

  test('LocaleLanguage("ja") → Locale("ja")', () async {
    final c = await makeContainer(const LocaleLanguage('ja'));
    expect(c.read(localeProvider), const Locale('ja'));
  });

  test('LocaleLanguage("en") → Locale("en")', () async {
    final c = await makeContainer(const LocaleLanguage('en'));
    expect(c.read(localeProvider), const Locale('en'));
  });
}
