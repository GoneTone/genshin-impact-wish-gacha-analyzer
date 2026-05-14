import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/banner_top_rarity_bars.dart';

WishRecord _r({
  required String id,
  required String gachaType,
  required int rank,
  required DateTime time,
  String name = 'X',
  String itemType = '角色',
}) => WishRecord(
  id: id,
  uid: '100000000',
  gachaType: gachaType,
  name: name,
  itemType: itemType,
  rankType: rank,
  time: time,
  lang: 'zh-tw',
);

Widget _wrap(Widget Function(BuildContext ctx, BannerColors colors) build) =>
    MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 280,
          child: Builder(
            builder: (ctx) {
              final colors = BannerColors.of(Theme.of(ctx).brightness);
              return build(ctx, colors);
            },
          ),
        ),
      ),
    );

void main() {
  testWidgets('empty banners → renders one row per gachaType', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => BannerTopRarityBars(
          types: gachaTypes,
          banners: const {},
          colors: colors,
        ),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(BannerTopRarityBars)),
    )!;
    for (final t in gachaTypes) {
      expect(find.text(t.resolveName(l)), findsOneWidget);
    }
    // 除新手池 (100) 顯示「已結束」外，其餘所有池都顯示「暫無 5★」
    expect(find.text(l.pityNoFiveStar), findsNWidgets(gachaTypes.length - 1));
    expect(find.text(l.pityBeginnerEnded), findsOneWidget);
    // 件數全為 0；分隔點「·」出現 N 次
    expect(find.text('0'), findsNWidgets(gachaTypes.length));
    expect(find.text('·'), findsNWidgets(gachaTypes.length));
  });

  testWidgets('renders 5★ count and "距上次 5★" subtitle correctly', (
    tester,
  ) async {
    // 301 character: desc-by-time → [4★, 4★, 5★A] → 5★ count = 1, pulls since last 5★ = 2
    final t0 = DateTime(2025, 1, 1);
    final banners = <String, List<WishRecord>>{
      '301': [
        _r(
          id: '3',
          gachaType: '301',
          rank: 4,
          time: t0.add(const Duration(days: 3)),
        ),
        _r(
          id: '2',
          gachaType: '301',
          rank: 4,
          time: t0.add(const Duration(days: 2)),
        ),
        _r(
          id: '1',
          gachaType: '301',
          rank: 5,
          time: t0.add(const Duration(days: 1)),
        ),
      ],
    };
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => BannerTopRarityBars(
          types: gachaTypes,
          banners: banners,
          colors: colors,
        ),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(BannerTopRarityBars)),
    )!;
    // count = 1 appears once (others are 0)
    expect(find.text('1'), findsOneWidget);
    expect(find.text(l.bannerTopRarityPullsSinceLast(5, 2)), findsOneWidget);
  });

  testWidgets('100 (beginner) → subtitle always "已結束" even with 5★ records', (
    tester,
  ) async {
    final t0 = DateTime(2025, 1, 1);
    final banners = <String, List<WishRecord>>{
      '100': [_r(id: 'b1', gachaType: '100', rank: 5, time: t0)],
    };
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => BannerTopRarityBars(
          types: gachaTypes,
          banners: banners,
          colors: colors,
        ),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(BannerTopRarityBars)),
    )!;
    // Beginner pool count = 1; subtitle still "已結束" (not "暫無 5★")
    expect(find.text('1'), findsOneWidget);
    expect(find.text(l.pityBeginnerEnded), findsOneWidget);
    // 其他所有池仍顯示「暫無 5★」
    expect(find.text(l.pityNoFiveStar), findsNWidgets(gachaTypes.length - 1));
  });

  testWidgets('bar widthFactor = topCount / max(topCount across banners)', (
    tester,
  ) async {
    expect(
      gachaTypes.map((t) => t.gachaType).toList(),
      const ['301', '302', '500', '200', '100', '2000', '1000'],
      reason: 'test assumes gachaTypes order — update if order changes',
    );
    final t0 = DateTime(2025, 1, 1);
    // 301: 4×5★; 302: 1×5★; others: 0
    final banners = <String, List<WishRecord>>{
      '301': [
        for (var i = 0; i < 4; i++)
          _r(
            id: '301-$i',
            gachaType: '301',
            rank: 5,
            time: t0.add(Duration(days: i)),
          ),
      ],
      '302': [_r(id: '302-0', gachaType: '302', rank: 5, time: t0)],
    };
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => BannerTopRarityBars(
          types: gachaTypes,
          banners: banners,
          colors: colors,
        ),
      ),
    );
    final fractions = tester
        .widgetList<FractionallySizedBox>(
          find.descendant(
            of: find.byType(BannerTopRarityBars),
            matching: find.byType(FractionallySizedBox),
          ),
        )
        .toList();
    expect(fractions.length, gachaTypes.length);
    expect(fractions[0].widthFactor, 1.0);
    expect(fractions[1].widthFactor, closeTo(0.25, 1e-6));
    for (var i = 2; i < fractions.length; i++) {
      expect(fractions[i].widthFactor, 0.0);
    }
  });

  testWidgets('bar color matches BannerColors.colorFor(gachaType)', (
    tester,
  ) async {
    final t0 = DateTime(2025, 1, 1);
    final banners = <String, List<WishRecord>>{
      for (final t in gachaTypes)
        t.gachaType: [
          _r(
            id: '${t.gachaType}-0',
            gachaType: t.gachaType,
            rank: t.primaryPity.rank,
            time: t0,
          ),
        ],
    };
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => BannerTopRarityBars(
          types: gachaTypes,
          banners: banners,
          colors: colors,
        ),
      ),
    );
    final colors = BannerColors.of(
      Theme.of(tester.element(find.byType(BannerTopRarityBars))).brightness,
    );
    final containers = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(BannerTopRarityBars),
            matching: find.byType(Container),
          ),
        )
        .where(
          (c) => (c.decoration as BoxDecoration?)?.gradient is LinearGradient,
        )
        .toList();
    expect(containers.length, gachaTypes.length);
    for (var i = 0; i < gachaTypes.length; i++) {
      final gradient =
          (containers[i].decoration as BoxDecoration).gradient
              as LinearGradient;
      expect(gradient.colors.last, colors.colorFor(gachaTypes[i].gachaType));
    }
  });

  testWidgets('依每個 type 自己的 primaryPity.rank 算件數 — odes 4★', (tester) async {
    final eventOdes = gachaTypes.firstWhere((t) => t.gachaType == '2000');
    final standardOdes = gachaTypes.firstWhere((t) => t.gachaType == '1000');
    final t0 = DateTime(2025, 1, 1);
    final banners = <String, List<WishRecord>>{
      // 活動頌願 primary = 5★：只有 1 件 5★ 算入
      '2000': [
        _r(id: 'a', gachaType: '2000', rank: 5, time: t0),
        _r(
          id: 'b',
          gachaType: '2000',
          rank: 4,
          time: t0.add(const Duration(days: 1)),
        ),
      ],
      // 常駐頌願 primary = 4★：只有 1 件 4★ 算入（3★ 不算）
      '1000': [
        _r(id: 'c', gachaType: '1000', rank: 4, time: t0),
        _r(
          id: 'd',
          gachaType: '1000',
          rank: 3,
          time: t0.add(const Duration(days: 1)),
        ),
      ],
    };
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => BannerTopRarityBars(
          types: [eventOdes, standardOdes],
          banners: banners,
          colors: colors,
        ),
      ),
    );
    // 兩條 bar 各 1 件
    expect(find.text('1'), findsNWidgets(2));
  });
}
