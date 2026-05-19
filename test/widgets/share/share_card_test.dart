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
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';

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

  testWidgets('右欄時間軸超出左欄高時，截斷且底部顯示正確剩餘筆數', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    // 造 12 筆 rank5 → timeline.length=12。新行為：N 由左欄高保守估算
    // （只有 5★ → rarity/itemType 各 1 legend 行 → 左欄較矮）→ N<12，
    // remaining = 12 - N 併入 footer，且右側嚴格不超出左欄。
    final records = <GachaRecord>[
      for (var i = 0; i < 12; i++) _r('301', 5, '五星$i'),
    ];
    final card = ShareCard.banner(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      title: '角色活動祈願',
      records: records,
      targetRank: 5,
    );
    await _pump(t, card);
    expect(t.takeException(), isNull);

    // 右欄 TimelineVertical 卡高 ≤ 左欄兩 _PieBox 疊高（嚴格不超出，容忍 0.5）。
    final timelineHeight = t.getSize(find.byType(TimelineVertical)).height;
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
    final leftHeight =
        t.getBottomLeft(itemTypeBox).dy - t.getTopLeft(rarityBox).dy;
    expect(timelineHeight, lessThanOrEqualTo(leftHeight + 0.5));

    // 截斷：N 必 < 12，footer 顯示 remaining = 12 - N（> 0）。
    // 標題含 N（timelineTopRarityTitle 第二參數），由標題反推 N。
    var shownN = 0;
    for (var n = 1; n <= 12; n++) {
      if (find
          .descendant(
            of: find.byType(TimelineVertical),
            matching: find.text(l.timelineTopRarityTitle(l.rarityStar(5), n)),
          )
          .evaluate()
          .isNotEmpty) {
        shownN = n;
        break;
      }
    }
    expect(shownN, greaterThan(0));
    expect(shownN, lessThan(12));
    expect(
      find.descendant(
        of: find.byType(TimelineVertical),
        matching: find.text(
          l.shareImageTimelineMore(12 - shownN, l.rarityStar(5)),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('右欄時間軸 ≤ 10 筆時，不顯示剩餘筆數提示', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    // 造 3 筆 rank5 → timeline.length=3，remaining=0，不顯示提示。
    final records = <GachaRecord>[
      for (var i = 0; i < 3; i++) _r('301', 5, '五星$i'),
    ];
    final card = ShareCard.banner(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      title: '角色活動祈願',
      records: records,
      targetRank: 5,
    );
    await _pump(t, card);
    expect(t.takeException(), isNull);

    expect(
      find.text(l.shareImageTimelineMore(0, l.rarityStar(5))),
      findsNothing,
    );
  });

  testWidgets('下方右欄時間軸卡高度 == 左欄雙圓餅卡疊起來的總高', (t) async {
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

    // 右欄：時間軸卡外框（TimelineVertical）高度。
    final timelineHeight = t.getSize(find.byType(TimelineVertical)).height;

    // 左欄：兩張圓餅卡（_PieBox 外框 Container = 各自標題 labelSmall 的
    // 最近 ancestor Container）疊起來的範圍 = 第一張頂端 → 第二張底端。
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
    final leftColumnTop = t.getTopLeft(rarityBox).dy;
    final leftColumnBottom = t.getBottomLeft(itemTypeBox).dy;
    final leftColumnHeight = leftColumnBottom - leftColumnTop;

    // 嚴格不超出（硬需求）：右 ≤ 左。
    expect(timelineHeight, lessThanOrEqualTo(leftColumnHeight + 0.5));
    // 少量資料放得下時，fillHeight + IntrinsicHeight 使右欄撐到與左欄等高
    // （右側內容估算 ≤ H，IntrinsicHeight 較高側恆為左欄，不反拉左欄）。
    expect(timelineHeight, closeTo(leftColumnHeight, 0.5));
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
