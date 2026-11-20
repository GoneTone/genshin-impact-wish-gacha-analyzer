import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_access.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/item_image_save.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/zoomable_image_overlay.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/scroll/scroll_affordance.dart';

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

/// 雙欄版面左欄（資訊欄）的 key。
const detailsColumnKey = ValueKey('detail-info-column');

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

  /// 測試內設成 true 即走 Android 分支（`isAndroidProvider` 首次讀取時才取值）。
  var android = false;

  setUp(() async {
    android = false;
    tempDir = await Directory.systemTemp.createTemp('gacha_item_detail_test_');
    container = ProviderContainer(
      overrides: [
        isAndroidProvider.overrideWith((ref) => android),
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
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

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

    testWidgets('actions 區顯示「前往 HoYoWiki」按鈕，label 與 icon 正確', (tester) async {
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
      final l = AppLocalizations.of(
        tester.element(find.byType(GachaItemDetailDialog)),
      )!;
      expect(find.text(l.actionViewOnHoYoWiki), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      final btn = tester.widget<TextButton>(
        find.ancestor(
          of: find.text(l.actionViewOnHoYoWiki),
          matching: find.byType(TextButton),
        ),
      );
      expect(btn.onPressed, isNotNull);
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

    Future<void> pumpDialog(
      WidgetTester tester,
      GachaRecord record, {
      ThemeData? theme,
    }) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: theme ?? buildDarkTheme(),
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

    testWidgets('點 gallery 主圖 → 開啟 ZoomableImageOverlay', (tester) async {
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
                imgDescHtml: '',
              ),
            ],
          ),
        );
      });

      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      final mainImage = find.descendant(
        of: find.byType(GachaItemDetailDialog),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is FileImage &&
              (w.image as FileImage).file.path.endsWith(
                origFile.uri.pathSegments.last,
              ),
        ),
      );
      expect(mainImage, findsOneWidget);

      await tester.tap(mainImage);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ZoomableImageOverlay), findsOneWidget);
      final overlayImg = tester.widget<Image>(
        find.descendant(
          of: find.byType(ZoomableImageOverlay),
          matching: find.byType(Image),
        ),
      );
      expect(overlayImg.image, isA<FileImage>());
      expect((overlayImg.image as FileImage).file.path, origFile.path);
    });

    testWidgets('切到「卡片」chip 後點主圖 → overlay 開的是 pic 檔', (tester) async {
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
                imgDescHtml: '',
              ),
            ],
          ),
        );
      });

      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      await tester.tap(find.text('Card'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final mainImage = find.descendant(
        of: find.byType(GachaItemDetailDialog),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is FileImage &&
              (w.image as FileImage).file.path.endsWith(
                picFile.uri.pathSegments.last,
              ),
        ),
      );
      await tester.tap(mainImage);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final overlayImg = tester.widget<Image>(
        find.descendant(
          of: find.byType(ZoomableImageOverlay),
          matching: find.byType(Image),
        ),
      );
      expect((overlayImg.image as FileImage).file.path, picFile.path);
    });

    testWidgets('gallery 主圖 wrapper 有 click cursor', (tester) async {
      await tester.runAsync(() async {
        await _touchFile(tempDir, '12345_icon.png');
        final origFile = hoyowikiGalleryCacheFile(
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
            picUrl: '',
            list: [
              HoYoWikiGalleryItem(
                id: 'a',
                key: 'Original',
                imgUrl: 'https://x/orig.png',
                imgDescHtml: '',
              ),
            ],
          ),
        );
      });

      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      final mouseRegions = tester.widgetList<MouseRegion>(
        find.descendant(
          of: find.byType(GachaItemDetailDialog),
          matching: find.byType(MouseRegion),
        ),
      );
      expect(
        mouseRegions.any((m) => m.cursor == SystemMouseCursors.click),
        isTrue,
      );
    });

    /// 種一筆名為 [name]、含原圖（附三行說明）與 icon 的角色，回傳原圖的快取檔。
    Future<File> seedWithGallery(
      WidgetTester tester, {
      String name = 'Hu Tao',
      String desc = '',
      List<String> tags = const [],
      String imgDescHtml = '<p>Outfit</p><p>Line two</p><p>Line three</p>',
    }) async {
      final origFile = hoyowikiGalleryCacheFile(
        baseDir: tempDir,
        id: '12345',
        url: 'https://x/orig.png',
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, '12345_icon.png');
        await _touchFile(tempDir, origFile.uri.pathSegments.last);
        await seedEntry(
          '12345',
          name,
          'en-us',
          _entryWith(
            iconUrl: 'https://x/icon.png',
            picUrl: '',
            desc: desc,
            tags: tags,
            list: [
              HoYoWikiGalleryItem(
                id: 'a',
                key: 'Original',
                imgUrl: 'https://x/orig.png',
                imgDescHtml: imgDescHtml,
              ),
            ],
          ),
        );
      });
      return origFile;
    }

    testWidgets('mouse long press on the image does not open the menu', (
      tester,
    ) async {
      final origFile = await seedWithGallery(tester);
      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      final l = AppLocalizations.of(
        tester.element(find.byType(GachaItemDetailDialog)),
      )!;
      await tester.longPressAt(
        tester.getCenter(find.byKey(ValueKey(origFile.path))),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(l.actionSaveImage), findsNothing);
    });

    testWidgets('long press on the image opens the image menu', (tester) async {
      final origFile = await seedWithGallery(tester);
      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      final l = AppLocalizations.of(
        tester.element(find.byType(GachaItemDetailDialog)),
      )!;
      await tester.longPress(find.byKey(ValueKey(origFile.path)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(l.actionSaveImage), findsOneWidget);
    });

    /// 開啟 ready 圖的溢出選單。
    Future<void> openImageMenu(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.byType(GachaItemDetailDialog),
          matching: find.byIcon(Icons.more_vert),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// 取詳情 dialog 所在 context 的 [AppLocalizations]。
    AppLocalizations loc(WidgetTester tester) => AppLocalizations.of(
      tester.element(find.byType(GachaItemDetailDialog)),
    )!;

    /// 開 [name] 的詳情、選單點 [label] 選出的項目，並等動作跑完。
    Future<void> runMenuAction(
      WidgetTester tester,
      String Function(AppLocalizations l) label, {
      String name = 'Hu Tao',
    }) async {
      await pumpDialog(tester, _rec(name: name, gachaType: '301'));
      await openImageMenu(tester);
      await tester.tap(find.text(label(loc(tester))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// 結束前 flush toast 的停留計時器與淡出動畫。
    Future<void> flushToast(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// 讓圖片準備直接回傳假 bytes（[isGif] 決定當成 GIF 或 PNG），並在測試結束時重設 seam。
    void stubPrepared({bool isGif = false}) {
      addTearDown(resetItemImageSaveSeams);
      addTearDown(resetFileAccessSeams);
      prepareOutputImageOverride = (_) async =>
          OutputImage(bytes: Uint8List.fromList([1, 2, 3, 4]), isGif: isGif);
    }

    testWidgets('item image menu offers share only on Android', (tester) async {
      android = true;
      await seedWithGallery(tester);
      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      await openImageMenu(tester);
      expect(find.text(loc(tester).actionShare), findsOneWidget);
    });

    testWidgets('item image menu hides share on desktop', (tester) async {
      await seedWithGallery(tester);
      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      await openImageMenu(tester);
      expect(find.text(loc(tester).actionShare), findsNothing);
      expect(find.text(loc(tester).actionRefetchImage), findsOneWidget);
    });

    testWidgets('sharing an item image sends a png named after the item', (
      tester,
    ) async {
      stubPrepared();
      String? name;
      String? mime;
      fileSharer = (bytes, fileName, mimeType) async {
        name = fileName;
        mime = mimeType;
      };
      android = true;
      await seedWithGallery(tester);
      await runMenuAction(tester, (l) => l.actionShare);
      expect(name, 'Hu Tao_Original.png');
      expect(mime, 'image/png');
    });

    testWidgets('sharing a gif item image keeps it as a gif', (tester) async {
      stubPrepared(isGif: true);
      String? name;
      String? mime;
      fileSharer = (bytes, fileName, mimeType) async {
        name = fileName;
        mime = mimeType;
      };
      android = true;
      await seedWithGallery(tester);
      await runMenuAction(tester, (l) => l.actionShare);
      expect(name, 'Hu Tao_Original.gif');
      expect(mime, 'image/gif');
    });

    testWidgets('item image share failure shows shareFailed', (tester) async {
      stubPrepared();
      fileSharer = (_, _, _) async => throw Exception('boom');
      android = true;
      await seedWithGallery(tester);
      await runMenuAction(tester, (l) => l.actionShare);
      expect(find.text(loc(tester).shareFailed), findsOneWidget);
      await flushToast(tester);
    });

    testWidgets('sharing successfully shows no toast', (tester) async {
      stubPrepared();
      var shared = false;
      fileSharer = (_, _, _) async {
        shared = true;
      };
      android = true;
      await seedWithGallery(tester);
      await runMenuAction(tester, (l) => l.actionShare);
      expect(shared, isTrue);
      final l = loc(tester);
      for (final message in [
        l.shareFailed,
        l.imageCopied,
        l.imageCopyFailed,
        l.imageSaveFailed,
      ]) {
        expect(find.text(message), findsNothing);
      }
    });

    testWidgets('Windows save toast shows the full path and logs the outcome', (
      tester,
    ) async {
      stubPrepared();
      String? title;
      fileSaveDialog = (_, _, _, _, dialogTitle) async {
        title = dialogTitle;
        return r'C:\out\Hu Tao_Original.png';
      };
      final messages = <String>[];
      final sub = Logger.root.onRecord
          .where((r) => r.loggerName == 'gacha.hoyowiki.save')
          .listen((r) => messages.add(r.message));
      addTearDown(sub.cancel);
      await seedWithGallery(tester);
      await runMenuAction(tester, (l) => l.actionSaveImage);
      final l = loc(tester);
      expect(title, l.dialogSaveAsTitle);
      expect(
        find.text(l.imageSavedTo(r'C:\out\Hu Tao_Original.png')),
        findsOneWidget,
      );
      expect(messages, [
        'item image action=save name=Hu Tao_Original.png outcome=ok',
      ]);
      await flushToast(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('Android save toast shows only the file name', (tester) async {
      stubPrepared();
      fileSaveDialog = (_, _, _, _, _) async =>
          '/document/primary:Download/Hu Tao_Original.png';
      android = true;
      await seedWithGallery(tester);
      await runMenuAction(tester, (l) => l.actionSaveImage);
      expect(
        find.text(loc(tester).imageSavedTo('Hu Tao_Original.png')),
        findsOneWidget,
      );
      await flushToast(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('saving a gif item image asks for a .gif', (tester) async {
      stubPrepared(isGif: true);
      String? name;
      String? ext;
      String? mime;
      fileSaveDialog = (_, suggestedName, extension, mimeType, _) async {
        name = suggestedName;
        ext = extension;
        mime = mimeType;
        return null;
      };
      await seedWithGallery(tester);
      await runMenuAction(tester, (l) => l.actionSaveImage);
      expect(name, endsWith('.gif'));
      expect(ext, 'gif');
      expect(mime, 'image/gif');
    });

    testWidgets(
      'saving an image with illegal characters in its name passes a sanitized '
      'name',
      (tester) async {
        stubPrepared();
        String? name;
        fileSaveDialog = (_, suggestedName, _, _, _) async {
          name = suggestedName;
          return null;
        };
        await seedWithGallery(tester, name: 'A:B/C');
        await runMenuAction(tester, (l) => l.actionSaveImage, name: 'A:B/C');
        expect(name, 'A_B_C_Original.png');
        expect(name, isNot(matches(RegExp(r'[<>:"/\\|?*]'))));
      },
    );

    testWidgets('a failed image preparation toasts and logs the base name', (
      tester,
    ) async {
      addTearDown(resetItemImageSaveSeams);
      prepareOutputImageOverride = (_) async => null;
      final messages = <String>[];
      final sub = Logger.root.onRecord
          .where((r) => r.loggerName == 'gacha.hoyowiki.save')
          .listen((r) => messages.add(r.message));
      addTearDown(sub.cancel);
      await seedWithGallery(tester);
      await runMenuAction(tester, (l) => l.actionCopyImage);
      expect(find.text(loc(tester).imageCopyFailed), findsOneWidget);
      expect(
        messages.last,
        'item image action=copy name=Hu Tao_Original outcome=failed',
      );
      await flushToast(tester);
    });

    /// 把測試畫面設成 [size]（dpr 1），測試結束後還原。
    void setPhoneView(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    /// 以 [size] 的畫面開啟詳情（平台由 test variant 決定），回傳名稱與圖片的位置。
    Future<(Rect, Rect)> pumpAt(
      WidgetTester tester,
      Size size, {
      String desc = '',
      List<String> tags = const [],
    }) async {
      setPhoneView(tester, size);
      final origFile = await seedWithGallery(tester, desc: desc, tags: tags);
      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      expect(tester.takeException(), isNull);
      return (
        tester.getRect(find.text('Hu Tao')),
        tester.getRect(find.byKey(ValueKey(origFile.path))),
      );
    }

    testWidgets('phone landscape puts details and image side by side', (
      tester,
    ) async {
      final (name, image) = await pumpAt(tester, const Size(800, 360));
      expect(name.right, lessThan(image.left));
      expect((name.top - image.top).abs(), lessThan(100));
      expect(tester.getSize(find.byKey(detailsColumnKey)).width, 240);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('phone landscape keeps the image tall with its description '
        'in the left column', (tester) async {
      final (_, image) = await pumpAt(tester, const Size(800, 360));
      expect(image.height, greaterThanOrEqualTo(200));
      final desc = tester.getRect(find.textContaining('Outfit'));
      expect(desc.right, lessThan(image.left));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('phone portrait stacks details above the image', (
      tester,
    ) async {
      final (name, image) = await pumpAt(tester, const Size(360, 800));
      expect(name.bottom, lessThan(image.top));
      expect(find.byKey(detailsColumnKey), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('wide desktop window puts details and image side by side', (
      tester,
    ) async {
      final (name, image) = await pumpAt(tester, const Size(1280, 800));
      expect(name.right, lessThan(image.left));
      expect(tester.getSize(find.byKey(detailsColumnKey)).width, 320);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('desktop window under 1000 wide stays single column', (
      tester,
    ) async {
      final (name, image) = await pumpAt(tester, const Size(900, 700));
      expect(name.bottom, lessThan(image.top));
      expect(find.byKey(detailsColumnKey), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('two-column detail keeps HoYoWiki tags, skins and the '
        'HoYoWiki link', (tester) async {
      await pumpAt(
        tester,
        const Size(1280, 800),
        desc: '<p>Intro text</p>',
        tags: ['Pyro', 'Polearm'],
      );
      final column = find.byKey(detailsColumnKey);
      for (final text in ['Hu Tao', 'Intro text', 'Pyro', 'Polearm']) {
        expect(
          find.descendant(of: column, matching: find.textContaining(text)),
          findsWidgets,
          reason: text,
        );
      }
      expect(
        find.descendant(of: column, matching: find.textContaining('Outfit')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: column, matching: find.byIcon(Icons.open_in_new)),
        findsOneWidget,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    group('close button', () {
      final close = find.byType(AppDialogCloseButton);

      /// [a] 與 [b] 在垂直方向有重疊（同一列）。
      bool sameRow(Rect a, Rect b) => a.top < b.bottom && b.top < a.bottom;

      /// 點 ✕ 後詳情應關閉。
      Future<void> tapClosesDialog(WidgetTester tester) async {
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(GachaItemDetailDialog), findsNothing);
      }

      testWidgets('phone portrait: at the right end of the header row', (
        tester,
      ) async {
        final (name, _) = await pumpAt(tester, const Size(360, 800));
        expect(close, findsOneWidget);
        final rect = tester.getRect(close);
        expect(sameRow(rect, name), isTrue);
        expect(rect.left, greaterThanOrEqualTo(name.right));
        expect(tester.getSize(close), const Size(44, 44));
        final icon = tester.getCenter(
          find.descendant(of: close, matching: find.byIcon(Icons.close)),
        );
        expect((icon.dy - name.center.dy).abs(), lessThanOrEqualTo(2));
        await tapClosesDialog(tester);
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));

      /// 圖片區（圖片最近的 [Expanded]）頂端與 ✕ 所在頂列底端的距離。
      double gapBelowClose(WidgetTester tester, Finder image) =>
          tester
              .getTopLeft(
                find.ancestor(of: image, matching: find.byType(Expanded)).first,
              )
              .dy -
          tester
              .getRect(
                find.ancestor(of: close, matching: find.byType(Row)).first,
              )
              .bottom;

      testWidgets('two columns with a chip bar: gap under the top row', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final origFile = await seedWithGallery(tester);
        await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
        expect(find.byType(ChoiceChip), findsWidgets);
        expect(
          gapBelowClose(tester, find.byKey(ValueKey(origFile.path))),
          closeTo(AppSpacing.m, 0.5),
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

      testWidgets('two columns, single image: X row without the extra gap', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final iconFile = hoyowikiIconCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/icon.png',
        );
        await tester.runAsync(() async {
          await _touchFile(tempDir, iconFile.uri.pathSegments.last);
          await seedEntry(
            '12345',
            'Hu Tao',
            'en-us',
            _entryWith(
              iconUrl: 'https://x/icon.png',
              picUrl: '',
              desc: '',
              tags: const [],
              list: const [],
            ),
          );
        });
        await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
        expect(find.byType(ChoiceChip), findsNothing);
        expect(close, findsOneWidget);
        expect(
          gapBelowClose(tester, find.byKey(ValueKey(iconFile.path))),
          closeTo(0, 0.5),
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

      for (final (label, size, platform) in [
        ('phone landscape', const Size(914, 411), TargetPlatform.android),
        ('desktop', const Size(1280, 800), TargetPlatform.windows),
      ]) {
        testWidgets('two columns: right of the chip bar arrow ($label)', (
          tester,
        ) async {
          final (_, image) = await pumpAt(tester, size);
          expect(close, findsOneWidget);
          final rect = tester.getRect(close);
          final arrow = tester.getRect(find.byTooltip('Next'));
          expect(sameRow(rect, arrow), isTrue);
          expect(rect.left, greaterThanOrEqualTo(arrow.right));
          expect(rect.bottom, lessThanOrEqualTo(image.top));
          expect(rect.width, greaterThanOrEqualTo(44));
          await tapClosesDialog(tester);
        }, variant: TargetPlatformVariant.only(platform));
      }
    });

    group('two-column details scroll as one region', () {
      /// 超過原本內層捲動上限的長簡介。
      final longIntro = '<p>${'A very long intro sentence. ' * 120}</p>';

      /// 簡介的 [Html]（左欄第一個 Html）。
      Finder intro() => find.byType(Html).first;

      /// 左欄底部的漸層提示。
      Finder bottomFade() => find.byWidgetPredicate(
        (w) => w is ScrollEdgeFade && w.side == ScrollSide.bottom,
      );

      testWidgets('dragging on the intro scrolls the whole column', (
        tester,
      ) async {
        await pumpAt(tester, const Size(1280, 800), desc: longIntro);
        final scrollables = find.ancestor(
          of: intro(),
          matching: find.byType(Scrollable),
        );
        expect(scrollables, findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(detailsColumnKey),
            matching: find.byType(Scrollable),
          ),
          findsOneWidget,
        );
        final introTop = tester.getRect(intro()).top;
        final link = find.byIcon(Icons.open_in_new);
        final linkTop = tester.getRect(link).top;

        await tester.dragFrom(
          tester.getTopLeft(intro()) + const Offset(40, 20),
          const Offset(0, -200),
        );
        await tester.pump();

        final position = tester.state<ScrollableState>(scrollables).position;
        expect(position.pixels, greaterThan(0));
        expect(tester.getRect(intro()).top, lessThan(introTop));
        expect(tester.getRect(link).top, linkTop);
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

      testWidgets('bottom fade shows until scrolled to the end', (
        tester,
      ) async {
        await pumpAt(tester, const Size(1280, 800), desc: longIntro);
        await tester.pump();
        expect(bottomFade(), findsOneWidget);
        final position = tester
            .state<ScrollableState>(
              find.ancestor(of: intro(), matching: find.byType(Scrollable)),
            )
            .position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        expect(bottomFade(), findsNothing);
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

      testWidgets('divider separates tags from the skin caption only', (
        tester,
      ) async {
        await pumpAt(tester, const Size(1280, 800), tags: ['Pyro']);
        final divider = find.descendant(
          of: find.byKey(detailsColumnKey),
          matching: find.byType(Divider),
        );
        expect(divider, findsOneWidget);
        expect(
          tester.getRect(find.text('Pyro')).bottom,
          lessThan(tester.getRect(divider).top),
        );
        expect(
          tester.getRect(divider).bottom,
          lessThan(tester.getRect(find.text('Outfit').first).top),
        );
        // 切到 Icon（無圖片說明）→ 分隔線一併消失。
        await tester.tap(find.byType(ChoiceChip).last);
        await tester.pump();
        expect(divider, findsNothing);
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

      /// 左欄往下捲的箭頭按鈕。
      Finder scrollDown() => find.byTooltip('Scroll down');

      /// 以左欄捲軸的 painter 在其實際尺寸上作畫的函式，供 `paints` 比對。
      void Function(Canvas) paintDetailsScrollbar(WidgetTester tester) {
        final finder = find.descendant(
          of: find.byKey(detailsColumnKey),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.foregroundPainter is ScrollbarPainter,
          ),
        );
        final painter = tester.widget<CustomPaint>(finder).foregroundPainter!;
        final size = tester.getSize(finder);
        return (canvas) => painter.paint(canvas, size);
      }

      /// 畫出不透明度大於 0 的捲軸 thumb（淡出時仍會以全透明色作畫）。
      final visibleThumb = paints
        ..something((_, args) => args.last is Paint && args.last.color.a > 0);

      for (final (name, size, platform) in [
        ('desktop', const Size(1280, 800), TargetPlatform.windows),
        ('phone landscape', const Size(914, 411), TargetPlatform.android),
      ]) {
        testWidgets('scrollbar thumb shows without interaction ($name)', (
          tester,
        ) async {
          await pumpAt(tester, size, desc: longIntro);
          await tester.pump(const Duration(milliseconds: 500));
          expect(paintDetailsScrollbar(tester), visibleThumb);
        }, variant: TargetPlatformVariant.only(platform));

        testWidgets('scroll-down chevron pages the column until the end '
            '($name)', (tester) async {
          await pumpAt(tester, size, desc: longIntro);
          await tester.pump();
          expect(scrollDown(), findsOneWidget);
          expect(tester.getSize(scrollDown()).width, greaterThanOrEqualTo(44));
          expect(tester.getSize(scrollDown()).height, greaterThanOrEqualTo(44));
          final position = tester
              .state<ScrollableState>(
                find.ancestor(of: intro(), matching: find.byType(Scrollable)),
              )
              .position;
          await tester.tap(scrollDown());
          await tester.pumpAndSettle();
          expect(position.pixels, closeTo(position.viewportDimension * 0.8, 1));
          position.jumpTo(position.maxScrollExtent);
          await tester.pump();
          expect(scrollDown(), findsNothing);
          expect(bottomFade(), findsNothing);
        }, variant: TargetPlatformVariant.only(platform));

        testWidgets('no scrollbar thumb or chevron when the column fits '
            '($name)', (tester) async {
          await pumpAt(tester, size, desc: '<p>Short</p>');
          await tester.pump(const Duration(milliseconds: 500));
          expect(scrollDown(), findsNothing);
          expect(paintDetailsScrollbar(tester), isNot(visibleThumb));
        }, variant: TargetPlatformVariant.only(platform));
      }

      testWidgets('no bottom fade when the column fits', (tester) async {
        await pumpAt(tester, const Size(1280, 800), desc: '<p>Short</p>');
        await tester.pump();
        expect(bottomFade(), findsNothing);
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

      testWidgets('phone portrait keeps the capped inner intro scroll', (
        tester,
      ) async {
        await pumpAt(tester, const Size(360, 800), desc: longIntro);
        final inner = find.ancestor(
          of: intro(),
          matching: find.byType(SingleChildScrollView),
        );
        expect(inner, findsOneWidget);
        expect(tester.getSize(inner).height, lessThanOrEqualTo(120));
        expect(tester.getSize(intro()).height, greaterThan(120));
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));

      testWidgets('phone portrait: long intro shows the scroll hint and the '
          'chevron pages it', (tester) async {
        await pumpAt(tester, const Size(360, 800), desc: longIntro);
        await tester.pump(const Duration(milliseconds: 500));
        expect(bottomFade(), findsOneWidget);
        expect(scrollDown(), findsOneWidget);
        final scrollbar = find.ancestor(
          of: intro(),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.foregroundPainter is ScrollbarPainter,
          ),
        );
        final painter = tester
            .widget<CustomPaint>(scrollbar)
            .foregroundPainter!;
        final size = tester.getSize(scrollbar);
        expect((Canvas c) => painter.paint(c, size), visibleThumb);
        final position = tester
            .state<ScrollableState>(
              find.ancestor(of: intro(), matching: find.byType(Scrollable)),
            )
            .position;
        await tester.tap(scrollDown());
        await tester.pumpAndSettle();
        expect(position.pixels, closeTo(position.viewportDimension * 0.8, 1));
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        expect(scrollDown(), findsNothing);
        expect(bottomFade(), findsNothing);
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));

      testWidgets('phone portrait: the skin caption is not capped and shows '
          'no scroll hint', (tester) async {
        await pumpAt(tester, const Size(360, 800), desc: '<p>Short</p>');
        await tester.pump();
        expect(bottomFade(), findsNothing);
        expect(scrollDown(), findsNothing);
        final caption = find.text('Outfit');
        expect(
          find.ancestor(of: caption, matching: find.byType(Scrollable)),
          findsNothing,
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));

      testWidgets('phone portrait: short intro keeps its own height, no hint', (
        tester,
      ) async {
        await pumpAt(tester, const Size(360, 800), desc: '<p>Short</p>');
        await tester.pump();
        expect(bottomFade(), findsNothing);
        expect(scrollDown(), findsNothing);
        final inner = find.ancestor(
          of: intro(),
          matching: find.byType(SingleChildScrollView),
        );
        expect(tester.getSize(inner).height, lessThan(60));
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));
    });

    group('swipe between images', () {
      /// 開啟「原圖＋Icon」兩張圖（[gif] 為 true 時中間多一張 GIF）的詳情，
      /// 回傳依 chip 順序排列的圖檔。
      Future<List<File>> openImages(
        WidgetTester tester, {
        bool gif = false,
        ThemeData? theme,
      }) async {
        final orig = hoyowikiGalleryCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/orig.png',
        );
        final anim = hoyowikiGalleryCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/anim.gif',
        );
        final icon = hoyowikiIconCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/icon.png',
        );
        await tester.runAsync(() async {
          await _touchFile(tempDir, orig.uri.pathSegments.last);
          if (gif) await _touchFile(tempDir, anim.uri.pathSegments.last);
          await _touchFile(tempDir, icon.uri.pathSegments.last);
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
                  key: 'Original',
                  imgUrl: 'https://x/orig.png',
                  imgDescHtml: '<p>Outfit One</p>',
                ),
                if (gif)
                  HoYoWikiGalleryItem(
                    id: 'b',
                    key: 'Dance',
                    imgUrl: 'https://x/anim.gif',
                    imgDescHtml: '<p>Outfit Two</p>',
                  ),
              ],
            ),
          );
        });
        await pumpDialog(
          tester,
          _rec(name: 'Hu Tao', gachaType: '301'),
          theme: theme,
        );
        return [orig, if (gif) anim, icon];
      }

      /// 圖片區目前顯示 [file] 的那張。
      Finder shown(File file) => find.byKey(ValueKey(file.path));

      /// 頁點（key 為 `page-dot-N`）。
      Finder dots() => find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> && k.value.startsWith('page-dot-');
      });

      /// 第 [i] 個頁點的寬度。
      double dotWidth(WidgetTester tester, int i) =>
          tester.getSize(find.byKey(ValueKey('page-dot-$i'))).width;

      testWidgets('swipe left goes to the next image, right goes back', (
        tester,
      ) async {
        final [orig, icon] = await openImages(tester);
        expect(shown(orig), findsOneWidget);
        await tester.drag(shown(orig), const Offset(-120, 0));
        await tester.pump();
        expect(shown(icon), findsOneWidget);
        expect(shown(orig), findsNothing);
        await tester.drag(shown(icon), const Offset(120, 0));
        await tester.pump();
        expect(shown(orig), findsOneWidget);
      });

      testWidgets('swiping keeps the chip bar selection in step', (
        tester,
      ) async {
        final [orig, _] = await openImages(tester);
        ChoiceChip chip(String label) =>
            tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
        expect(chip('Original').selected, isTrue);
        await tester.drag(shown(orig), const Offset(-120, 0));
        await tester.pump();
        expect(chip('Original').selected, isFalse);
        expect(chip('Icon').selected, isTrue);
      });

      testWidgets('no wrap-around at either end', (tester) async {
        final [orig, icon] = await openImages(tester);
        await tester.drag(shown(orig), const Offset(120, 0));
        await tester.pump();
        expect(shown(orig), findsOneWidget);
        await tester.drag(shown(orig), const Offset(-120, 0));
        await tester.pump();
        await tester.drag(shown(icon), const Offset(-120, 0));
        await tester.pump();
        expect(shown(icon), findsOneWidget);
      });

      testWidgets('vertical drag never switches', (tester) async {
        final [orig, _] = await openImages(tester);
        await tester.drag(shown(orig), const Offset(0, -120));
        await tester.pump();
        expect(shown(orig), findsOneWidget);
      });

      testWidgets('short slow drag does not switch', (tester) async {
        final [orig, _] = await openImages(tester);
        await tester.timedDrag(
          shown(orig),
          const Offset(-20, 0),
          const Duration(seconds: 1),
        );
        await tester.pump();
        expect(shown(orig), findsOneWidget);
      });

      testWidgets('short fast flick switches', (tester) async {
        final [orig, icon] = await openImages(tester);
        await tester.timedDrag(
          shown(orig),
          const Offset(-40, 0),
          const Duration(milliseconds: 60),
        );
        await tester.pump();
        expect(shown(icon), findsOneWidget);
      });

      testWidgets('trackpad horizontal pan switches', (tester) async {
        final [orig, icon] = await openImages(tester);
        final center = tester.getCenter(shown(orig));
        final pointer = TestPointer(1, PointerDeviceKind.trackpad);
        await tester.sendEventToBinding(pointer.panZoomStart(center));
        await tester.sendEventToBinding(
          pointer.panZoomUpdate(center, pan: const Offset(-60, 0)),
        );
        await tester.sendEventToBinding(
          pointer.panZoomUpdate(center, pan: const Offset(-120, 0)),
        );
        await tester.sendEventToBinding(pointer.panZoomEnd());
        await tester.pump();
        expect(shown(icon), findsOneWidget);
      });

      testWidgets('tap still opens zoom and the menu button stays', (
        tester,
      ) async {
        final [orig, _] = await openImages(tester);
        expect(find.byIcon(Icons.more_vert), findsOneWidget);
        await tester.tap(shown(orig));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(ZoomableImageOverlay), findsOneWidget);
      });

      testWidgets('page dots: one per image, selected one is wider', (
        tester,
      ) async {
        final [orig, _] = await openImages(tester);
        expect(dots(), findsNWidgets(2));
        expect(dotWidth(tester, 0), 18);
        expect(dotWidth(tester, 1), 6);
        await tester.drag(shown(orig), const Offset(-120, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(dotWidth(tester, 0), 6);
        expect(dotWidth(tester, 1), 18);
      });

      /// 第 [i] 個頁點的底色。
      Color dotColor(WidgetTester tester, int i) =>
          ((tester
                      .widget<AnimatedContainer>(
                        find.byKey(ValueKey('page-dot-$i')),
                      )
                      .decoration!
                  as BoxDecoration)
              .color)!;

      for (final (name, theme) in [
        ('light', buildLightTheme()),
        ('dark', buildDarkTheme()),
      ]) {
        testWidgets('page dots sit on a dark pill readable over any image '
            '($name)', (tester) async {
          // 頁點直接畫在圖上，深色圖會吃掉 borderEmphasis 色的點；比照 ⋮ 鈕墊半透明黑底。
          await openImages(tester, theme: theme);
          final pill = find.byKey(const ValueKey('page-dots-scrim'));
          expect(pill, findsOneWidget);
          for (final i in [0, 1]) {
            expect(
              find.descendant(
                of: pill,
                matching: find.byKey(ValueKey('page-dot-$i')),
              ),
              findsOneWidget,
            );
          }
          final decoration =
              tester.widget<DecoratedBox>(pill).decoration as ShapeDecoration;
          expect(decoration.color, Colors.black.withValues(alpha: 0.4));
          expect(dotColor(tester, 0), theme.colorScheme.primary);
          expect(dotColor(tester, 1), Colors.white70);
        });
      }

      /// 頁點的半透明底。
      Finder pill() => find.byKey(const ValueKey('page-dots-scrim'));

      testWidgets('tap on the page-dots pill still opens zoom', (tester) async {
        // 頁點墊了底色但不接手勢，點在上面仍要放大圖片。
        await openImages(tester);
        await tester.tapAt(tester.getCenter(pill()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(ZoomableImageOverlay), findsOneWidget);
      });

      testWidgets('swipe starting on the page-dots pill switches the image', (
        tester,
      ) async {
        final [_, icon] = await openImages(tester);
        await tester.dragFrom(tester.getCenter(pill()), const Offset(-120, 0));
        await tester.pump();
        expect(shown(icon), findsOneWidget);
      });

      testWidgets('swiping onto a GIF page shows the GIF', (tester) async {
        final [orig, anim, icon] = await openImages(tester, gif: true);
        expect(dots(), findsNWidgets(3));
        await tester.drag(shown(orig), const Offset(-120, 0));
        await tester.pump();
        expect(shown(anim), findsOneWidget);
        expect(shown(orig), findsNothing);
        expect(find.byIcon(Icons.more_vert), findsOneWidget);
        await tester.drag(shown(anim), const Offset(-120, 0));
        await tester.pump();
        expect(shown(icon), findsOneWidget);
      });

      testWidgets('switching skin updates the skin caption', (tester) async {
        final [orig, _, _] = await openImages(tester, gif: true);
        expect(find.text('Outfit One'), findsOneWidget);
        expect(find.text('Outfit Two'), findsNothing);
        await tester.drag(shown(orig), const Offset(-120, 0));
        await tester.pump();
        expect(find.text('Outfit One'), findsNothing);
        expect(find.text('Outfit Two'), findsOneWidget);
        await tester.tap(find.text('Original'));
        await tester.pump();
        expect(find.text('Outfit One'), findsOneWidget);
      });

      testWidgets('single image has no page dots and swipes do nothing', (
        tester,
      ) async {
        final icon = hoyowikiIconCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/icon.png',
        );
        await tester.runAsync(() async {
          await _touchFile(tempDir, icon.uri.pathSegments.last);
          await seedEntry(
            '12345',
            'Hu Tao',
            'en-us',
            _entryWith(iconUrl: 'https://x/icon.png', picUrl: '', list: []),
          );
        });
        await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
        expect(dots(), findsNothing);
        await tester.drag(shown(icon), const Offset(-120, 0));
        await tester.drag(shown(icon), const Offset(120, 0));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(shown(icon), findsOneWidget);
      });
    });
  });

  group('title 區 desc 間距', () {
    /// 開 dialog 並回傳「名稱底 → 說明文字首行頂」的垂直間距。
    /// [contains] 用來在 title 區 Html 內定位實際 desc 文字那條 RichText。
    Future<double> openAndMeasureGap(
      WidgetTester tester,
      String name,
      String contains,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            // 唯一 key：避免兩次量測重用同一 Navigator、上一個 dialog 殘留擋住按鈕。
            key: ValueKey(name),
            theme: buildDarkTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showGachaItemDetailDialog(
                  ctx,
                  _rec(name: name, gachaType: '301'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final nameBottom = tester.getRect(find.text(name)).bottom;
      final descLine = find.descendant(
        of: find.byType(Html),
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains(contains),
        ),
      );
      return tester.getRect(descLine.first).top - nameBottom;
    }

    testWidgets('單行說明與多行（換行）說明的首行間距一致', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'short1_icon.png');
        await _touchFile(tempDir, 'long1_icon.png');
        await notifier.setSearch(
          name: 'ShortName',
          lang: 'en-us',
          id: 'short1',
          menuId: 2,
        );
        await notifier.mergeEntry(
          id: 'short1',
          lang: 'en-us',
          fetched: const HoYoWikiEntryFetched(
            iconUrl: 'https://cdn.hoyolab.com/short_icon.png',
            page: HoYoWikiPageData(
              gallery: null,
              desc: '<p>Short.</p>',
              tags: [],
            ),
          ),
        );
        await notifier.setSearch(
          name: 'LongName',
          lang: 'en-us',
          id: 'long1',
          menuId: 2,
        );
        await notifier.mergeEntry(
          id: 'long1',
          lang: 'en-us',
          fetched: const HoYoWikiEntryFetched(
            iconUrl: 'https://cdn.hoyolab.com/long_icon.png',
            page: HoYoWikiPageData(
              gallery: null,
              desc:
                  '<p>This is a very long description that should definitely '
                  'wrap across multiple lines inside the constrained dialog '
                  'width so the leading above the first line can be '
                  'compared with the single-line case.</p>',
              tags: [],
            ),
          ),
        );
      });

      final shortGap = await openAndMeasureGap(tester, 'ShortName', 'Short.');
      final longGap = await openAndMeasureGap(
        tester,
        'LongName',
        'This is a very long',
      );

      expect(
        (shortGap - longGap).abs(),
        lessThan(1.0),
        reason: 'single-line gap=$shortGap multi-line gap=$longGap',
      );
    });
  });

  group('buildHoYoWikiEntryUrl', () {
    test('帶上 lang query 參數並對齊資料語言', () {
      final uri = buildHoYoWikiEntryUrl(id: 'x1', lang: 'zh-tw');
      expect(uri.path, '/pc/genshin/entry/x1');
      expect(uri.queryParameters['lang'], 'zh-tw');
      expect(
        uri.toString(),
        'https://wiki.hoyolab.com/pc/genshin/entry/x1?lang=zh-tw',
      );
    });

    test('不同資料語言反映在 lang 參數', () {
      expect(
        buildHoYoWikiEntryUrl(id: 'a2', lang: 'ja-jp').queryParameters['lang'],
        'ja-jp',
      );
    });
  });
}
