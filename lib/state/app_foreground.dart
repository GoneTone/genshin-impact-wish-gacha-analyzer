import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App 是否在前景，以及等它回到前景。
///
/// 新版 Android 會擋背景 App 的網路（`APP_BACKGROUND`），玩家還在遊戲裡時就拿到祈願紀錄網址，
/// 抓資料會立刻 DNS 失敗；所以要等玩家切回本 App 再開始抓。
class AppForeground {
  /// App 目前是否在前景；還沒有 binding（純 Dart 測試）時視為前景。
  bool get isForeground {
    try {
      final state = WidgetsBinding.instance.lifecycleState;
      return state == null || state == AppLifecycleState.resumed;
    } catch (_) {
      return true;
    }
  }

  /// 等到 App 回到前景（已在前景時立刻完成）。
  Future<void> untilForeground() {
    if (isForeground) return Future.value();
    final resumed = Completer<void>();
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(
      onResume: () {
        listener.dispose();
        if (!resumed.isCompleted) resumed.complete();
      },
    );
    return resumed.future;
  }
}

/// 提供 [AppForeground]，測試可 override。
final appForegroundProvider = Provider<AppForeground>((ref) => AppForeground());
