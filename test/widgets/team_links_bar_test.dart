// test/widgets/team_links_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/team_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/team_links_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildDarkTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('TeamLinksBar 渲染 4 個社群 IconButton 與團隊名稱', (tester) async {
    await tester.pumpWidget(_wrap(const TeamLinksBar()));

    // 4 個社群 icon（用 FaIcon 找）
    expect(find.byType(FaIcon), findsNWidgets(4));

    // 團隊名稱出現
    expect(find.text(TeamInfo.name), findsOneWidget);
  });

  testWidgets('每個社群 IconButton 都有正確 tooltip', (tester) async {
    await tester.pumpWidget(_wrap(const TeamLinksBar()));

    for (final label in const ['Facebook', 'Discord', 'Line', 'GitHub']) {
      expect(
        find.byTooltip(label),
        findsOneWidget,
        reason: '應該有 tooltip 為 $label 的 IconButton',
      );
    }
  });

  testWidgets('4 個社群 IconButton 的 onPressed 都不為 null', (tester) async {
    await tester.pumpWidget(_wrap(const TeamLinksBar()));

    final buttons = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .toList();
    expect(buttons.length, 4);
    for (final b in buttons) {
      expect(b.onPressed, isNotNull);
    }
  });

  testWidgets('每個社群 IconButton 的 mouseCursor 為 SystemMouseCursors.click', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const TeamLinksBar()));

    final buttons = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .toList();
    for (final b in buttons) {
      expect(b.mouseCursor, SystemMouseCursors.click);
    }
  });

  testWidgets('團隊名稱被 AppLink 包住且 URL 為 TeamInfo.websiteUrl', (tester) async {
    await tester.pumpWidget(_wrap(const TeamLinksBar()));

    final appLink = tester.widget<AppLink>(find.byType(AppLink));
    expect(appLink.url, TeamInfo.websiteUrl);
  });

  testWidgets('點擊任一 IconButton 或團隊名稱不會拋例外', (tester) async {
    await tester.pumpWidget(_wrap(const TeamLinksBar()));

    await tester.tap(find.byTooltip('Facebook'));
    await tester.tap(find.byTooltip('Discord'));
    await tester.tap(find.byTooltip('Line'));
    await tester.tap(find.byTooltip('GitHub'));
    await tester.tap(find.text(TeamInfo.name));
    await tester.pumpAndSettle();
  });
}
