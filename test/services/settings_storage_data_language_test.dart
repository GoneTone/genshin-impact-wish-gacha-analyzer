import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('absent key -> uninitialized (null, not seeded)', () async {
    final s = await SettingsStorage.load();
    expect(s.dataLanguage, isNull);
    expect(s.dataLanguageSeeded, isFalse);
  });

  test('"none" -> explicitly unset (null, seeded)', () async {
    SharedPreferences.setMockInitialValues({'pref.dataLanguage': 'none'});
    final s = await SettingsStorage.load();
    expect(s.dataLanguage, isNull);
    expect(s.dataLanguageSeeded, isTrue);
  });

  test('language code -> specified (code, seeded)', () async {
    SharedPreferences.setMockInitialValues({'pref.dataLanguage': 'ja-jp'});
    final s = await SettingsStorage.load();
    expect(s.dataLanguage, 'ja-jp');
    expect(s.dataLanguageSeeded, isTrue);
  });

  test('save: not seeded removes key', () async {
    SharedPreferences.setMockInitialValues({'pref.dataLanguage': 'ja-jp'});
    await SettingsStorage.save(
      AppSettings.defaults.copyWith(dataLanguageSeeded: false),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pref.dataLanguage'), isNull);
  });

  test('save: seeded + null writes "none"', () async {
    await SettingsStorage.save(
      AppSettings.defaults.copyWith(dataLanguageSeeded: true),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pref.dataLanguage'), 'none');
  });

  test('save: seeded + code writes code', () async {
    await SettingsStorage.save(
      AppSettings.defaults.copyWith(dataLanguage: 'en-us', dataLanguageSeeded: true),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pref.dataLanguage'), 'en-us');
  });

  test('copyWith clearDataLanguage resets to null', () async {
    final s = AppSettings.defaults.copyWith(dataLanguage: 'ja-jp', dataLanguageSeeded: true);
    final cleared = s.copyWith(clearDataLanguage: true);
    expect(cleared.dataLanguage, isNull);
    expect(cleared.dataLanguageSeeded, isTrue);
  });
}
