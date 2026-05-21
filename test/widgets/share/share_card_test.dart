import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/inline_section_title.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/left_driven_equal_height.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';

Future<ui.Image> _img() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(4, 4);
}

GachaRecord _r(String gt, int rank, String name, {DateTime? time}) =>
    GachaRecord(
      id: '$name$rank${gt}_${DateTime.now().microsecondsSinceEpoch}',
      uid: '800123456',
      gachaType: gt,
      name: name,
      itemType: rank == 5 ? '角色' : '武器',
      rankType: rank,
      time: time ?? DateTime(2026, 5, 10, 12),
      lang: 'zh-tw',
    );

/// 造跨月 5★ 紀錄：第 i 筆時間落在不同年月（遞減），使 TimelineVertical
/// 幾乎每筆都帶月份 tag（較高的 row），自然高遠超左欄高。共 [count] 筆。
List<GachaRecord> _crossMonthFives(int count) => [
  for (var i = 0; i < count; i++)
    _r(
      '301',
      5,
      '五星$i',
      // 從 2026-01 往前每筆退一個月，產生 count 個不同年月。
      time: DateTime(2026, 1, 1, 12).subtract(Duration(days: 31 * i + 1)),
    ),
];

Future<void> _pump(WidgetTester t, Widget card) async {
  await t.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 1200, child: card)),
      ),
    ),
  );
  await t.pump();
}

/// 左欄兩 _PieBox 疊起來的總高（第一張頂端 → 第二張底端）。
double _leftColumnHeight(WidgetTester t, AppLocalizations l) {
  final rarityBox = find
      .ancestor(
        of: find.text(l.statsRarityDistribution),
        matching: find.byType(Container),
      )
      .first;
  final itemTypeBox = find
      .ancestor(
        of: find.text(l.statsItemTypeDistribution),
        matching: find.byType(Container),
      )
      .first;
  return t.getBottomLeft(itemTypeBox).dy - t.getTopLeft(rarityBox).dy;
}

