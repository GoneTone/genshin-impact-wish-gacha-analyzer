import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';

void main() {
  DateTime t(int day) => DateTime.utc(2026, 5, day);

  group('mergeUidOrder', () {
    test('空 customOrder → 全部按 lastUpdated desc', () {
      final result = mergeUidOrder(
        knownUids: const ['A', 'B', 'C'],
        customOrder: const [],
        lastUpdatedOf: (u) => {'A': t(1), 'B': t(3), 'C': t(2)}[u]!,
      );
      expect(result, ['B', 'C', 'A']);
    });

    test('customOrder 全部覆蓋 → 維持 customOrder', () {
      final result = mergeUidOrder(
        knownUids: const ['A', 'B', 'C'],
        customOrder: const ['C', 'A', 'B'],
        lastUpdatedOf: (_) => t(1),
      );
      expect(result, ['C', 'A', 'B']);
    });

    test('customOrder 含已不存在的 UID → 過濾掉', () {
      final result = mergeUidOrder(
        knownUids: const ['A', 'B'],
        customOrder: const ['C', 'A', 'D', 'B'],
        lastUpdatedOf: (_) => t(1),
      );
      expect(result, ['A', 'B']);
    });

    test('customOrder 部分覆蓋 → 已排序的優先、新 UID 接尾端按 lastUpdated desc', () {
      final result = mergeUidOrder(
        knownUids: const ['A', 'B', 'C', 'D'],
        customOrder: const ['C', 'A'],
        lastUpdatedOf: (u) => {'A': t(1), 'B': t(2), 'C': t(3), 'D': t(4)}[u]!,
      );
      expect(result, ['C', 'A', 'D', 'B']);
    });

    test('knownUids 為空 → 回傳空 list', () {
      final result = mergeUidOrder(
        knownUids: const <String>[],
        customOrder: const ['A', 'B'],
        lastUpdatedOf: (_) => t(1),
      );
      expect(result, isEmpty);
    });
  });
}
