import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
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
/// 幾乎每筆都帶月份 tag（較高的 row）。共 [count] 筆。
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

  testWidgets('跨月 5★ 大量資料：banner 右欄嚴格 ≤ 左欄（不可超出）', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    // 16 筆 5★ 每筆不同年月 → timeline 每筆帶月份 tag（最高的 row）。
    final card = ShareCard.banner(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      title: '角色活動祈願',
      records: _crossMonthFives(16),
      targetRank: 5,
    );
    await _pump(t, card);
    expect(t.takeException(), isNull);

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
    // 嚴格不超出（硬需求，不可放寬成 closeTo）。
    expect(
      timelineHeight,
      lessThanOrEqualTo(leftHeight + 0.5),
      reason: 'banner 跨月：右欄 $timelineHeight 不可超出左欄 $leftHeight',
    );
    // 保守不應退化到極少筆：至少放得下若干筆（避免 N→0/1）。
    var shownN = 0;
    for (var n = 1; n <= 16; n++) {
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
    expect(shownN, greaterThanOrEqualTo(3), reason: 'N 不應退化到極少筆，實際 $shownN');
  });

  testWidgets('跨月 5★ 大量資料：overview 右欄嚴格 ≤ 左欄（不可超出）', (t) async {
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

    // 第一段（祈願）為跨月大量 5★ → 檢查其右欄不超出左欄。
    final timelines = find.byType(TimelineVertical);
    expect(timelines, findsNWidgets(2));
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
    final timelineHeight = t.getSize(timelines.first).height;
    final leftHeight =
        t.getBottomLeft(itemTypeBox).dy - t.getTopLeft(rarityBox).dy;
    expect(
      timelineHeight,
      lessThanOrEqualTo(leftHeight + 0.5),
      reason: 'overview 跨月：右欄 $timelineHeight 不可超出左欄 $leftHeight',
    );
  });

  // 量「右欄時間軸內容自然高」：用與分享圖完全相同的 shown 筆數（由標題反推
  // N）、**完全相同的右欄外框寬度**（先從已 pump 的分享圖量真實 TimelineVertical
  // 寬度——meta 文字會否換行高度敏感於寬度，故必須一致）與相同 title/footerNote/
  // nowPulls，pump 一個**不帶 fillHeight** 的對照，讓它依內容自然收縮量高。
  // 這是內容真實所需高，不受 fillHeight 撐高干擾，且與分享圖逐像素同行高。
  Future<double> naturalTimelineHeight(
    WidgetTester t,
    AppLocalizations l,
    List<GachaRecord> records, {
    required int targetRank,
    required bool isAcrossBanners,
    int? nowPulls,
  }) async {
    // 先量分享圖右欄 TimelineVertical 真實外框寬度（與行高換行行為攸關）。
    final realWidth = t.getSize(find.byType(TimelineVertical)).width;
    // 由分享圖標題反推 N（timelineTopRarityTitle 第二參數）。
    final timeline = buildTimelineEntries(records, targetRank: targetRank);
    var shownN = 0;
    for (var n = timeline.length; n >= 1; n--) {
      if (find
          .text(l.timelineTopRarityTitle(l.rarityStar(targetRank), n))
          .evaluate()
          .isNotEmpty) {
        shownN = n;
        break;
      }
    }
    final shown = timeline.take(shownN).toList(growable: false);
    final remaining = timeline.length - shownN;
    await t.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: realWidth, // 與分享圖右欄真實外框寬度一致
                child: TimelineVertical(
                  key: const Key('natTl'),
                  title: l.timelineTopRarityTitle(
                    l.rarityStar(targetRank),
                    shownN,
                  ),
                  footerNote: remaining > 0
                      ? l.shareImageTimelineMore(
                          remaining,
                          l.rarityStar(targetRank),
                        )
                      : null,
                  fillHeight: false,
                  entries: shown,
                  colors: BannerColors.of(Brightness.dark),
                  targetRank: targetRank,
                  nowPulls: nowPulls,
                  isAcrossBanners: isAcrossBanners,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    return t.getSize(find.byKey(const Key('natTl'))).height;
  }

  testWidgets('填滿率：同月大量 5★ → 右欄內容自然高 ≥ 左欄高 × 0.85', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    // 14 筆同月 5★（同年月 → 僅第一筆帶月份 tag，每筆 ~70px）。
    final records = <GachaRecord>[
      for (var i = 0; i < 14; i++)
        _r('301', 5, '五星$i', time: DateTime(2026, 5, 20 - i, 12)),
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
    // 嚴格不超出。
    expect(timelineHeight, lessThanOrEqualTo(leftHeight + 0.5));

    // 內容自然高（重 pump 對照，會破壞上面 finder，故最後量）。
    final pulls = pullsSinceLastRanked(records, rank: 5);
    final natural = await naturalTimelineHeight(
      t,
      l,
      records,
      targetRank: 5,
      isAcrossBanners: false,
      nowPulls: pulls,
    );
    expect(
      natural,
      greaterThanOrEqualTo(leftHeight * 0.85),
      reason:
          '同月填滿率不足：內容自然高 $natural < 左欄 $leftHeight × 0.85 '
          '(${(natural / leftHeight).toStringAsFixed(3)})',
    );
  });

  testWidgets('填滿率：跨月大量 5★ → 右欄內容自然高 ≥ 左欄高 × 0.85', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final records = _crossMonthFives(16);
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

    final pulls = pullsSinceLastRanked(records, rank: 5);
    final natural = await naturalTimelineHeight(
      t,
      l,
      records,
      targetRank: 5,
      isAcrossBanners: false,
      nowPulls: pulls,
    );
    expect(
      natural,
      greaterThanOrEqualTo(leftHeight * 0.85),
      reason:
          '跨月填滿率不足：內容自然高 $natural < 左欄 $leftHeight × 0.85 '
          '(${(natural / leftHeight).toStringAsFixed(3)})',
    );
  });

  testWidgets('填滿率：混合 rarity（3 legend 行）大量同月 → 內容自然高 ≥ 左欄高 × 0.85', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    // 含 5★/4★/3★ → rarity legend 3 行、itemType 2 行 → 左欄較高；
    // 大量同月 5★ 作為時間軸資料（targetRank=5 的 timeline 只取 5★）。
    final records = <GachaRecord>[
      for (var i = 0; i < 14; i++)
        _r('301', 5, '五星$i', time: DateTime(2026, 5, 20 - i, 12)),
      for (var i = 0; i < 8; i++)
        _r('301', 4, '四星$i', time: DateTime(2026, 5, 19, 12)),
      for (var i = 0; i < 30; i++)
        _r('301', 3, '三星$i', time: DateTime(2026, 5, 19, 12)),
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

    final pulls = pullsSinceLastRanked(records, rank: 5);
    final natural = await naturalTimelineHeight(
      t,
      l,
      records,
      targetRank: 5,
      isAcrossBanners: false,
      nowPulls: pulls,
    );
    expect(
      natural,
      greaterThanOrEqualTo(leftHeight * 0.85),
      reason:
          '混合 rarity 填滿率不足：內容自然高 $natural < 左欄 $leftHeight × 0.85 '
          '(${(natural / leftHeight).toStringAsFixed(3)})',
    );
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
