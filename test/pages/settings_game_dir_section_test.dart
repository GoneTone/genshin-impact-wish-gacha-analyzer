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
import 'package:genshin_impact_wish_gacha_analyzer/services/game_dir_locator.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import '../helpers/no_game_dir.dart';

/// 空 [GachaCapture] 替身，避免測試啟動真實 MITM session。
class _NullCapture implements GachaCapture {
  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(null), cancel: () async {});
}

/// 路徑含 `bad` 視為無效、含 `stale` 的設定值失效的 locator 替身。
class _FakeLocator extends GameDirLocator {
  /// 建立替身；[location] 為設定值失效或未設定時 `locate` 的回傳。
  _FakeLocator(this.location);

  /// 設定值失效或未設定時 `locate` 回傳的結果。
  final GameDirLocation? location;

  @override
  Future<GameDirLocation?> locate({String? settingDir}) async =>
      settingDir != null && !settingDir.contains('stale')
      ? GameDirLocation(settingDir, GameDirSource.setting)
      : location;

  @override
  Future<String?> normalize(String picked) async =>
      picked.contains('bad') ? null : picked;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('settings_game_dir_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 以 [predicate] 輪詢等待（最多 5 秒），每輪推進一次 frame。
  Future<void> waitFor(WidgetTester tester, bool Function() predicate) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!predicate() && DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(predicate(), isTrue);
  }

  /// 等待畫面出現含 [text] 的文字。
  Future<void> waitForText(WidgetTester tester, Finder finder) =>
      waitFor(tester, () => finder.evaluate().isNotEmpty);

  /// 啟動 SettingsPage；[locator] 預設為找不到遊戲資料夾。
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    GameDirLocator? locator,
    String? settingDir,
    Future<String?> Function()? pickDirectory,
    Size size = const Size(1000, 2000),
    double textScale = 1.0,
  }) async {
    if (settingDir != null) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pref.gameDir': settingDir,
      });
    }
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = ProviderContainer(
        overrides: [
          gameDirLocatorProvider.overrideWithValue(
            locator ??
                (settingDir != null ? _FakeLocator(null) : NoGameDirLocator()),
          ),
          gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
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
    });
    addTearDown(container.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: buildDarkTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(body: SettingsPage(pickGameDir: pickDirectory)),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('shows manual setting with path and clear button', (
    tester,
  ) async {
    final container = await pump(tester, settingDir: r'D:\Games\Genshin');
    await waitForText(tester, find.text(r'Set manually: D:\Games\Genshin'));
    final clear = find.byKey(const ValueKey('settings.gameDirClear'));
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await waitForText(tester, find.text('Game folder not found'));
    expect(container.read(settingsProvider).gameDir, isNull);
  });

  testWidgets('stale manual dir falls back to auto-detected path', (
    tester,
  ) async {
    await pump(
      tester,
      settingDir: r'D:\stale',
      locator: _FakeLocator(
        const GameDirLocation(r'C:\Genshin', GameDirSource.registry),
      ),
    );
    await waitForText(tester, find.text(r'Auto-detected: C:\Genshin'));
    expect(find.textContaining('stale'), findsNothing);
  });

  testWidgets('shows auto-detected path without clear button', (tester) async {
    await pump(
      tester,
      locator: _FakeLocator(
        const GameDirLocation(r'C:\Genshin', GameDirSource.outputLog),
      ),
    );
    await waitForText(tester, find.text(r'Auto-detected: C:\Genshin'));
    expect(find.byKey(const ValueKey('settings.gameDirClear')), findsNothing);
  });

  testWidgets('choose saves picked dir; invalid shows snack bar', (
    tester,
  ) async {
    String? next;
    final container = await pump(
      tester,
      locator: _FakeLocator(null),
      pickDirectory: () async => next,
    );
    final choose = find.byKey(const ValueKey('settings.gameDirChoose'));
    await tester.ensureVisible(choose);
    await tester.pump();

    next = r'D:\bad';
    await tester.tap(choose);
    await waitForText(
      tester,
      find.textContaining('was not found in this folder'),
    );
    expect(container.read(settingsProvider).gameDir, isNull);

    next = r'D:\good';
    await tester.tap(choose);
    await waitForText(tester, find.text(r'Set manually: D:\good'));
    expect(container.read(settingsProvider).gameDir, r'D:\good');
  });

  testWidgets('does not overflow at 360 px width and 1.3x text scale', (
    tester,
  ) async {
    // 設定頁其他區塊在窄寬度另有既存 overflow，這裡只收集並檢查遊戲資料夾區塊。
    final errors = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.toString());
    await pump(
      tester,
      settingDir: r'D:\' + 'VeryLongFolderName' * 12 + r'\Genshin',
      size: const Size(360, 2000),
      textScale: 1.3,
    );
    await waitForText(tester, find.textContaining('Set manually'));
    FlutterError.onError = prev;
    expect(errors.where((e) => e.contains('settings.gameDir')), isEmpty);
    for (final f in [
      find.textContaining('Set manually'),
      find.byKey(const ValueKey('settings.gameDirChoose')),
      find.byKey(const ValueKey('settings.gameDirClear')),
    ]) {
      expect(tester.getRect(f).right, lessThanOrEqualTo(360));
    }
  });
}
