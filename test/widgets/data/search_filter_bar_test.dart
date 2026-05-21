import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/search_filter_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('clear button hidden when no active filter', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SearchFilterBar(
          state: const RecordFilterState(filter: RecordFilter(), sort: null),
          availableItemTypes: const ['角色', '武器'],
          onFilterChanged: (_) {},
          onClear: () {},
        ),
      ),
    );
    final clearBtn = find.widgetWithIcon(TextButton, Icons.clear);
    expect(clearBtn, findsNothing);
  });

  testWidgets('clear button visible when filter active', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SearchFilterBar(
          state: const RecordFilterState(
            filter: RecordFilter(rarity: RarityFilter.fiveStar),
            sort: null,
          ),
          availableItemTypes: const ['角色', '武器'],
          onFilterChanged: (_) {},
          onClear: () {},
        ),
      ),
    );
    final clearBtn = find.widgetWithIcon(TextButton, Icons.clear);
    expect(clearBtn, findsOneWidget);
  });

  testWidgets('itemType dropdown 依 availableItemTypes 動態列舉', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SearchFilterBar(
          state: const RecordFilterState(filter: RecordFilter(), sort: null),
          availableItemTypes: const ['角色', '武器', '裝扮'],
          onFilterChanged: (_) {},
          onClear: () {},
        ),
      ),
    );
    // rarity dropdown + itemType dropdown 共兩個
    expect(find.byType(DropdownButton<RarityFilter>), findsOneWidget);
    expect(find.byType(DropdownButton<String?>), findsOneWidget);
  });

  testWidgets('選擇 itemType → onFilterChanged 收到新的 itemType', (tester) async {
    RecordFilter? captured;
    await tester.pumpWidget(
      _wrap(
        SearchFilterBar(
          state: const RecordFilterState(filter: RecordFilter(), sort: null),
          availableItemTypes: const ['角色', '武器'],
          onFilterChanged: (f) => captured = f,
          onClear: () {},
        ),
      ),
    );

    // 開 dropdown
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    // 點 '角色' 選項（dropdown 開啟後菜單會有兩個 '角色' Text：一個 closed item，一個 menu item）
    final characterItems = find.text('角色');
    expect(characterItems, findsWidgets);
    await tester.tap(characterItems.last);
    await tester.pumpAndSettle();

    expect(captured?.itemType, '角色');
  });
}
