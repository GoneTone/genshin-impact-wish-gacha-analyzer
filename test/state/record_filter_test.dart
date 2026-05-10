import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';

void main() {
  test('預設值為空篩選 + sort=null', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container.read(recordFilterProvider('301'));
    expect(state.filter.rarity, RarityFilter.all);
    expect(state.filter.kind, KindFilter.all);
    expect(state.filter.query, '');
    expect(state.sort, isNull);
  });

  test('cycleSort：三態循環 null → desc → asc → null', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(recordFilterProvider('301').notifier);

    notifier.cycleSort(SortColumn.time);
    expect(
      container.read(recordFilterProvider('301')).sort,
      const TableSort(column: SortColumn.time, direction: SortDirection.desc),
    );

    notifier.cycleSort(SortColumn.time);
    expect(
      container.read(recordFilterProvider('301')).sort,
      const TableSort(column: SortColumn.time, direction: SortDirection.asc),
    );

    notifier.cycleSort(SortColumn.time);
    expect(container.read(recordFilterProvider('301')).sort, isNull);
  });

  test('cycleSort：換欄重置為 desc', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(recordFilterProvider('301').notifier);

    notifier.cycleSort(SortColumn.time); // time desc
    notifier.cycleSort(SortColumn.time); // time asc
    notifier.cycleSort(SortColumn.totalIndex); // 換欄 → totalIndex desc
    expect(
      container.read(recordFilterProvider('301')).sort,
      const TableSort(
        column: SortColumn.totalIndex,
        direction: SortDirection.desc,
      ),
    );
  });

  test('setFilter / cycleSort 各卡池獨立', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(recordFilterProvider('301').notifier)
        .setFilter(const RecordFilter(rarity: RarityFilter.fiveStar));
    container
        .read(recordFilterProvider('302').notifier)
        .cycleSort(SortColumn.rarity);

    expect(
      container.read(recordFilterProvider('301')).filter.rarity,
      RarityFilter.fiveStar,
    );
    expect(container.read(recordFilterProvider('301')).sort, isNull);
    expect(
      container.read(recordFilterProvider('302')).filter.rarity,
      RarityFilter.all,
    );
    expect(
      container.read(recordFilterProvider('302')).sort,
      const TableSort(column: SortColumn.rarity, direction: SortDirection.desc),
    );
  });

  test('clear 同時清 filter 與 sort', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(recordFilterProvider('301').notifier);
    notifier.setFilter(const RecordFilter(query: 'foo'));
    notifier.cycleSort(SortColumn.name);
    notifier.clear();
    final state = container.read(recordFilterProvider('301'));
    expect(state.filter.query, '');
    expect(state.sort, isNull);
  });
}