void main() {
  testWidgets('卡池模式渲染且無 overflow（遮罩 UID）', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final card = ShareCard.banner(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      title: '角色活動祈願',
      records: [_r('301', 5, '那維萊特'), _r('301', 4, '菲謝爾'), _r('301', 3, '冷刃')],
      targetRank: 5,
    );
    await _pump(t, card);
    expect(t.takeException(), isNull);
    expect(find.textContaining('800xxxxxx'), findsOneWidget);
    expect(find.textContaining('800123456'), findsNothing);
  });

  testWidgets('頂部 stat 為水平橫排（三張同一橫列）', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final card = ShareCard.banner(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      title: '角色活動祈願',
      records: [_r('301', 5, '那維萊特'), _r('301', 4, '菲謝爾'), _r('301', 3, '冷刃')],
      targetRank: 5,
    );
    await _pump(t, card);
    expect(t.takeException(), isNull);

    // 結構斷言：stat 橫排 Row 帶 Key('shareStatRow')。
    final statRow = find.byKey(const Key('shareStatRow'));
    expect(statRow, findsOneWidget);

    // 版面斷言：三個 stat label（總計 / 5★ / 4★）位於同一橫列，
    // y 座標相近（同列），且 x 座標遞增（左→右排列）。
    final labels = <Finder>[
      find.text(l.statsTotal),
      find.text(l.statsRankCount(l.rarityStar(5))),
      find.text(l.statsRankCount(l.rarityStar(4))),
    ];
    final tops = labels
        .map((f) => t.getTopLeft(f.first).dy)
        .toList(growable: false);
    final lefts = labels
        .map((f) => t.getTopLeft(f.first).dx)
        .toList(growable: false);
    expect((tops[0] - tops[1]).abs(), lessThan(2));
    expect((tops[1] - tops[2]).abs(), lessThan(2));
    expect(lefts[0], lessThan(lefts[1]));
    expect(lefts[1], lessThan(lefts[2]));
  });

  testWidgets('卡池模式重用 App 元件（StatCard ×3 + TimelineVertical ×1）', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final card = ShareCard.banner(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      title: '角色活動祈願',
      records: [_r('301', 5, '那維萊特'), _r('301', 4, '菲謝爾'), _r('301', 3, '冷刃')],
      targetRank: 5,
    );
    await _pump(t, card);
    expect(t.takeException(), isNull);

    // 鎖住「已改用 App 元件」：回退到自製 _StatTile/_ShareTimeline 會失敗。
    expect(find.byType(StatCard), findsNWidgets(3));
    expect(find.byType(TimelineVertical), findsOneWidget);
    // 右欄時間軸標題改用與其他卡片一致的低調小標題（labelSmall），
    // 不再用視覺權重過重的 InlineSectionTitle（titleLarge + icon）。
    expect(find.byType(InlineSectionTitle), findsNothing);
    // 時間軸標題現在進到 TimelineVertical 卡片內（border 內）。
    expect(
      find.descendant(
        of: find.byType(TimelineVertical),
        matching: find.text(l.timelineTopRarityTitle(l.rarityStar(5), 1)),
      ),
      findsOneWidget,
    );
  });

  testWidgets('綜合模式重用 App 元件（StatCard ×6 + TimelineVertical ×2）', (t) async {
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
    await _pump(t, card);
    expect(t.takeException(), isNull);

    expect(find.byType(StatCard), findsNWidgets(6));
    expect(find.byType(TimelineVertical), findsNWidgets(2));
    expect(find.byType(InlineSectionTitle), findsNothing);
    // 兩段時間軸標題皆進到各自 TimelineVertical 卡片內。
    expect(
      find.descendant(
        of: find.byType(TimelineVertical),
        matching: find.text(l.timelineTopRarityTitle(l.rarityStar(5), 1)),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('時間軸超出左欄高：右欄卡恆 = 左欄高、內容被裁、無 overflow', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    // 12 筆跨月 5★ → 時間軸自然高遠超左欄（只有 5★ → 左欄各 1 legend 行，較矮）。
    final card = ShareCard.banner(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      title: '角色活動祈願',
      records: _crossMonthFives(12),
      targetRank: 5,
    );
    await _pump(t, card);
    // 直接裁切方案：不可有 RenderFlex overflow 或任何 error。
    expect(t.takeException(), isNull);

    // 右欄時間軸卡外框高度恆 == 左欄兩 _PieBox 疊高（LeftDrivenEqualHeight
    // 量左欄高後強制右欄等高；超出由 TimelineVertical 自身 ClipRect 裁掉）。
    expect(find.byType(LeftDrivenEqualHeight), findsOneWidget);
    final rightHeight = t
        .getSize(
          find
              .descendant(
                of: find.byType(TimelineVertical),
                matching: find.byType(Container),
              )
              .first,
        )
        .height;
    final leftHeight = _leftColumnHeight(t, l);
    expect(rightHeight, closeTo(leftHeight, 0.5));

    // 標題仍在 TimelineVertical 子樹內（title 保留，至多 10 筆）。
    expect(
      find.descendant(
        of: find.byType(TimelineVertical),
        matching: find.text(l.timelineTopRarityTitle(l.rarityStar(5), 10)),
      ),
      findsOneWidget,
    );
  });

  testWidgets('資料少：右欄卡恆 = 左欄高（卡內底部留白，不縮小）', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final card = ShareCard.banner(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      title: '角色活動祈願',
      records: [_r('301', 5, '那維萊特'), _r('301', 4, '菲謝爾'), _r('301', 3, '冷刃')],
      targetRank: 5,
    );
    await _pump(t, card);
    expect(t.takeException(), isNull);

    // 資料少時，右欄卡仍被強制撐到左欄高（卡內底部為留白，非縮小、
    // 非外部背景空白）—— 即使用者確認的目標行為。
    expect(find.byType(LeftDrivenEqualHeight), findsOneWidget);
    final rightHeight = t
        .getSize(
          find
              .descendant(
                of: find.byType(TimelineVertical),
                matching: find.byType(Container),
              )
              .first,
        )
        .height;
    final leftHeight = _leftColumnHeight(t, l);
    expect(rightHeight, closeTo(leftHeight, 0.5));
  });

  testWidgets('跨月 5★ 大量資料（overview）：兩段渲染、無 overflow', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final card = ShareCard.overview(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      banners: {
        '301': _crossMonthFives(16),
        '2000': [_r('2000', 5, '某五星')],
      },
    );
    await _pump(t, card);
    expect(t.takeException(), isNull);

    expect(find.byType(TimelineVertical), findsNWidgets(2));
    expect(find.byType(LeftDrivenEqualHeight), findsNWidgets(2));
  });

  testWidgets('綜合模式：祈願 + 頌願兩段，showFullUid', (t) async {
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
    await _pump(t, card);
    expect(t.takeException(), isNull);
    expect(find.textContaining('800123456'), findsOneWidget);
  });
}
