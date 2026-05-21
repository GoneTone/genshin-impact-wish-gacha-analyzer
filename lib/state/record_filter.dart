import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_filter.dart';

/// 記錄列表的篩選條件與排序狀態。
@immutable
class RecordFilterState {
  /// 建立 [RecordFilterState]。
  const RecordFilterState({required this.filter, required this.sort});

  /// 目前的篩選條件。
  final RecordFilter filter;

  /// 目前的排序設定；null 表示依預設順序（id 降序）。
  final TableSort? sort;

  /// 複製並選擇性覆蓋 [filter]，sort 保持不變。
  RecordFilterState copyWith({RecordFilter? filter}) =>
      RecordFilterState(filter: filter ?? this.filter, sort: sort);
}

/// 記錄列表篩選與排序的 Riverpod notifier。
class RecordFilterNotifier extends Notifier<RecordFilterState> {
  @override
  RecordFilterState build() {
    return const RecordFilterState(filter: RecordFilter(), sort: null);
  }

  /// 套用新的篩選條件。
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
      TableSort(column: final c, direction: SortDirection.asc)
          when c == column =>
        null,
      _ => TableSort(column: column, direction: SortDirection.desc),
    };
    state = RecordFilterState(filter: state.filter, sort: next);
  }

  /// 重置篩選條件與排序為預設值。
  void clear() {
    state = const RecordFilterState(filter: RecordFilter(), sort: null);
  }
}

/// 每個 gacha_type 獨立的 [RecordFilterNotifier] provider，離開頁面自動釋放。
final recordFilterProvider = NotifierProvider.autoDispose
    .family<RecordFilterNotifier, RecordFilterState, String>(
      (gachaType) => RecordFilterNotifier(),
    );
