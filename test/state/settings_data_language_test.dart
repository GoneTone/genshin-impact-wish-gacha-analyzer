import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('setDataLanguage(code) sets value and marks seeded', () async {
    final c = makeContainer();
    final notifier = c.read(settingsProvider.notifier);
    await notifier.waitForLoad();
    await notifier.setDataLanguage('en-us');
    expect(c.read(settingsProvider).dataLanguage, 'en-us');
    expect(c.read(settingsProvider).dataLanguageSeeded, isTrue);
    expect(c.read(dataLanguageProvider), 'en-us');
  });

  test('setDataLanguage(null) marks seeded (explicit no-convert)', () async {
    final c = makeContainer();
    final notifier = c.read(settingsProvider.notifier);
    await notifier.waitForLoad();
    await notifier.setDataLanguage(null);
    expect(c.read(settingsProvider).dataLanguage, isNull);
    expect(c.read(settingsProvider).dataLanguageSeeded, isTrue);
  });

  test('seedDataLanguageIfUnset seeds only when not seeded and code supported', () async {
    final c = makeContainer();
    final notifier = c.read(settingsProvider.notifier);
    await notifier.waitForLoad();
    await notifier.seedDataLanguageIfUnset('zh-tw');
    expect(c.read(settingsProvider).dataLanguage, 'zh-tw');
    await notifier.seedDataLanguageIfUnset('en-us');
    expect(c.read(settingsProvider).dataLanguage, 'zh-tw');
  });

  test('seedDataLanguageIfUnset no-op for unsupported code', () async {
    final c = makeContainer();
    final notifier = c.read(settingsProvider.notifier);
    await notifier.waitForLoad();
    await notifier.seedDataLanguageIfUnset('en');
    expect(c.read(settingsProvider).dataLanguage, isNull);
    expect(c.read(settingsProvider).dataLanguageSeeded, isFalse);
  });
}
