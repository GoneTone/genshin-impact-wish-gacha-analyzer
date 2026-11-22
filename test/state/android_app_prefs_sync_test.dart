import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/app_prefs_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/android_app_prefs_sync.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AppPrefsPlatform.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// 模擬的系統端 app 語言；null 代表 Android 13 以下（不支援）。
  String? systemTag;

  /// 送給系統的 setLocale 標籤，依序記錄。
  late List<String> pushed;

  setUp(() {
    pushed = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getLocale':
          return systemTag;
        case 'setLocale':
          final tag = (call.arguments as Map)['tag'] as String;
          pushed.add(tag);
          systemTag = tag;
          return true;
        default:
          return true;
      }
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// 以 [prefs] 為磁碟內容建 container、等設定載入並啟動同步。
  Future<ProviderContainer> start(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    await container.read(androidAppPrefsSyncProvider).start();
    return container;
  }

  LanguagePreference localeOf(ProviderContainer c) =>
      c.read(settingsProvider).locale;

  group('startup', () {
    test('a language picked in system settings wins', () async {
      systemTag = 'ja';
      final c = await start({'pref.locale': 'system'});
      expect(localeOf(c), const LocaleLanguage('ja'));
      expect(pushed, isEmpty);
    });

    test('first run pushes an existing in-app choice to the system', () async {
      systemTag = '';
      final c = await start({'pref.locale': 'zh'});
      expect(pushed, ['zh-Hant']);
      expect(localeOf(c), const LocaleLanguage('zh'));
    });

    test('after the first run, system default means follow system', () async {
      systemTag = '';
      final c = await start({
        'pref.locale': 'ja',
        AndroidAppPrefsSync.migratedKey: true,
      });
      expect(localeOf(c), const SystemLanguage());
      expect(pushed, isEmpty);
    });

    test('Android 12 and below leaves the in-app choice alone', () async {
      systemTag = null;
      final c = await start({'pref.locale': 'ja'});
      expect(localeOf(c), const LocaleLanguage('ja'));
      expect(pushed, isEmpty);
    });
  });

  group('app to system', () {
    test('changing the language in the app updates the system', () async {
      systemTag = '';
      final c = await start({AndroidAppPrefsSync.migratedKey: true});
      await c
          .read(settingsProvider.notifier)
          .setLocale(const LocaleLanguage('zh-Hans'));
      await pumpEventQueue();
      expect(pushed, ['zh-Hans']);
      await c.read(settingsProvider.notifier).setLocale(const SystemLanguage());
      await pumpEventQueue();
      expect(pushed, ['zh-Hans', '']);
    });
  });

  group('system to app', () {
    test('a change made in system settings updates the app', () async {
      systemTag = '';
      final c = await start({AndroidAppPrefsSync.migratedKey: true});
      systemTag = 'zh-Hant-TW';
      c.read(androidAppPrefsSyncProvider).didChangeLocales(null);
      await pumpEventQueue();
      expect(localeOf(c), const LocaleLanguage('zh'));
      // 系統已是同一個語言，不再回推。
      expect(pushed, isEmpty);
    });

    test('resetting to system default in system settings follows', () async {
      systemTag = 'ja';
      final c = await start({AndroidAppPrefsSync.migratedKey: true});
      systemTag = '';
      c.read(androidAppPrefsSyncProvider).didChangeLocales(null);
      await pumpEventQueue();
      expect(localeOf(c), const SystemLanguage());
      expect(pushed, isEmpty);
    });
  });
}
