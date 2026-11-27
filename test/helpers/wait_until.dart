import 'package:flutter_test/flutter_test.dart';

/// 反覆讓出事件迴圈直到 [cond] 成立，超過 [timeout] 就讓測試失敗。
Future<void> waitUntil(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition never became true within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// widget 測試用：被測程式在背景 isolate 或真實檔案 I/O 做事、結果要真實時間才回來時，
/// 每輪讓背景跑一下（[WidgetTester.runAsync]）再推進畫面，直到 [cond] 成立
/// （最多 [timeout] 的實際時間），最後再 settle。
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!cond() && stopwatch.elapsed < timeout) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
