import 'dart:async';
import 'dart:math' as math;

/// 跑 [items] 一輪，最多 [concurrency] 個 worker 同時 in-flight。
///
/// - [worker] 拋例外不會中斷其他 worker；caller 應在 worker 內自行 try/catch
///   並決定是否要 swallow。
/// - [shouldAbort] 在每個 worker 取下一筆前查；回 true 即所有 worker 早退。
/// - items 完成順序不保證，caller 不可依賴。
/// - [concurrency] 必須 ≥ 1，否則拋 [ArgumentError]。
Future<void> runConcurrent<T>({
  required List<T> items,
  required int concurrency,
  required Future<void> Function(T item) worker,
  required FutureOr<bool> Function() shouldAbort,
}) async {
  if (concurrency < 1) {
    throw ArgumentError.value(concurrency, 'concurrency', 'must be >= 1');
  }
  if (items.isEmpty) return;

  var next = 0;

  Future<void> spawn() async {
    while (true) {
      if (await shouldAbort()) return;
      final i = next++;
      if (i >= items.length) return;
      try {
        await worker(items[i]);
      } catch (_) {
        // 吞掉避免中斷其他 worker；caller 自行 log。
      }
    }
  }

  final n = math.min(concurrency, items.length);
  await Future.wait(List.generate(n, (_) => spawn()));
}
