import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/game_dir_locator.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/game_dir_help_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/game_dir_picker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/update_progress_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可切換 progress 並計數 [restartWebCacheWatch] 的替身。
class _FakeRepo extends GachaRepository {
  /// 目前為止 [restartWebCacheWatch] 被呼叫的次數。
  static int restarts = 0;

  @override
  GachaState build() =>
      GachaState(progress: const WaitingForCapture(), isBootstrapping: false);

  /// 直接把 progress 設為 [p]（null 代表清除）。
  void setProgress(UpdateProgress? p) =>
      state = state.copyWith(progress: p, clearProgress: p == null);

  @override
  Future<void> restartWebCacheWatch() async => restarts++;

  @override
  Future<void> cancelCapture() async {}
}

/// 固定回傳 [result] 的 locator；[normalize] 沿用真實驗證。
class _FixedLocator extends GameDirLocator {
  /// 建立固定結果的 locator。
  _FixedLocator(this.result);

  /// [locate] 要回傳的結果。
  final GameDirLocation? result;

  @override
  Future<GameDirLocation?> locate({String? settingDir}) async => result;
}

/// 在 [root] 下建立含 `GenshinImpact_Data` 的有效遊戲資料夾。
Directory _makeGameDir(Directory root) {
  final dir = Directory('${root.path}\\Game')..createSync();
  Directory('${dir.path}\\GenshinImpact_Data').createSync();
  return dir;
}

/// 條件式等待：反覆 pump 並讓真實非同步（檔案 I/O）跑，直到 [done] 成立，最多 5 秒。
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not met in 5 s');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
}

