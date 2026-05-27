import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LanguagePreference', () {
    test('fromCode("system") 回傳 SystemLanguage', () {
      expect(LanguagePreference.fromCode('system'), isA<SystemLanguage>());
    });

    test('fromCode("zh-Hans") 回傳 LocaleLanguage("zh-Hans")', () {
      final pref = LanguagePreference.fromCode('zh-Hans');
      expect(pref, isA<LocaleLanguage>());
      expect((pref as LocaleLanguage).code, 'zh-Hans');
    });

    test('fromCode("pt-BR") 回傳 LocaleLanguage("pt-BR")', () {
      final pref = LanguagePreference.fromCode('pt-BR');
      expect((pref as LocaleLanguage).code, 'pt-BR');
    });

    test('toCode roundtrip 在 system / zh-Hans / en / pt-BR / ja 都保持原值', () {
      for (final code in ['system', 'zh-Hans', 'en', 'pt-BR', 'ja']) {
        expect(LanguagePreference.fromCode(code).toCode(), code);
      }
    });

    test('SystemLanguage 相等比較', () {
      expect(const SystemLanguage() == const SystemLanguage(), isTrue);
      expect(const SystemLanguage() == const LocaleLanguage('en'), isFalse);
    });

    test('LocaleLanguage 依 code 相等', () {
      expect(
        const LocaleLanguage('zh-Hans') == const LocaleLanguage('zh-Hans'),
        isTrue,
      );
      expect(
        const LocaleLanguage('zh-Hans') == const LocaleLanguage('en'),
        isFalse,
      );
    });

    test('hashCode 與 == 一致', () {
      expect(
        const LocaleLanguage('ja').hashCode,
        const LocaleLanguage('ja').hashCode,
      );
      expect(const SystemLanguage().hashCode, const SystemLanguage().hashCode);
    });
  });

  group('SettingsStorage', () {
    test('預設回傳 system theme 與 SystemLanguage locale', () async {
      final s = await SettingsStorage.load();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.locale, const SystemLanguage());
    });

    test('save 後 load 回得到相同值', () async {
      await SettingsStorage.save(
        const AppSettings(
          themeMode: AppThemeMode.dark,
          locale: LocaleLanguage('en'),
        ),
      );
      final s = await SettingsStorage.load();
      expect(s.themeMode, AppThemeMode.dark);
      expect(s.locale, const LocaleLanguage('en'));
    });

    test(
      '未知 themeMode 降級為 system；任意非 system locale 字串為 LocaleLanguage',
      () async {
        SharedPreferences.setMockInitialValues({
          'pref.themeMode': 'rainbow',
          'pref.locale': 'ja',
        });
        final s = await SettingsStorage.load();
        expect(s.themeMode, AppThemeMode.system);
        expect(s.locale, const LocaleLanguage('ja'));
      },
    );

    test('已存的 pref.locale 字串能正確解析為 LocaleLanguage', () async {
      SharedPreferences.setMockInitialValues({'pref.locale': 'zh-Hans'});
      final s = await SettingsStorage.load();
      expect(s.locale, const LocaleLanguage('zh-Hans'));
    });

    test('locale = "system" 字串 解析為 SystemLanguage', () async {
      SharedPreferences.setMockInitialValues({'pref.locale': 'system'});
      final s = await SettingsStorage.load();
      expect(s.locale, const SystemLanguage());
    });

    test('locale 缺欄位（null）解析為 SystemLanguage', () async {
      final s = await SettingsStorage.load();
      expect(s.locale, const SystemLanguage());
    });

    test('新欄位預設為 null / 空 map / 空 list', () async {
      final s = await SettingsStorage.load();
      expect(s.lastActiveUid, isNull);
      expect(s.uidAliases, isEmpty);
      expect(s.uidOrder, isEmpty);
      expect(s.skippedReleaseTag, isNull);
    });

    test('lastActiveUid round-trip', () async {
      await SettingsStorage.save(
        const AppSettings(
          themeMode: AppThemeMode.system,
          locale: SystemLanguage(),
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
          locale: SystemLanguage(),
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
          locale: SystemLanguage(),
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

    test('skippedReleaseTag round-trip', () async {
      await SettingsStorage.save(
        const AppSettings(
          themeMode: AppThemeMode.system,
          locale: SystemLanguage(),
          skippedReleaseTag: 'v1.2.0',
        ),
      );
      final s = await SettingsStorage.load();
      expect(s.skippedReleaseTag, 'v1.2.0');
    });

    test('skippedReleaseTag null 表清除（save 後 load 取得 null）', () async {
      SharedPreferences.setMockInitialValues({
        'pref.skippedReleaseTag': 'v1.0.0',
      });
      await SettingsStorage.save(
        const AppSettings(
          themeMode: AppThemeMode.system,
          locale: SystemLanguage(),
          skippedReleaseTag: null,
        ),
      );
      final s = await SettingsStorage.load();
      expect(s.skippedReleaseTag, isNull);
    });

    test('預設 skippedReleaseTag 為 null', () async {
      final s = await SettingsStorage.load();
      expect(s.skippedReleaseTag, isNull);
    });
  });

  group('maskUidInUi', () {
    test('defaults to false when key absent', () async {
      final s = await SettingsStorage.load();
      expect(s.maskUidInUi, false);
    });

    test('roundtrips true', () async {
      await SettingsStorage.save(
        AppSettings.defaults.copyWith(maskUidInUi: true),
      );
      final s = await SettingsStorage.load();
      expect(s.maskUidInUi, true);
    });

    test('roundtrips false explicitly', () async {
      await SettingsStorage.save(
        AppSettings.defaults.copyWith(maskUidInUi: false),
      );
      final s = await SettingsStorage.load();
      expect(s.maskUidInUi, false);
    });
  });
}
