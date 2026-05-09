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
    expect(s.locale, AppLocale.system);
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
}
