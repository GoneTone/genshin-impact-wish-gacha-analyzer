import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/pity_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_horizontal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_node.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/pager.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/scroll/scroll_affordance.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/uid_indicator.dart';

// 阿拉伯文、希伯來文會讓整個畫面左右鏡像；寫死 left／right 的元件會跑錯邊。

TimelineEntry _e(String name, int pulls, DateTime time) => TimelineEntry(
  name: name,
  gachaType: '301',
  time: time,
  pullsSincePrev: pulls,
);

/// 以阿拉伯文（由右往左）建出 [build] 的內容，寬 [width]。
Widget _rtl(
  Widget Function(BuildContext ctx, BannerColors colors) build, {
  double width = 600,
}) => ProviderScope(
  child: MaterialApp(
    theme: buildDarkTheme(),
    locale: const Locale('ar'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: Builder(
          builder: (ctx) =>
              build(ctx, BannerColors.of(Theme.of(ctx).brightness)),
        ),
      ),
    ),
  ),
);

/// 取出 [root] 底下第一個 Container 的邊框。
BoxBorder? _firstBorder(WidgetTester tester, Finder root) {
  final box = tester.widget<Container>(
    find.descendant(of: root, matching: find.byType(Container)).first,
  );
  return (box.decoration! as BoxDecoration).border;
}

void main() {
  testWidgets('horizontal timeline: the start edge (arrow and fade) is on '
      'the right', (tester) async {
    await tester.pumpWidget(
      _rtl(
        (ctx, colors) => SizedBox(
          height: 160,
          child: TimelineHorizontal(
            entries: [
              for (var i = 0; i < 20; i++)
                _e('角色$i', 50 + i, DateTime(2026, 1, 1 + i)),
            ],
            targetRank: 5,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 剛進頁面捲動位置在起點（右邊），只有結束側（左邊）還有內容可捲。
    final arrows = find.byType(ScrollArrowButton);
    expect(arrows, findsOneWidget);
    expect(tester.getCenter(arrows).dx, lessThan(300));
    expect(tester.getCenter(find.byType(ScrollEdgeFade)).dx, lessThan(300));
  });

  testWidgets('vertical timeline: the rail runs through the dots', (
    tester,
  ) async {
    await tester.pumpWidget(
      _rtl(
        (ctx, colors) => TimelineVertical(
          entries: [
            _e('甲', 60, DateTime(2026, 2, 1)),
            _e('乙', 70, DateTime(2026, 1, 1)),
          ],
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rail = find.byWidgetPredicate(
      (w) => w is PositionedDirectional && w.width == 2,
    );
    expect(rail, findsOneWidget);
    final dot = find.byType(TimelineNode).first;
    expect(tester.getCenter(rail).dx, closeTo(tester.getCenter(dot).dx, 2));
    expect(tester.getCenter(dot).dx, greaterThan(300));
  });

  testWidgets('pager keeps "1 / 81" in reading order', (tester) async {
    await tester.pumpWidget(
      _rtl((ctx, colors) => Pager(page: 0, totalPages: 81, onChanged: (_) {})),
    );
    final label = tester.widget<Text>(find.text('1 / 81'));
    expect(label.textDirection, TextDirection.ltr);
  });

  testWidgets('stat card accent bar sits on the start (right) side', (
    tester,
  ) async {
    await tester.pumpWidget(
      _rtl(
        (ctx, colors) =>
            const StatCard(label: 'L', value: '1', accent: Colors.red),
      ),
    );
    final border = _firstBorder(tester, find.byType(StatCard))!;
    expect(border, isA<BorderDirectional>());
    expect(border.dimensions.resolve(TextDirection.rtl).right, 3);
    expect(border.dimensions.resolve(TextDirection.rtl).left, 0);
  });

  testWidgets('pity card: accent bar on the right, bar fills from the right, '
      'and "5 / 80" keeps its order', (tester) async {
    await tester.pumpWidget(
      _rtl(
        (ctx, colors) => const PityCard(
          label: 'L',
          rank: 5,
          pity: Pity(
            current: 5,
            threshold: 80,
            lastRecordAt: null,
            averageInterval: null,
            hitCount: 0,
            completedPulls: 0,
          ),
          accent: Colors.amber,
        ),
        width: 280,
      ),
    );
    final border = _firstBorder(tester, find.byType(PityCard))!;
    expect(border, isA<BorderDirectional>());
    expect(border.dimensions.resolve(TextDirection.rtl).right, 3);

    final fill = find.descendant(
      of: find.byType(PityCard),
      matching: find.byType(FractionallySizedBox),
    );
    expect(fill, findsOneWidget);
    final track = tester.getRect(
      find.ancestor(of: fill, matching: find.byType(ClipRRect)).first,
    );
    expect(tester.getTopRight(fill).dx, closeTo(track.right, 1));

    final current = tester.widget<Text>(find.text('5 / 80'));
    expect(current.textDirection, TextDirection.ltr);
  });

  testWidgets('masked UID keeps its digits first', (tester) async {
    await tester.pumpWidget(
      _rtl(
        (ctx, colors) => const AccountTriggerLabel(
          activeUid: '701000000',
          alias: '我的帳號',
          maskUid: true,
        ),
      ),
    );
    final uid = tester.widget<Text>(find.text('(701••••••) '));
    expect(uid.textDirection, TextDirection.ltr);
  });
}
