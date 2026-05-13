// lib/state/clock_tick.dart
//
// 每 30 秒 emit 一次 `DateTime.now()`，給需要顯示相對時間的 UI 訂閱。
// 取出的值本身可以不使用 — 只要 watch 它就會跟著 rebuild。

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 每 30 秒 emit 一次 `DateTime.now()`。
///
/// 訂閱對象: footer / 帳號卡片 / 帳號匯入對話框 / 新版本對話框。
/// 取出的值本身可以不使用 — 只要 watch 它就會跟著 rebuild。
final clockTickProvider = StreamProvider<DateTime>((ref) {
  return Stream<DateTime>.periodic(
    const Duration(seconds: 30),
    (_) => DateTime.now(),
  );
});
