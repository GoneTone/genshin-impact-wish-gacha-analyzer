import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/banner_top_rarity_bars.dart';

GachaRecord _r({
  required String id,
  required String gachaType,
  required int rank,
  required DateTime time,
  String name = 'X',
  String itemType = '角色',
}) => GachaRecord(
  id: id,
  uid: '100000000',
  gachaType: gachaType,
  name: name,
  itemType: itemType,
  rankType: rank,
  time: time,
  lang: 'zh-tw',
);

Widget _wrap(
  Widget Function(BuildContext ctx, BannerColors colors) build, {
  Locale? locale,
  double width = 800,
  // 7 rows × ~2 wrapped lines × ~24px + 間距/padding ≈ 480
  double height = 480,
}) => MaterialApp(
  theme: buildDarkTheme(),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SizedBox(
      width: width,
      height: height,
      child: Builder(
        builder: (ctx) {
          final colors = BannerColors.of(Theme.of(ctx).brightness);
          return build(ctx, colors);
        },
      ),
    ),
  ),
);

/// [finder] 文字每一行實際字形的右緣（全域座標），用來判斷是否靠右對齊。
///
/// 略過空白字元：換行處的行尾空白會懸出段落寬度之外，不算可見字形。
List<double> _lineRights(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final text = paragraph.text.toPlainText();
  final boxes = [
    for (var i = 0; i < text.length; i++)
      if (text[i].trim().isNotEmpty)
        ...paragraph.getBoxesForSelection(
          TextSelection(baseOffset: i, extentOffset: i + 1),
        ),
  ];
  final rightByLine = <double, double>{};
  for (final b in boxes) {
    rightByLine.update(
      b.top,
      (r) => r > b.right ? r : b.right,
      ifAbsent: () => b.right,
    );
  }
  return [
    for (final r in rightByLine.values)
      paragraph.localToGlobal(Offset(r, 0)).dx,
  ];
}

/// 斷言每個卡池的說明文字每一行右緣都貼齊 [BannerTopRarityBars] 右緣。
void _expectSubtitlesFlushRight(WidgetTester tester) {
  final l = AppLocalizations.of(
    tester.element(find.byType(BannerTopRarityBars)),
  )!;
  final edge = tester.getRect(find.byType(BannerTopRarityBars)).right;
  final subtitles = [
    find.text(l.bannerTopRarityPullsSinceLast(l.rarityStar(5), 25)),
    find.text(l.pityNoMainRarity(l.rarityStar(5))),
    find.text(l.pityNoMainRarity(l.rarityStar(4))),
    find.text(l.pityBeginnerEnded),
  ];
  var checked = 0;
  for (final s in subtitles) {
    for (var i = 0; i < s.evaluate().length; i++) {
      checked++;
      for (final right in _lineRights(tester, s.at(i))) {
        expect(right, closeTo(edge, 0.5));
      }
    }
  }
  expect(checked, gachaTypes.length);
}

