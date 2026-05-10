import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';

@immutable
class RecordFilterState {
  const RecordFilterState({
    required this.filter,
    required this.sort,
  });

  final RecordFilter filter;
  final TableSort? sort;

  RecordFilterState copyWith({RecordFilter? filter}) =>
      RecordFilterState(filter: filter ?? this.filter, sort: sort);
}

class RecordFilterNotifier extends Notifier<RecordFilterState> {
  @override
  RecordFilterState build() {
    return const RecordFilterState(filter: RecordFilter(), sort: null);
  }

  void setFilter(RecordFilter filter) {
    state = RecordFilterState(filter: filter, sort: state.sort);
  }

  /// 三態循環：null 或其他欄 → desc → asc → null。
  void cycleSort(SortColumn column) {
    final cur = state.sort;
    final next = switch (cur) {
      null => TableSort(column: column, direction: SortDirection.desc),
      TableSort(column: final c, direction: SortDirection.desc)
          when c == column =>
        TableSort(column: column, direction: SortDirection.asc),
      TableSort(column: final c, direction: SortDirection.asc) when c == column
        => null,
      _ => TableSort(column: column, direction: SortDirection.desc),
    };
    state = RecordFilterState(filter: state.filter, sort: next);
  }

  void clear() {
    state = const RecordFilterState(filter: RecordFilter(), sort: null);
  }
}

final recordFilterProvider = NotifierProvider.autoDispose.family<
    RecordFilterNotifier, RecordFilterState, String>(
        (gachaType) => RecordFilterNotifier());
