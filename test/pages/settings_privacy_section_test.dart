import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/settings_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

/// 空 [GachaCapture] 替身，避免測試啟動真實 MITM session。
class _NullCapture implements GachaCapture {
  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(null), cancel: () async {});
}

/// 啟動測試用 [ProviderContainer]，覆寫 SettingsPage 所需依賴並完成 bootstrap。
Future<ProviderContainer> _setupContainer({
  required GachaStorage storage,
  required Directory tempDir,
}) async {
  final container = ProviderContainer(
    overrides: [
      gachaStorageProvider.overrideWithValue(storage),
      gachaCaptureProvider.overrideWithValue(_NullCapture()),
      cancellableHttpClientFactoryProvider.overrideWithValue(
        () => CancellableHttpClient(
          client: MockClient((_) async => http.Response('{}', 200)),
          cancel: () {},
        ),
      ),
      hoyowikiIndexStorageProvider.overrideWithValue(
        HoYoWikiIndexStorage(tempDir),
      ),
      hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      appVersionProvider.overrideWithValue('0.0.0-test'),
    ],
  );
  await container.read(settingsProvider.notifier).waitForLoad();
  container.read(gachaRepositoryProvider);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return container;
}

/// 將 [SettingsPage] 包進 [MaterialApp] 與 [UncontrolledProviderScope]，
/// 套用測試所需的 i18n delegates 與英文語系。
Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: buildDarkTheme(),
    home: const Scaffold(body: SettingsPage()),
  ),
);

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('settings_privacy_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 啟動 container 與 SettingsPage，回傳 container 供測試讀取 settingsProvider。
  Future<ProviderContainer> pumpSettingsPage(WidgetTester tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _setupContainer(
        storage: GachaStorage(tempDir),
        tempDir: tempDir,
      );
    });
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return container;
  }

  testWidgets('Privacy section title renders', (tester) async {
    await pumpSettingsPage(tester);
    expect(find.text('Privacy'), findsOneWidget);
  });

  testWidgets('Privacy switch reflects default false', (tester) async {
    await pumpSettingsPage(tester);
    final sw = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('settings.maskUidInUiSwitch')),
    );
    expect(sw.value, false);
  });

  testWidgets('Toggling switch calls setMaskUidInUi(true)', (tester) async {
    final container = await pumpSettingsPage(tester);
    expect(container.read(settingsProvider).maskUidInUi, false);

    final switchFinder = find.byKey(
      const ValueKey('settings.maskUidInUiSwitch'),
    );
    await tester.ensureVisible(switchFinder);
    await tester.pump();
    await tester.tap(switchFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(settingsProvider).maskUidInUi, true);
  });

  testWidgets('Section sits between Language and Data Management', (
    tester,
  ) async {
    await pumpSettingsPage(tester);
    final languageY = tester.getTopLeft(find.text('Language')).dy;
    final privacyY = tester.getTopLeft(find.text('Privacy')).dy;
    final dataManagementY = tester.getTopLeft(find.text('Data management')).dy;
    expect(languageY, lessThan(privacyY));
    expect(privacyY, lessThan(dataManagementY));
  });
}
