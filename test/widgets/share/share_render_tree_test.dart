import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_renderer.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_image_helper.dart';

// 自適應高度斷言用上下界（邏輯px × pixelRatio 3）：
// 下界證明確有內容（非空白圖）；上界 = renderer 預設 maxHeight × pixelRatio，
// 證明沒撞到上限被裁切。實測 overview 兩段大資料 < 3500 邏輯px。
const _minPngHeight = 600 * 3; // > 600 邏輯px 才算有實際內容
const _maxPngHeight = 8000 * 3; // renderer maxHeight 上限 × pixelRatio

// 鏡像 test/widgets/share/share_card_test.dart 的 ui.Image / GachaRecord 工廠。
Future<ui.Image> _img() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(4, 4);
}

GachaRecord _r(String gt, int rank, String name) => GachaRecord(
  id: '$name$rank${gt}_${DateTime.now().microsecondsSinceEpoch}',
  uid: '800123456',
  gachaType: gt,
  name: name,
  itemType: rank == 5 ? '角色' : '武器',
  rankType: rank,
  time: DateTime(2026, 5, 10, 12),
  lang: 'zh-tw',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 收集離屏渲染期間 widget build 拋出的 FlutterError（如 RarityPie 的
  // null-check），渲染不會 throw、只會替換成 ErrorWidget，必須靠 onError 攔。
  late List<FlutterErrorDetails> collected;
  FlutterExceptionHandler? prevOnError;
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    collected = <FlutterErrorDetails>[];
    prevOnError = FlutterError.onError;
    FlutterError.onError = (details) => collected.add(details);
    tempDir = await Directory.systemTemp.createTemp('share_render_tree_test_');
    container = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoyoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      ],
    );
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
  });

  tearDown(() async {
    FlutterError.onError = prevOnError;
    container.dispose();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('buildShareRenderTree 渲染 banner 卡（含雙圓餅）不應拋錯', (t) async {
    await t.runAsync(() async {
      final l = await AppLocalizations.delegate.load(const Locale('zh'));
      final card = ShareCard.banner(
        l: l,
        appVersion: '1.0.0',
        appIcon: await _img(),
        options: const ShareImageOptions(),
        uid: '800123456',
        updatedAt: DateTime(2026, 5, 18, 14, 30),
        title: '角色活動祈願',
        records: [
          _r('301', 5, '那維萊特'),
          _r('301', 4, '菲謝爾'),
          _r('301', 3, '冷刃'),
        ],
        targetRank: 5,
      );
      final png = await renderWidgetToPng(
        buildShareRenderTree(
          card: card,
          brightness: Brightness.dark,
          locale: const Locale('zh'),
          container: container,
        ),
        width: kShareCardWidth,
      );

      expect(
        collected,
        isEmpty,
        reason: collected.isEmpty
            ? null
            : '離屏渲染拋出 ${collected.length} 個錯誤：'
                  '${collected.map((d) => d.exceptionAsString()).join(' | ')}',
      );
      expect(png.isNotEmpty, isTrue);
      expect(png.length, greaterThan(10 * 1024), reason: 'PNG 過小，可能渲染為空白圖');

      // 高度自適應：解碼後高度在合理下界（有內容）與 maxHeight 上界（未被裁切）之間，
      // 證明 banner 卡輸出高=內容高、零留白零裁切。
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, (kShareCardWidth * 3).round());
      expect(
        frame.image.height,
        greaterThan(_minPngHeight),
        reason: 'PNG 過矮，可能渲染為空白圖',
      );
      expect(
        frame.image.height,
        lessThan(_maxPngHeight),
        reason: 'PNG 撞到 maxHeight，內容可能被裁切',
      );
    });
  });

  testWidgets('buildShareRenderTree 渲染 overview 卡（兩段雙圓餅）不應拋錯', (t) async {
    await t.runAsync(() async {
      final l = await AppLocalizations.delegate.load(const Locale('zh'));
      final card = ShareCard.overview(
        l: l,
        appVersion: '1.0.0',
        appIcon: await _img(),
        options: const ShareImageOptions(showFullUid: true),
        uid: '800123456',
        updatedAt: DateTime(2026, 5, 18, 14, 30),
        banners: {
          '301': [_r('301', 5, '那維萊特'), _r('301', 3, '冷刃')],
          '2000': [_r('2000', 5, '某五星')],
        },
      );
      final png = await renderWidgetToPng(
        buildShareRenderTree(
          card: card,
          brightness: Brightness.dark,
          locale: const Locale('zh'),
          container: container,
        ),
        width: kShareCardWidth,
      );

      expect(
        collected,
        isEmpty,
        reason: collected.isEmpty
            ? null
            : '離屏渲染拋出 ${collected.length} 個錯誤：'
                  '${collected.map((d) => d.exceptionAsString()).join(' | ')}',
      );
      expect(png.isNotEmpty, isTrue);
      expect(png.length, greaterThan(10 * 1024), reason: 'PNG 過小，可能渲染為空白圖');

      // 高度自適應：overview 兩段內容比 banner 高，仍須落在下界與上界之間，
      // 證明零留白零裁切。
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, (kShareCardWidth * 3).round());
      expect(
        frame.image.height,
        greaterThan(_minPngHeight),
        reason: 'PNG 過矮，可能渲染為空白圖',
      );
      expect(
        frame.image.height,
        lessThan(_maxPngHeight),
        reason: 'PNG 撞到 maxHeight，內容可能被裁切',
      );
    });
  });
}
