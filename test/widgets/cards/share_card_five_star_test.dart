import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/five_star_overview.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/preloaded_hoyowiki_images.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';

Future<ui.Image> _solidImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(4, 4);
}

void main() {
  testWidgets('banner 分享圖含 FiveStarOverview（含 5★ 時）', (tester) async {
    late Directory tempDir;
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('share_five_star_test_');
    });
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
    final container = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(hoyowikiIndexProvider.notifier).waitForLoad(),
    );

    final icon = await tester.runAsync(_solidImage);
    addTearDown(() => icon!.dispose());

    final records = [
      GachaRecord(
        id: '1',
        uid: '100000001',
        gachaType: '301',
        name: '夜蘭',
        itemType: '角色',
        rankType: 5,
        time: DateTime(2025, 4, 1),
        lang: 'zh-tw',
      ),
    ];

    late AppLocalizations l;
    final card = Builder(
      builder: (ctx) {
        l = AppLocalizations.of(ctx)!;
        return ShareCard.banner(
          l: l,
          appVersion: '1.0.0',
          appIcon: icon!,
          options: const ShareImageOptions(
            brightness: Brightness.dark,
            showFullUid: true,
          ),
          uid: '100000001',
          updatedAt: DateTime(2025, 4, 1),
          title: 'Test',
          records: records,
          targetRank: 5,
          index: container.read(hoyowikiIndexProvider),
        );
      },
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PreloadedHoYoWikiImages(images: const {}, child: card),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FiveStarOverview), findsOneWidget);
    expect(find.text(l.fiveStarOverviewTitle), findsOneWidget);
  });

  testWidgets('overview 分享圖的五星一覽落在祈願段、頌願段之前', (tester) async {
    late Directory tempDir;
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('share_five_star_ov_');
    });
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
    final container = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(hoyowikiIndexProvider.notifier).waitForLoad(),
    );

    final icon = await tester.runAsync(_solidImage);
    addTearDown(() => icon!.dispose());

    // 祈願段有 5★（301），頌願段也有資料（2000）。
    final banners = {
      '301': [
        GachaRecord(
          id: '1',
          uid: '100000001',
          gachaType: '301',
          name: '夜蘭',
          itemType: '角色',
          rankType: 5,
          time: DateTime(2025, 4, 1),
          lang: 'zh-tw',
        ),
      ],
      '2000': [
        GachaRecord(
          id: '2',
          uid: '100000001',
          gachaType: '2000',
          name: '頌願五星',
          itemType: '角色',
          rankType: 5,
          time: DateTime(2025, 4, 2),
          lang: 'zh-tw',
        ),
      ],
    };

    late AppLocalizations l;
    final card = Builder(
      builder: (ctx) {
        l = AppLocalizations.of(ctx)!;
        return ShareCard.overview(
          l: l,
          appVersion: '1.0.0',
          appIcon: icon!,
          options: const ShareImageOptions(
            brightness: Brightness.dark,
            showFullUid: true,
          ),
          uid: '100000001',
          updatedAt: DateTime(2025, 4, 2),
          banners: banners,
          index: container.read(hoyowikiIndexProvider),
        );
      },
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PreloadedHoYoWikiImages(images: const {}, child: card),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 只在祈願段出現一次（頌願段的 5★ 被排除）。
    expect(find.byType(FiveStarOverview), findsOneWidget);

    // 五星一覽必須在頌願段標題「之上」（= 落在祈願段底下、頌願段之前）。
    final overviewDy = tester.getTopLeft(find.byType(FiveStarOverview)).dy;
    final odesTitleDy = tester
        .getTopLeft(find.text(l.pageOverviewOdesSection))
        .dy;
    expect(overviewDy, lessThan(odesTitleDy));
  });
}