void main() {
  late Directory tmp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _FakeRepo.restarts = 0;
    tmp = Directory.systemTemp.createTempSync('gamedir_test');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('pickAndSaveGameDir', () {
    /// 在 widget 樹內執行 [pickAndSaveGameDir]，回傳結果與 container。
    Future<(GameDirPickOutcome, ProviderContainer)> run(
      WidgetTester tester,
      Future<String?> Function() pick,
    ) async {
      late WidgetRef captured;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (_, ref, _) {
              captured = ref;
              return const SizedBox();
            },
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Consumer)),
      );
      final outcome = await tester.runAsync(() async {
        await container.read(settingsProvider.notifier).waitForLoad();
        return pickAndSaveGameDir(captured, pickDirectory: pick);
      });
      return (outcome!, container);
    }

    testWidgets('valid folder is saved normalized', (tester) async {
      final game = _makeGameDir(tmp);
      final (outcome, c) = await run(
        tester,
        () async => '${game.path}\\GenshinImpact_Data',
      );
      expect(outcome, GameDirPickOutcome.saved);
      expect(c.read(settingsProvider).gameDir, game.path);
    });

    testWidgets('empty folder is invalid and leaves settings unchanged', (
      tester,
    ) async {
      final (outcome, c) = await run(tester, () async => tmp.path);
      expect(outcome, GameDirPickOutcome.invalid);
      expect(c.read(settingsProvider).gameDir, isNull);
    });

    testWidgets('null pick is cancelled', (tester) async {
      final (outcome, _) = await run(tester, () async => null);
      expect(outcome, GameDirPickOutcome.cancelled);
    });

    testWidgets('folder chosen after the host unmounts is still saved', (
      tester,
    ) async {
      final game = _makeGameDir(tmp);
      late WidgetRef captured;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (_, ref, _) {
              captured = ref;
              return const SizedBox();
            },
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Consumer)),
      );
      final outcome = await tester.runAsync(() async {
        await container.read(settingsProvider.notifier).waitForLoad();
        final picked = Completer<String?>();
        final future = pickAndSaveGameDir(
          captured,
          pickDirectory: () => picked.future,
        );
        await tester.pumpWidget(const ProviderScope(child: SizedBox()));
        picked.complete(game.path);
        return future;
      });
      expect(outcome, GameDirPickOutcome.saved);
      expect(container.read(settingsProvider).gameDir, game.path);
    });
  });

  group('GameDirHelpDialog', () {
    /// 在 BASE 頁之上開啟進度視窗與說明視窗；[pick] 非 null 時以注入版直接開說明視窗。
    Future<ProviderContainer> open(
      WidgetTester tester, {
      GameDirLocation? located,
      Future<String?> Function()? pick,
      double width = 800,
    }) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext baseCtx;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gachaRepositoryProvider.overrideWith(_FakeRepo.new),
            gameDirLocatorProvider.overrideWithValue(_FixedLocator(located)),
          ],
          child: MaterialApp(
            theme: buildDarkTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh', 'Hant'),
            home: Builder(
              builder: (ctx) {
                baseCtx = ctx;
                return const Scaffold(body: Text('BASE'));
              },
            ),
          ),
        ),
      );
      showDialog<void>(
        context: baseCtx,
        builder: (_) => const UpdateProgressDialog(),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (pick == null) {
        await tester.tap(find.text('已經開啟祈願歷史記錄，卻一直沒有反應？'));
      } else {
        showGameDirHelpDialog(baseCtx, pickDirectory: pick);
      }
      await _pumpUntil(
        tester,
        () => find.text('偵測不到祈願歷史記錄').evaluate().isNotEmpty,
      );
      await _pumpUntil(
        tester,
        () => find.byType(LinearProgressIndicator).evaluate().length == 1,
      );
      return ProviderScope.containerOf(tester.element(find.text('BASE')));
    }

    testWidgets('not found shows choose button', (tester) async {
      await open(tester);
      expect(find.textContaining('找不到原神的遊戲資料夾'), findsOneWidget);
      expect(find.text('選擇遊戲資料夾'), findsOneWidget);
    });

    testWidgets('found shows path and rechoose button', (tester) async {
      await open(
        tester,
        located: const GameDirLocation(r'D:\Genshin', GameDirSource.outputLog),
      );
      expect(find.textContaining(r'D:\Genshin'), findsOneWidget);
      expect(find.text('重新選擇'), findsOneWidget);
    });

    testWidgets('long path wraps without overflow at 360 px wide', (
      tester,
    ) async {
      await open(
        tester,
        located: GameDirLocation(
          'D:\\${'VeryLongFolderName' * 8}\\Genshin Impact game',
          GameDirSource.registry,
        ),
        width: 360,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('重新選擇'), findsOneWidget);
    });

    testWidgets('help dialog closes when progress leaves waiting', (
      tester,
    ) async {
      final c = await open(tester);
      (c.read(gachaRepositoryProvider.notifier) as _FakeRepo).setProgress(
        const FetchingBanner(
          gachaType: '301',
          displayName: 'gachaTypeCharacter',
          pageIndex: 1,
          newRecordsSoFar: 0,
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('偵測不到祈願歷史記錄').evaluate().isEmpty,
      );
      expect(find.byType(UpdateProgressDialog), findsOneWidget);
    });

    testWidgets('both dialogs close when progress becomes null', (
      tester,
    ) async {
      final c = await open(tester);
      (c.read(gachaRepositoryProvider.notifier) as _FakeRepo).setProgress(null);
      await _pumpUntil(
        tester,
        () =>
            find.text('偵測不到祈願歷史記錄').evaluate().isEmpty &&
            find.byType(UpdateProgressDialog).evaluate().isEmpty,
      );
      expect(find.text('BASE'), findsOneWidget);
    });

    testWidgets('picking a folder shows reopen hint and restarts watch', (
      tester,
    ) async {
      final game = _makeGameDir(tmp);
      final c = await open(tester, pick: () async => game.path);
      await tester.runAsync(c.read(settingsProvider.notifier).waitForLoad);
      await tester.tap(find.text('選擇遊戲資料夾'));
      await _pumpUntil(
        tester,
        () => find.textContaining('請回到遊戲').evaluate().isNotEmpty,
      );
      expect(_FakeRepo.restarts, 1);
    });
  });
}
