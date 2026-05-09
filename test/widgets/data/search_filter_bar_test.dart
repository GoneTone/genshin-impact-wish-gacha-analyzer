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
    await tester.pumpWidget(_wrap(SearchFilterBar(
      state: const RecordFilterState(
        filter: RecordFilter(),
        sort: RecordSort.timeDesc,
      ),
      onFilterChanged: (_) {},
      onSortChanged: (_) {},
      onClear: () {},
    )));
    // No TextButton present until filter is non-default
    final clearBtn = find.widgetWithIcon(TextButton, Icons.clear);
    expect(clearBtn, findsNothing);
  });

  testWidgets('clear button visible when filter active', (tester) async {
    await tester.pumpWidget(_wrap(SearchFilterBar(
      state: const RecordFilterState(
        filter: RecordFilter(rarity: RarityFilter.fiveStar),
        sort: RecordSort.timeDesc,
      ),
      onFilterChanged: (_) {},
      onSortChanged: (_) {},
      onClear: () {},
    )));
    final clearBtn = find.widgetWithIcon(TextButton, Icons.clear);
    expect(clearBtn, findsOneWidget);
  });
}
