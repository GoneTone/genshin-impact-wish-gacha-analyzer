// test/state/settings_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('初始狀態 = defaults', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 等 build 內 _bootstrap 完成
    await container.read(settingsProvider.notifier).waitForLoad();
    final s = container.read(settingsProvider);
    expect(s.themeMode, AppThemeMode.system);
    expect(s.locale, const SystemLanguage());
  });

  test('setThemeMode(dark) 後 state 與 prefs 同步', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container
        .read(settingsProvider.notifier)
        .setThemeMode(AppThemeMode.dark);

    expect(container.read(settingsProvider).themeMode, AppThemeMode.dark);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.themeMode, AppThemeMode.dark);
  });

  test('themeModeFlutter 將 system 對應到 ThemeMode.system', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    expect(container.read(themeModeProvider), ThemeMode.system);

    await container
        .read(settingsProvider.notifier)
        .setThemeMode(AppThemeMode.light);
    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  test('setLastActiveUid 寫入 state 與 prefs', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(settingsProvider.notifier).setLastActiveUid('UID1');
    expect(container.read(settingsProvider).lastActiveUid, 'UID1');
    final reloaded = await SettingsStorage.load();
    expect(reloaded.lastActiveUid, 'UID1');
  });

  test('setLastActiveUid(null) 清掉 state 與 prefs', () async {
    SharedPreferences.setMockInitialValues({'pref.lastActiveUid': 'UID1'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    expect(container.read(settingsProvider).lastActiveUid, 'UID1');

    await container.read(settingsProvider.notifier).setLastActiveUid(null);
    expect(container.read(settingsProvider).lastActiveUid, isNull);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.lastActiveUid, isNull);
  });

  test('setUidAlias 新增與覆蓋', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(settingsProvider.notifier).setUidAlias('A', '主帳');
    expect(container.read(settingsProvider).uidAliases, {'A': '主帳'});

    await container.read(settingsProvider.notifier).setUidAlias('A', '新名字');
    expect(container.read(settingsProvider).uidAliases, {'A': '新名字'});
  });

  test('setUidAlias trim 後為空字串 → 移除', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    await container.read(settingsProvider.notifier).setUidAlias('A', '主帳');

    await container.read(settingsProvider.notifier).setUidAlias('A', '   ');
    expect(container.read(settingsProvider).uidAliases, isEmpty);

    await container.read(settingsProvider.notifier).setUidAlias('A', '主帳');
    await container.read(settingsProvider.notifier).setUidAlias('A', null);
    expect(container.read(settingsProvider).uidAliases, isEmpty);
  });

  test('setUidOrder 寫入並持久化', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(settingsProvider.notifier).setUidOrder([
      'C',
      'A',
      'B',
    ]);
    expect(container.read(settingsProvider).uidOrder, ['C', 'A', 'B']);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.uidOrder, ['C', 'A', 'B']);
  });

  test('removeUidFromSettings 同時清 alias 與 order，不動 lastActiveUid', () async {
    SharedPreferences.setMockInitialValues({
      'pref.lastActiveUid': 'A',
      'pref.uidAliases': '{"A":"主帳","B":"小號"}',
      'pref.uidOrder': '["B","A","C"]',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(settingsProvider.notifier).removeUidFromSettings('A');
    final s = container.read(settingsProvider);
    expect(s.uidAliases, {'B': '小號'});
    expect(s.uidOrder, ['B', 'C']);
    expect(s.lastActiveUid, 'A'); // 不動
  });

  test('clearAllUidPreferences 一次清三個欄位', () async {
    SharedPreferences.setMockInitialValues({
      'pref.lastActiveUid': 'A',
      'pref.uidAliases': '{"A":"主帳"}',
      'pref.uidOrder': '["A","B"]',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(settingsProvider.notifier).clearAllUidPreferences();
    final s = container.read(settingsProvider);
    expect(s.lastActiveUid, isNull);
    expect(s.uidAliases, isEmpty);
    expect(s.uidOrder, isEmpty);
  });

  test('applyImportedPreferences updates aliases + uidOrder + lastActiveUid '
      'and persists once', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container
        .read(settingsProvider.notifier)
        .applyImportedPreferences(
          aliases: const {'A': '主號', 'C': '小號'},
          uidOrder: const ['A', 'C', 'B'],
          lastActiveUid: 'A',
        );

    final state = container.read(settingsProvider);
    expect(state.uidAliases, {'A': '主號', 'C': '小號'});
    expect(state.uidOrder, ['A', 'C', 'B']);
    expect(state.lastActiveUid, 'A');

    final reloaded = await SettingsStorage.load();
    expect(reloaded.uidAliases, {'A': '主號', 'C': '小號'});
    expect(reloaded.uidOrder, ['A', 'C', 'B']);
    expect(reloaded.lastActiveUid, 'A');
  });

  test('applyImportedPreferences with null lastActiveUid clears it', () async {
    SharedPreferences.setMockInitialValues({'pref.lastActiveUid': 'OLD'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container
        .read(settingsProvider.notifier)
        .applyImportedPreferences(
          aliases: const {},
          uidOrder: const [],
          lastActiveUid: null,
        );

    expect(container.read(settingsProvider).lastActiveUid, isNull);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.lastActiveUid, isNull);
  });

  test('setSkippedReleaseTag 寫入 state 與 prefs', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container
        .read(settingsProvider.notifier)
        .setSkippedReleaseTag('v1.2.0');
    expect(container.read(settingsProvider).skippedReleaseTag, 'v1.2.0');
    final reloaded = await SettingsStorage.load();
    expect(reloaded.skippedReleaseTag, 'v1.2.0');
  });

  test('setSkippedReleaseTag(null) 清掉 state 與 prefs', () async {
    SharedPreferences.setMockInitialValues({
      'pref.skippedReleaseTag': 'v1.2.0',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    expect(container.read(settingsProvider).skippedReleaseTag, 'v1.2.0');

    await container.read(settingsProvider.notifier).setSkippedReleaseTag(null);
    expect(container.read(settingsProvider).skippedReleaseTag, isNull);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.skippedReleaseTag, isNull);
  });

  group('logLevel', () {
    test('setLogLevel persists and applies to Logger.root', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(settingsProvider.notifier).waitForLoad();
      expect(Logger.root.level, equals(Level.INFO));

      await container.read(settingsProvider.notifier).setLogLevel('WARNING');
      expect(Logger.root.level, equals(Level.WARNING));
      expect(container.read(settingsProvider).logLevel, equals('WARNING'));

      // Simulate fresh process — manually reset root level, reload container
      Logger.root.level = Level.INFO;
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      await container2.read(settingsProvider.notifier).waitForLoad();
      expect(Logger.root.level, equals(Level.WARNING));
    });

    tearDown(() {
      Logger.root.level = Level.INFO;
      Logger.root.clearListeners();
    });
  });
}
