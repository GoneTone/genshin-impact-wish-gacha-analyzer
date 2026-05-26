import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';

GachaRecord _rec({
  required String name,
  required String gachaType,
  String lang = 'en-us',
  int rankType = 5,
}) => GachaRecord(
  id: '1',
  uid: '801057625',
  gachaType: gachaType,
  name: name,
  itemType: 'Character',
  rankType: rankType,
  time: DateTime(2026, 5, 24),
  lang: lang,
);

/// 在 [dir] 內建立一個指定路徑的假圖檔（內容隨意，僅供 existsSync 命中）。
Future<File> _touchFile(Directory dir, String relative) async {
  final f = File('${dir.path}/$relative');
  await f.create(recursive: true);
  await f.writeAsBytes([0x89, 0x50, 0x4E, 0x47]); // PNG magic, 4 bytes
  return f;
}

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gacha_item_detail_test_');
    container = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      ],
    );
    addTearDown(container.dispose);
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  /// 把 hasHoYoWikiContent 包成 widget context 內可呼叫的 helper。
  Future<bool> checkContent(WidgetTester tester, GachaRecord r) async {
    bool? out;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            out = hasHoYoWikiContent(ref, r);
            return const SizedBox();
          },
        ),
      ),
    );
    return out!;
  }

  /// 以 [tester.runAsync] 包裝 disk I/O：設定 search + entry，
  /// 讓 file-based Future 在 testWidgets 內能真正執行到完成。
  Future<void> seedIndex(
    WidgetTester tester,
    HoYoWikiIndexNotifier notifier, {
    required String name,
    required String id,
    required HoYoWikiEntryFetched fetched,
  }) => tester.runAsync(
    () => notifier
        .setSearch(name: name, lang: 'en-us', id: id, menuId: 2)
        .then(
          (_) => notifier.mergeEntry(id: id, lang: 'en-us', fetched: fetched),
        ),
  );

  group('hasHoYoWikiContent', () {
    testWidgets('gachaType 2000 (頌願) → false', (tester) async {
      expect(
        await checkContent(tester, _rec(name: 'Ode', gachaType: '2000')),
        isFalse,
      );
    });

    testWidgets('gachaType 1000 (頌願) → false', (tester) async {
      expect(
        await checkContent(tester, _rec(name: 'Ode', gachaType: '1000')),
        isFalse,
      );
    });

    testWidgets('lookup miss → false', (tester) async {
      expect(
        await checkContent(tester, _rec(name: 'Unknown', gachaType: '301')),
        isFalse,
      );
    });

    testWidgets('entry iconUrl 空 → false', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(iconUrl: '', gallery: null),
      );
      expect(
        await checkContent(tester, _rec(name: 'X', gachaType: '301')),
        isFalse,
      );
    });

    testWidgets('icon URL 存在但 cache file 未到 → false', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          gallery: null,
        ),
      );
      expect(
        await checkContent(tester, _rec(name: 'X', gachaType: '301')),
        isFalse,
      );
    });

    testWidgets('icon file 存在 → true', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          gallery: null,
        ),
      );
      await tester.runAsync(() => _touchFile(tempDir, 'x1_icon.png'));
      expect(
        await checkContent(tester, _rec(name: 'X', gachaType: '301')),
        isTrue,
      );
    });
  });

  Future<void> pumpDialog(WidgetTester tester, GachaRecord record) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      ),
    );
    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      showDialog<void>(
        context: navigatorState.context,
        builder: (_) => GachaItemDetailDialog(record: record),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('GachaItemDetailDialog 渲染', () {
    testWidgets('icon 存在 → title row 有 icon Image + name，content 為空殼', (
      tester,
    ) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          gallery: null,
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });

      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));

      expect(find.byType(GachaItemDetailDialog), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
      // 過渡版本：只有 icon（content 是 SizedBox.shrink()）
      expect(
        find.descendant(
          of: find.byType(GachaItemDetailDialog),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
    });

    testWidgets('icon 不存在 → dialog 只顯示 name，無 Image', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(iconUrl: '', gallery: null),
      );

      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));

      expect(find.byType(GachaItemDetailDialog), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GachaItemDetailDialog),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
    });

    testWidgets('小視窗 (640x480) 不會 vertical overflow', (tester) async {
      tester.view.physicalSize = const Size(640, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          gallery: null,
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });

      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));

      expect(tester.takeException(), isNull);
    });
  });

  group('GachaItemTapTarget', () {
    testWidgets('clickable record → 點下去 dialog 出現', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          gallery: null,
        ),
      );
      await tester.runAsync(() => _touchFile(tempDir, 'x1_icon.png'));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildDarkTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: GachaItemTapTarget(
                record: _rec(name: 'X', gachaType: '301'),
                child: const Text('tap-me'),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(GachaItemDetailDialog), findsNothing);
      await tester.tap(find.text('tap-me'));
      await tester.pumpAndSettle();
      expect(find.byType(GachaItemDetailDialog), findsOneWidget);
    });

    testWidgets('頌願 → 點下去不出 dialog，passthrough 無 MouseRegion click cursor', (
      tester,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: GachaItemTapTarget(
                record: _rec(name: 'Ode', gachaType: '2000'),
                child: const Text('tap-me'),
              ),
            ),
          ),
        ),
      );

      final mouseRegions = tester.widgetList<MouseRegion>(
        find.descendant(
          of: find.byType(GachaItemTapTarget),
          matching: find.byType(MouseRegion),
        ),
      );
      expect(
        mouseRegions.any((m) => m.cursor == SystemMouseCursors.click),
        isFalse,
      );

      await tester.tap(find.text('tap-me'));
      await tester.pumpAndSettle();
      expect(find.byType(GachaItemDetailDialog), findsNothing);
    });

    testWidgets('lookup miss → passthrough，點下去不出 dialog', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: GachaItemTapTarget(
                record: _rec(name: 'Unknown', gachaType: '301'),
                child: const Text('tap-me'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('tap-me'));
      await tester.pumpAndSettle();
      expect(find.byType(GachaItemDetailDialog), findsNothing);
    });
  });
}
