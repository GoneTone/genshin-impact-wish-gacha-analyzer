import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/item_type_kind.dart';
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
          availableItemTypes: const [kItemKindCharacter, kItemKindWeapon],
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
          availableItemTypes: const [kItemKindCharacter, kItemKindWeapon],
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
          availableItemTypes: const [
            kItemKindCharacter,
            kItemKindWeapon,
            '裝扮',
          ],
          onFilterChanged: (_) {},
          onClear: () {},
        ),
      ),
    );
    // rarity dropdown + itemType dropdown 共兩個
    expect(find.byType(DropdownButton<RarityFilter>), findsOneWidget);
    expect(find.byType(DropdownButton<String?>), findsOneWidget);
  });

  testWidgets('下拉顯示 itemTypeKeyLabel 的在地化標籤', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SearchFilterBar(
          state: const RecordFilterState(filter: RecordFilter(), sort: null),
          availableItemTypes: const [kItemKindCharacter, kItemKindWeapon],
          onFilterChanged: (_) {},
          onClear: () {},
        ),
      ),
    );
    // 開 dropdown，確認顯示在地化標籤而非原始 key
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    // 測試環境預設英文：kindCharacter → 'Character'、kindWeapon → 'Weapon'
    expect(find.text('Character'), findsWidgets);
    expect(find.text('Weapon'), findsWidgets);
    // 確認原始 key 字串不直接顯示在 dropdown 選項中
    expect(find.text(kItemKindCharacter), findsNothing);
    expect(find.text(kItemKindWeapon), findsNothing);
  });

  testWidgets('選擇 itemType → onFilterChanged 收到對應聚合鍵', (tester) async {
    RecordFilter? captured;
    await tester.pumpWidget(
      _wrap(
        SearchFilterBar(
          state: const RecordFilterState(filter: RecordFilter(), sort: null),
          availableItemTypes: const [kItemKindCharacter, kItemKindWeapon],
          onFilterChanged: (f) => captured = f,
          onClear: () {},
        ),
      ),
    );

    // 開 dropdown
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    // 測試環境英文下 kItemKindCharacter 顯示為「Character」；點最後一個（menu item）
    final characterItems = find.text('Character');
    expect(characterItems, findsWidgets);
    await tester.tap(characterItems.last);
    await tester.pumpAndSettle();

    // filter.itemType 儲存的是聚合鍵，非顯示標籤
    expect(captured?.itemType, kItemKindCharacter);
  });

  testWidgets('fallback 原始字串直接顯示原字串', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SearchFilterBar(
          state: const RecordFilterState(filter: RecordFilter(), sort: null),
          availableItemTypes: const ['服裝'],
          onFilterChanged: (_) {},
          onClear: () {},
        ),
      ),
    );
    // 開 dropdown，非 canonical key 的原始字串應原樣顯示
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    expect(find.text('服裝'), findsWidgets);
  });
}
