import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
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

/// 建立一個含指定 gallery 的 [HoYoWikiEntry]（預設 lang = en-us）。
HoYoWikiEntry _entryWith({
  required String iconUrl,
  required String picUrl,
  required List<HoYoWikiGalleryItem> list,
  String lang = 'en-us',
  String desc = '',
  List<String> tags = const [],
}) => HoYoWikiEntry(
  iconUrl: iconUrl,
  pageByLang: {
    lang: HoYoWikiPageData(
      gallery: HoYoWikiGalleryData(picUrl: picUrl, list: list),
      desc: desc,
      tags: tags,
    ),
  },
  fetchedAt: DateTime.utc(2026, 5, 26),
);

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
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
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
        fetched: const HoYoWikiEntryFetched(
          iconUrl: '',
          page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
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
          page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
      );
      expect(
        await checkContent(tester, _rec(name: 'X', gachaType: '301')),
        isFalse,
      );
    });

    testWidgets('icon file 存在 → true（gallery 可缺，武器路徑）', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });
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
    testWidgets('icon 存在（無 gallery）→ title row 有 icon Image + name', (
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
          page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });

      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));

      expect(find.byType(GachaItemDetailDialog), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
      // gallery null：title 1 張 icon + content Icon chip 1 張 icon (chip 列只一項自動隱藏)
      expect(
        find.descendant(
          of: find.byType(GachaItemDetailDialog),
          matching: find.byType(Image),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('icon 不存在 → dialog 只顯示 name，無 Image', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: '',
          page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
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
          page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });

      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));

      expect(tester.takeException(), isNull);
    });

    testWidgets('desc 為空字串 → title 區不渲染 desc Html', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });
      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));
      // gallery null + desc 空：整個 dialog 內無 Html widget。
      expect(find.byType(Html), findsNothing);
    });

    testWidgets('desc 帶 HTML → title 區渲染 Html 且文字可見', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          page: HoYoWikiPageData(
            gallery: null,
            desc: '<p>Hello desc</p>',
            tags: [],
          ),
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });
      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));
      expect(find.byType(Html), findsOneWidget);
      expect(find.textContaining('Hello desc'), findsOneWidget);
    });

    testWidgets('tags 3 個 → Wrap 內 3 個 Chip 顯示 label 文字', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          page: HoYoWikiPageData(
            gallery: null,
            desc: '',
            tags: ['Pyro', '4★', 'Polearm'],
          ),
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });
      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));
      expect(find.byType(Chip), findsNWidgets(3));
      expect(find.text('Pyro'), findsOneWidget);
      expect(find.text('4★'), findsOneWidget);
      expect(find.text('Polearm'), findsOneWidget);
    });

    testWidgets('tags 為空 list → Chip 不渲染', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });
      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));
      expect(find.byType(Chip), findsNothing);
    });
  });

  group('GachaItemTapTarget', () {
    testWidgets('clickable record → 點下去 dialog 出現', (tester) async {
      const picUrl = 'https://cdn.hoyolab.com/x_card.png';
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          page: HoYoWikiPageData(
            gallery: HoYoWikiGalleryData(picUrl: picUrl, list: const []),
            desc: '',
            tags: const [],
          ),
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
        final picFile = hoyowikiGalleryCacheFile(
          baseDir: tempDir,
          id: 'x1',
          url: picUrl,
        );
        await _touchFile(tempDir, picFile.uri.pathSegments.last);
      });

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

  group('GachaItemDetailDialog gallery', () {
    Future<void> seedEntry(
      String id,
      String name,
      String lang,
      HoYoWikiEntry entry,
    ) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.setSearch(name: name, lang: lang, id: id, menuId: 2);
      await notifier.mergeEntry(
        id: id,
        lang: lang,
        fetched: HoYoWikiEntryFetched(
          iconUrl: entry.iconUrl,
          page:
              entry.pageByLang[lang] ??
              const HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
      );
    }

    Future<void> pumpDialog(WidgetTester tester, GachaRecord record) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildDarkTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showGachaItemDetailDialog(ctx, record),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      // pump a few frames to let the dialog route and chip widgets build;
      // avoid pumpAndSettle because Image.file codec decode on fake files
      // may never fully settle in the test binding.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('chip 列順序：list → 卡片 → Icon', (tester) async {
      late File picFile;
      late File origFile;
      await tester.runAsync(() async {
        await _touchFile(tempDir, '12345_icon.png');
        picFile = hoyowikiGalleryCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/card.png',
        );
        await _touchFile(tempDir, picFile.uri.pathSegments.last);
        origFile = hoyowikiGalleryCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/orig.png',
        );
        await _touchFile(tempDir, origFile.uri.pathSegments.last);
        await seedEntry(
          '12345',
          'Hu Tao',
          'en-us',
          _entryWith(
            iconUrl: 'https://x/icon.png',
            picUrl: 'https://x/card.png',
            list: [
              HoYoWikiGalleryItem(
                id: 'a',
                key: 'Original',
                imgUrl: 'https://x/orig.png',
                imgDescHtml: '<p>Outfit</p>',
              ),
            ],
          ),
        );
      });

      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget); // app_en.arb galleryCardLabel
      expect(find.text('Icon'), findsOneWidget); // app_en.arb galleryIconLabel
      // 順序：ChoiceChip 在 widget tree 內的出現順序對應 chipEntries 順序
      final chipLabels = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((c) => (c.label as Text).data)
          .toList();
      expect(chipLabels, ['Original', 'Card', 'Icon']);
    });

    testWidgets('點切「卡片」chip → 圖片切到 pic', (tester) async {
      late File picFile;
      late File origFile;
      await tester.runAsync(() async {
        await _touchFile(tempDir, '12345_icon.png');
        picFile = hoyowikiGalleryCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/card.png',
        );
        await _touchFile(tempDir, picFile.uri.pathSegments.last);
        origFile = hoyowikiGalleryCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/orig.png',
        );
        await _touchFile(tempDir, origFile.uri.pathSegments.last);
        await seedEntry(
          '12345',
          'Hu Tao',
          'en-us',
          _entryWith(
            iconUrl: 'https://x/icon.png',
            picUrl: 'https://x/card.png',
            list: [
              HoYoWikiGalleryItem(
                id: 'a',
                key: 'Original',
                imgUrl: 'https://x/orig.png',
                imgDescHtml: '<p>Outfit</p>',
              ),
            ],
          ),
        );
      });

      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      // 預設第 0 張 = list[0] = orig
      var imgFinder = find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is FileImage &&
            (w.image as FileImage).file.path.endsWith(
              origFile.uri.pathSegments.last,
            ),
      );
      expect(imgFinder, findsOneWidget);

      // 切到「卡片」chip
      await tester.tap(find.text('Card'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      imgFinder = find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is FileImage &&
            (w.image as FileImage).file.path.endsWith(
              picFile.uri.pathSegments.last,
            ),
      );
      expect(imgFinder, findsOneWidget);
    });

    testWidgets('imgDesc 為空時整塊描述不繪', (tester) async {
      await tester.runAsync(() async {
        await _touchFile(tempDir, '12345_icon.png');
        final origFile = hoyowikiGalleryCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/orig.gif',
        );
        await _touchFile(tempDir, origFile.uri.pathSegments.last);
        await seedEntry(
          '12345',
          'Hu Tao',
          'en-us',
          _entryWith(
            iconUrl: 'https://x/icon.png',
            picUrl: '',
            list: [
              HoYoWikiGalleryItem(
                id: 'a',
                key: 'Idle',
                imgUrl: 'https://x/orig.gif',
                imgDescHtml: '',
              ),
            ],
          ),
        );
      });

      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      expect(find.byType(Html), findsNothing);
    });

    testWidgets('武器路徑：缺 gallery 仍可開 dialog，chip 列只一個 Icon 自動隱藏', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await _touchFile(tempDir, '12345_icon.png');
        await container
            .read(hoyowikiIndexProvider.notifier)
            .setSearch(name: 'Hu Tao', lang: 'en-us', id: '12345', menuId: 4);
        await container
            .read(hoyowikiIndexProvider.notifier)
            .mergeEntry(
              id: '12345',
              lang: 'en-us',
              fetched: const HoYoWikiEntryFetched(
                iconUrl: 'https://x/icon.png',
                page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
              ),
            );
      });

      // 可點：hasHoYoWikiContent 為 true（只要有 icon）
      final got = await checkContent(
        tester,
        _rec(name: 'Hu Tao', gachaType: '301'),
      );
      expect(got, isTrue);

      // dialog 開：chip 列只有 1 個（Icon）→ 不顯示 chip 列
      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      expect(find.byType(ChoiceChip), findsNothing);
      // 但 content 仍有 icon 圖（chipEntries[0].file）
      expect(
        find.descendant(
          of: find.byType(GachaItemDetailDialog),
          matching: find.byType(Image),
        ),
        findsNWidgets(2), // title icon + content icon
      );
    });
  });
}
