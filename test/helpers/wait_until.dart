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
