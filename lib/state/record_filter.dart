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
  final RecordSort sort;

  RecordFilterState copyWith({RecordFilter? filter, RecordSort? sort}) =>
      RecordFilterState(
        filter: filter ?? this.filter,
        sort: sort ?? this.sort,
      );
}

class RecordFilterNotifier extends Notifier<RecordFilterState> {
  @override
  RecordFilterState build() {
    return const RecordFilterState(
      filter: RecordFilter(),
      sort: RecordSort.timeDesc,
    );
  }

  void setFilter(RecordFilter filter) {
    state = state.copyWith(filter: filter);
  }

  void setSort(RecordSort sort) {
    state = state.copyWith(sort: sort);
  }

  void clear() {
    state = const RecordFilterState(
      filter: RecordFilter(),
      sort: RecordSort.timeDesc,
    );
  }
}

final recordFilterProvider = NotifierProvider.autoDispose.family<
    RecordFilterNotifier, RecordFilterState, String>(
        (gachaType) => RecordFilterNotifier());
