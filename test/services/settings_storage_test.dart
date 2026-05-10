// test/services/settings_storage_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsStorage', () {
    test('預設回傳 system theme 與 system locale', () async {
      final s = await SettingsStorage.load();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.locale, AppLocale.system);
    });

    test('save 後 load 回得到相同值', () async {
      await SettingsStorage.save(
        const AppSettings(themeMode: AppThemeMode.dark, locale: AppLocale.en),
      );
      final s = await SettingsStorage.load();
      expect(s.themeMode, AppThemeMode.dark);
      expect(s.locale, AppLocale.en);
    });

    test('未知 key 值降級為 system', () async {
      SharedPreferences.setMockInitialValues({
        'pref.themeMode': 'rainbow',
        'pref.locale': 'klingon',
      });
      final s = await SettingsStorage.load();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.locale, AppLocale.system);
    });
  });
}
