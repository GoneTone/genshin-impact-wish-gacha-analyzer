import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';

void main() {
  test('預設值為空篩選 + 時間 desc', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container.read(recordFilterProvider('301'));
    expect(state.filter.rarity, RarityFilter.all);
    expect(state.filter.kind, KindFilter.all);
    expect(state.filter.query, '');
    expect(state.sort, RecordSort.timeDesc);
  });

  test('setFilter / setSort 各卡池獨立', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(recordFilterProvider('301').notifier).setFilter(
        const RecordFilter(rarity: RarityFilter.fiveStar));
    container.read(recordFilterProvider('302').notifier).setSort(
        RecordSort.rarityDesc);

    expect(container.read(recordFilterProvider('301')).filter.rarity,
        RarityFilter.fiveStar);
    expect(container.read(recordFilterProvider('301')).sort,
        RecordSort.timeDesc);
    expect(container.read(recordFilterProvider('302')).filter.rarity,
        RarityFilter.all);
    expect(container.read(recordFilterProvider('302')).sort,
        RecordSort.rarityDesc);
  });

  test('clear 重置為預設', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier =
        container.read(recordFilterProvider('301').notifier);
    notifier.setFilter(const RecordFilter(query: 'foo'));
    notifier.setSort(RecordSort.rarityAsc);
    notifier.clear();
    final state = container.read(recordFilterProvider('301'));
    expect(state.filter.query, '');
    expect(state.sort, RecordSort.timeDesc);
  });
}
