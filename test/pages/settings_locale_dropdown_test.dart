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
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import '../helpers/no_game_dir.dart';

/// 不攔截任何封包的測試替身，避免 [SettingsPage] bootstrap 觸發真實 capture。
class _NullCapture implements GachaCapture {
  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(null), cancel: () async {});
}

/// 建立並預熱 [ProviderContainer]（含所有 SettingsPage 所需 override）。
///
/// 必須在 [WidgetTester.runAsync] 裡呼叫，以跳出 FakeAsync 讓 File I/O 正常完成。
Future<ProviderContainer> _setupContainer(Directory tempDir) async {
  final container = ProviderContainer(
    overrides: [
      gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
      noGameDirOverride,
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
  await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return container;
}

/// 將 [SettingsPage] 包進 [MaterialApp] 與 [UncontrolledProviderScope]，套用 i18n delegates 與英文語系。
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
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('settings_locale_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  // Android 系統設定「應用程式語言」改了會同步回 App 設定，設定頁開著時選單也要跟著變。
  testWidgets('language dropdown follows a change made outside the page', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _setupContainer(tempDir);
    });
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    final dropdown = find.byType(DropdownButtonFormField<LanguagePreference>);
    expect(
      find.descendant(of: dropdown, matching: find.text('Follow system')),
      findsOneWidget,
    );

    await tester.runAsync(
      () => container
          .read(settingsProvider.notifier)
          .setLocale(const LocaleLanguage('ja')),
    );
    await tester.pump();

    expect(
      find.descendant(of: dropdown, matching: find.text('日本語')),
      findsOneWidget,
    );
  });

  /// 收合時只建構已選的那項：全部語言名稱都排版會讓打開設定頁卡一下（要載入多種文字的字型）。
  Future<void> expectOnlySelectedLabel<T>(
    WidgetTester tester, {
    required String selected,
    required String other,
    required String pick,
  }) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _setupContainer(tempDir);
    });
    addTearDown(container.dispose);
    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final dropdown = find.byType(DropdownButtonFormField<T>);
    await tester.scrollUntilVisible(
      dropdown,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    Finder label(String text) => find.descendant(
      of: dropdown,
      matching: find.text(text, skipOffstage: false),
      skipOffstage: false,
    );
    expect(label(selected), findsOneWidget);
    expect(label(other), findsNothing);

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(find.text(other), findsWidgets);
    await tester.tap(find.text(pick).last);
    await tester.pumpAndSettle();

    expect(label(pick), findsOneWidget);
    expect(label(selected), findsNothing);
  }

  testWidgets('collapsed UI language dropdown builds only the selected name', (
    tester,
  ) async {
    await expectOnlySelectedLabel<LanguagePreference>(
      tester,
      selected: 'Follow system',
      other: 'English',
      pick: '日本語',
    );
  });

  testWidgets(
    'collapsed data language dropdown builds only the selected name',
    (tester) async {
      await expectOnlySelectedLabel<String?>(
        tester,
        selected: 'Not set (no conversion)',
        other: 'English',
        pick: '日本語',
      );
    },
  );
}