void main() {
  for (final (locale, width, scale) in [
    (const Locale('zh'), 800.0, 1.0),
    (const Locale('en'), 800.0, 1.0),
    // 寬版門檻附近，英文說明會換行。
    (const Locale('en'), 420.0, 1.0),
    // 放大字級時說明換行更多，仍不得溢出、右緣仍要對齊。
    for (final lang in ['en', 'ja'])
      for (final w in [800.0, 420.0]) (Locale(lang), w, 1.3),
    // 上下兩行版：短名稱與會換行的長名稱並存，各列數字仍要貼齊右緣。
    // 測試字型每字等寬，英文名稱全會換行；中文名稱短，才測得到不換行的列。
    (const Locale('zh'), 360.0, 1.0),
    (const Locale('en'), 360.0, 1.0),
    for (final lang in ['en', 'ja'])
      for (final w in [320.0, 419.0]) (Locale(lang), w, 1.3),
  ]) {
    testWidgets('trailing stats end flush at the right edge '
        '(${locale.languageCode}, $width, ${scale}x)', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1600);
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final t0 = DateTime(2025, 1, 1);
      final banners = <String, List<GachaRecord>>{
        '301': [
          for (var i = 0; i < 25; i++)
            _r(
              id: '4-$i',
              gachaType: '301',
              rank: 4,
              time: t0.add(Duration(days: 30 - i)),
            ),
          _r(id: '5', gachaType: '301', rank: 5, time: t0),
        ],
      };
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => BannerTopRarityBars(
            types: gachaTypes,
            banners: banners,
            colors: colors,
          ),
          locale: locale,
          width: width,
          height: 1600, // 放大字級換行後仍放得下，避免容器溢出掩蓋對齊斷言
        ),
      );
      await tester.pumpAndSettle();
      _expectSubtitlesFlushRight(tester);
      expect(tester.takeException(), isNull);
    });
  }

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
    // 除新手池 (100) 顯示「已結束」、常駐頌願 (1000) 主稀有度為 4★ 顯示
    // 「暫無 4★」外，其餘 5 池主稀有度為 5★ 顯示「暫無 5★」
    final gachaAndEventOdes = gachaTypes
        .where((t) => t.gachaType != '100' && t.primaryPity.rank == 5)
        .length;
    expect(
      find.text(l.pityNoMainRarity(l.rarityStar(5))),
      findsNWidgets(gachaAndEventOdes),
    );
    expect(find.text(l.pityNoMainRarity(l.rarityStar(4))), findsOneWidget);
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
    final banners = <String, List<GachaRecord>>{
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
    expect(
      find.text(l.bannerTopRarityPullsSinceLast(l.rarityStar(5), 2)),
      findsOneWidget,
    );
  });

  testWidgets('100 (beginner) → subtitle always "已結束" even with 5★ records', (
    tester,
  ) async {
    final t0 = DateTime(2025, 1, 1);
    final banners = <String, List<GachaRecord>>{
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
    // 其他主稀有度 5★ 的池仍顯示「暫無 5★」；常駐頌願 (1000) 主稀有度為 4★
    final gachaAndEventOdes = gachaTypes
        .where((t) => t.gachaType != '100' && t.primaryPity.rank == 5)
        .length;
    expect(
      find.text(l.pityNoMainRarity(l.rarityStar(5))),
      findsNWidgets(gachaAndEventOdes),
    );
    expect(find.text(l.pityNoMainRarity(l.rarityStar(4))), findsOneWidget);
  });

  testWidgets('bar widthFactor = topCount / max(topCount across banners)', (
    tester,
  ) async {
    expect(gachaTypes.map((t) => t.gachaType).toList(), const [
      '301',
      '302',
      '500',
      '200',
      '100',
      '2000',
      '1000',
    ], reason: 'test assumes gachaTypes order — update if order changes');
    final t0 = DateTime(2025, 1, 1);
    // 301: 4×5★; 302: 1×5★; others: 0
    final banners = <String, List<GachaRecord>>{
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
    final banners = <String, List<GachaRecord>>{
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
    final banners = <String, List<GachaRecord>>{
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

  testWidgets('英文窄視窗：名稱/說明不截斷（無 ellipsis）、bar 仍渲染', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => BannerTopRarityBars(
          types: gachaTypes,
          banners: const {},
          colors: colors,
        ),
        locale: const Locale('en'),
        width: 360, // 刻意窄，逼出換行
        // 窄欄 width:360 下換行更多行,7 rows × ~3 lines × ~24px ≈ 504,取 600 留 margin
        height: 600, // 足夠高度，避免七列換行觸發 RenderFlex overflow 掩蓋真正斷言
      ),
    );
    // 等 locale 切換 / 版面 settle 完成
    await tester.pumpAndSettle();

    final l = AppLocalizations.of(
      tester.element(find.byType(BannerTopRarityBars)),
    )!;

    // 名稱 Text 不得有 ellipsis（完整換行顯示）
    // 取 gachaTypes.first（301 角色活動祈願）的 en 名稱
    final firstName = gachaTypes.first.resolveName(l);
    final nameText = tester.widget<Text>(find.text(firstName));
    expect(nameText.overflow, isNot(TextOverflow.ellipsis));
    expect(nameText.maxLines, isNull);

    // 右側 subtitle Text 不得有 ellipsis（空 banners → "No 5★ yet"）
    // 對所有符合的 subtitle Text 逐一斷言
    final noMainRarityStr = l.pityNoMainRarity(l.rarityStar(5));
    for (final subtitleText in tester.widgetList<Text>(
      find.text(noMainRarityStr),
    )) {
      expect(subtitleText.overflow, isNot(TextOverflow.ellipsis));
      expect(subtitleText.maxLines, isNull);
    }

    // bar 仍每列渲染
    expect(
      find.descendant(
        of: find.byType(BannerTopRarityBars),
        matching: find.byType(FractionallySizedBox),
      ),
      findsNWidgets(gachaTypes.length),
    );

    // 版面未拋 overflow 例外
    expect(tester.takeException(), isNull);
  });
}
