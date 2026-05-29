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
}
