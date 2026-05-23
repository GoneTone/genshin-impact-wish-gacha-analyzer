import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/preloaded_hoyowiki_images.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/wish_item_icon.dart';

GachaRecord _rec({
  required String name,
  required String gachaType,
  int rankType = 5,
}) => GachaRecord(
  id: '1',
  uid: '801057625',
  gachaType: gachaType,
  name: name,
  itemType: 'Character',
  rankType: rankType,
  time: DateTime(2026, 5, 23),
  lang: 'en-us',
);

Widget _wrap(Widget child, ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(body: child),
      ),
    );

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wish_item_icon_test_');
    container = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoyoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      ],
    );
    addTearDown(container.dispose);
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
  });

  tearDown(() async {
    // Windows 上 Image.file 可能持有檔案 handle，忽略刪除失敗。
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  testWidgets('頌願 gachaType → SizedBox.shrink', (tester) async {
    await tester.pumpWidget(
      _wrap(
        WishItemIcon(
          record: _rec(name: 'OdesItem', gachaType: '2000'),
          size: 20,
        ),
        container,
      ),
    );
    final box = tester.getSize(find.byType(WishItemIcon));
    expect(box, Size.zero);
  });

  testWidgets('空 index → placeholder', (tester) async {
    await tester.pumpWidget(
      _wrap(
        WishItemIcon(
          record: _rec(name: 'Hu Tao', gachaType: '301'),
          size: 20,
        ),
        container,
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.byType(WishItemIcon), findsOneWidget);
    final size = tester.getSize(find.byType(WishItemIcon));
    expect(size.width, 20);
    expect(size.height, 20);
  });

  testWidgets('有 id 無 entry → placeholder', (tester) async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    // setSearch 涉及真實檔案 I/O（atomic rename），需在 runAsync 內執行。
    await tester.runAsync(
      () => notifier.setSearch(name: 'Hu Tao', lang: 'en-us', id: '111'),
    );
    await tester.pumpWidget(
      _wrap(
        WishItemIcon(
          record: _rec(name: 'Hu Tao', gachaType: '301'),
          size: 20,
        ),
        container,
      ),
    );
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('有 entry 但 cache 檔不存在 → placeholder', (tester) async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    await tester.runAsync(() async {
      await notifier.setSearch(name: 'Hu Tao', lang: 'en-us', id: '111');
      await notifier.setEntry(
        id: '111',
        entry: HoyoWikiEntry(
          iconUrl: 'https://x/icon.png',
          headerImgUrl: '',
          fetchedAt: DateTime.utc(2026, 5, 23),
        ),
      );
    });
    await tester.pumpWidget(
      _wrap(
        WishItemIcon(
          record: _rec(name: 'Hu Tao', gachaType: '301'),
          size: 20,
        ),
        container,
      ),
    );
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('完整 chain（index + cache 檔在） → 顯示 Image', (tester) async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    final iconUrl = 'https://x/icon.png';
    await tester.runAsync(() async {
      await notifier.setSearch(name: 'Hu Tao', lang: 'en-us', id: '111');
      await notifier.setEntry(
        id: '111',
        entry: HoyoWikiEntry(
          iconUrl: iconUrl,
          headerImgUrl: '',
          fetchedAt: DateTime.utc(2026, 5, 23),
        ),
      );
      final cacheFile = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '111',
        kind: HoyoWikiImageKind.icon,
        url: iconUrl,
      );
      await cacheFile.writeAsBytes(_minimalPng());
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _wrap(
          WishItemIcon(
            record: _rec(name: 'Hu Tao', gachaType: '301'),
            size: 20,
          ),
          container,
        ),
      );
      await tester.pump();
    });
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('PreloadedHoyoWikiImages 命中 → 顯示 RawImage', (tester) async {
    await tester.runAsync(() async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.setSearch(name: 'Hu Tao', lang: 'en-us', id: '111');
      await notifier.setEntry(
        id: '111',
        entry: HoyoWikiEntry(
          iconUrl: 'https://x/icon.png',
          headerImgUrl: '',
          fetchedAt: DateTime.utc(2026, 5, 23),
        ),
      );

      // 用 PictureRecorder 合成最小 ui.Image（比 instantiateImageCodec 更穩定）。
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      final img = await recorder.endRecording().toImage(1, 1);
      addTearDown(img.dispose);

      await tester.pumpWidget(
        _wrap(
          PreloadedHoyoWikiImages(
            images: {'111': img},
            child: WishItemIcon(
              record: _rec(name: 'Hu Tao', gachaType: '301'),
              size: 20,
            ),
          ),
          container,
        ),
      );
      await tester.pump();

      expect(find.byType(RawImage), findsOneWidget);
      expect(
        find.byType(Image),
        findsNothing,
        reason: 'preloaded 命中應該用 RawImage 而非 Image.file',
      );
    });
  });
}

/// 最小可解碼 1x1 透明 PNG。
List<int> _minimalPng() => const [
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x62,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0d,
  0x0a,
  0x2d,
  0xb4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];
