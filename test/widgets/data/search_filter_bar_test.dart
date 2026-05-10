import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
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
          onFilterChanged: (_) {},
          onClear: () {},
        ),
      ),
    );
    final clearBtn = find.widgetWithIcon(TextButton, Icons.clear);
    expect(clearBtn, findsOneWidget);
  });

  testWidgets('排序 dropdown 已不存在', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SearchFilterBar(
          state: const RecordFilterState(filter: RecordFilter(), sort: null),
          onFilterChanged: (_) {},
          onClear: () {},
        ),
      ),
    );
    // 只有兩個 dropdown：rarity / kind
    expect(find.byType(DropdownButton<RarityFilter>), findsOneWidget);
    expect(find.byType(DropdownButton<KindFilter>), findsOneWidget);
  });
}
