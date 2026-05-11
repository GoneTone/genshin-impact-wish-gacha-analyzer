// test/state/settings_test.dart
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
}
