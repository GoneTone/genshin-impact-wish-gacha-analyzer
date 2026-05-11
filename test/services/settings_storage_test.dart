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

    test('新欄位預設為 null / 空 map / 空 list', () async {
      final s = await SettingsStorage.load();
      expect(s.lastActiveUid, isNull);
      expect(s.uidAliases, isEmpty);
      expect(s.uidOrder, isEmpty);
    });

    test('lastActiveUid round-trip', () async {
      await SettingsStorage.save(
        const AppSettings(
          themeMode: AppThemeMode.system,
          locale: AppLocale.system,
          lastActiveUid: '123456789',
        ),
      );
      final s = await SettingsStorage.load();
      expect(s.lastActiveUid, '123456789');
    });

    test('uidAliases round-trip', () async {
      await SettingsStorage.save(
        const AppSettings(
          themeMode: AppThemeMode.system,
          locale: AppLocale.system,
          uidAliases: {'A': '主帳', 'B': '小號'},
        ),
      );
      final s = await SettingsStorage.load();
      expect(s.uidAliases, {'A': '主帳', 'B': '小號'});
    });

    test('uidOrder round-trip', () async {
      await SettingsStorage.save(
        const AppSettings(
          themeMode: AppThemeMode.system,
          locale: AppLocale.system,
          uidOrder: ['C', 'A', 'B'],
        ),
      );
      final s = await SettingsStorage.load();
      expect(s.uidOrder, ['C', 'A', 'B']);
    });

    test('uidAliases JSON 壞掉 → fallback 為空 map', () async {
      SharedPreferences.setMockInitialValues({
        'pref.uidAliases': 'not-json-at-all',
      });
      final s = await SettingsStorage.load();
      expect(s.uidAliases, isEmpty);
    });

    test('uidOrder JSON 壞掉 → fallback 為空 list', () async {
      SharedPreferences.setMockInitialValues({'pref.uidOrder': '{not-a-list}'});
      final s = await SettingsStorage.load();
      expect(s.uidOrder, isEmpty);
    });
  });
}
