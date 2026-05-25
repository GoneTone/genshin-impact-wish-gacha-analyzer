import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/concurrent_pool.dart';

void main() {
  group('runConcurrent', () {
    test('N 個 worker 真同時 in-flight', () async {
      final completers = List.generate(8, (_) => Completer<void>());
      var maxInFlight = 0;
      var current = 0;
      final futures = runConcurrent<int>(
        items: List.generate(8, (i) => i),
        concurrency: 4,
        shouldAbort: () => false,
        worker: (i) async {
          current++;
          if (current > maxInFlight) maxInFlight = current;
          await completers[i].future;
          current--;
        },
      );
      // 等所有 worker 都進到 await
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(maxInFlight, 4);
      for (final c in completers) {
        c.complete();
      }
      await futures;
    });

    test('單一 worker 拋例外不中斷其他 worker', () async {
      final done = <int>[];
      await runConcurrent<int>(
        items: const [0, 1, 2, 3, 4],
        concurrency: 2,
        shouldAbort: () => false,
        worker: (i) async {
          if (i == 2) throw StateError('boom');
          done.add(i);
        },
      );
      expect(done..sort(), [0, 1, 3, 4]);
    });

    test('shouldAbort 第一輪即 true 時不執行任何 item', () async {
      final done = <int>[];
      await runConcurrent<int>(
        items: const [0, 1, 2],
        concurrency: 2,
        shouldAbort: () => true,
        worker: (i) async {
          done.add(i);
        },
      );
      expect(done, isEmpty);
    });

    test('items 為空時不起任何 worker，立刻 resolve', () async {
      var calls = 0;
      await runConcurrent<int>(
        items: const [],
        concurrency: 4,
        shouldAbort: () => false,
        worker: (_) async {
          calls++;
        },
      );
      expect(calls, 0);
    });

    test('completion 順序不保證但所有 item 都跑過', () async {
      final done = <int>[];
      await runConcurrent<int>(
        items: List.generate(20, (i) => i),
        concurrency: 5,
        shouldAbort: () => false,
        worker: (i) async {
          await Future<void>.delayed(Duration(milliseconds: (i * 7) % 20));
          done.add(i);
        },
      );
      expect(done..sort(), List.generate(20, (i) => i));
    });
  });
}
