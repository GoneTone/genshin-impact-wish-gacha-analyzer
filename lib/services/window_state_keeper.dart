import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// 視窗最小尺寸（寬 × 高，dp）。
const Size _kMinWindowSize = Size(800, 450);

/// 計算預設視窗大小時留的邊距（dp）。
const double _kMargin = 100;

/// 判斷 saved bounds 是否「在螢幕上」的最低重疊比例。
const double _kOnScreenOverlapRatio = 0.3;

/// 根據工作區大小計算預設視窗尺寸（16:9 比例，留 [margin] 邊距）。
@visibleForTesting
Size computeDefaultWindowSize(Size workArea, {double margin = _kMargin}) {
  final w = workArea.width;
  final h = workArea.height;

  // 極端小螢幕保護：未達 200dp 直接走 fallback
  if (w < 200 || h < 200) {
    return _kMinWindowSize;
  }

  late Size raw;
  if (w > h) {
    final height = h - margin;
    raw = Size(height * 16 / 9, height);
  } else if (h > w) {
    final width = (w - margin) * 9 / 16;
    raw = Size(width, width * 16 / 9);
  } else {
    raw = Size(w - margin, h - margin);
  }

  // 兩個維度都低於最小尺寸 → 視為螢幕太小，fallback 到 min。
  // 單一維度低於（例如 portrait 螢幕 9:16 寬度<800）則保留比例信任公式，
  // 由 setMinimumSize 在使用者拖拉時提供下限保護。
  if (raw.width < _kMinWindowSize.width &&
      raw.height < _kMinWindowSize.height) {
    return _kMinWindowSize;
  }
  return raw;
}

/// 決定視窗初始 bounds：[saved] 有效且有足夠螢幕重疊時沿用，否則置中公式。
@visibleForTesting
Rect resolveInitialBounds({
  required Rect? saved,
  required List<Rect> displayVisibleRects,
}) {
  final primary = displayVisibleRects.isNotEmpty
      ? displayVisibleRects.first
      : const Rect.fromLTWH(0, 0, 1280, 720);

  Rect formulaCentered() {
    final size = computeDefaultWindowSize(primary.size);
    final dx = primary.left + (primary.width - size.width) / 2;
    final dy = primary.top + (primary.height - size.height) / 2;
    return Rect.fromLTWH(dx, dy, size.width, size.height);
  }

  if (saved == null) return formulaCentered();

  final savedArea = saved.width * saved.height;
  if (savedArea <= 0) return formulaCentered();

  for (final d in displayVisibleRects) {
    final overlap = saved.intersect(d);
    if (overlap.isEmpty) continue;
    final overlapArea = overlap.width * overlap.height;
    if (overlapArea / savedArea >= _kOnScreenOverlapRatio) {
      return saved;
    }
  }
  return formulaCentered();
}

/// 監聽視窗移動/縮放事件並持久化 bounds；重啟時自動恢復上次位置。
class WindowStateKeeper with WindowListener {
  /// 私有建構；透過 [bootstrap] 初始化。
  WindowStateKeeper._(this._prefs);

  /// SharedPreferences key：視窗左上角 x 座標。
  static const _kX = 'window.state.x';

  /// SharedPreferences key：視窗左上角 y 座標。
  static const _kY = 'window.state.y';

  /// SharedPreferences key：視窗寬度。
  static const _kWidth = 'window.state.width';

  /// SharedPreferences key：視窗高度。
  static const _kHeight = 'window.state.height';

  /// SharedPreferences key：是否最大化。
  static const _kMaximized = 'window.state.isMaximized';

  /// 視窗狀態寫入 debounce 間隔。
  static const _kSaveDebounce = Duration(milliseconds: 800);

  /// SharedPreferences 實例，用於持久化視窗狀態。
  final SharedPreferences _prefs;

  /// debounce timer，[_scheduleSave] 使用。
  Timer? _debounceTimer;

  /// 初始化視窗：讀取持久化狀態 → 解析初始 bounds → 套用 → 開始監聽。
  /// 呼叫端負責先 await `windowManager.ensureInitialized()`。
  static Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final keeper = WindowStateKeeper._(prefs);

    final saved = keeper._loadSaved();
    final wasMaximized = prefs.getBool(_kMaximized) ?? false;

    final displays = await screenRetriever.getAllDisplays();
    final visibleRects = displays.map((d) {
      final pos = d.visiblePosition ?? Offset.zero;
      final size = d.visibleSize ?? d.size;
      return Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
    }).toList();

    final bounds = resolveInitialBounds(
      saved: saved,
      displayVisibleRects: visibleRects,
    );

    const opts = WindowOptions(skipTaskbar: false);
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.setMinimumSize(_kMinWindowSize);
      await windowManager.setBounds(bounds);
      if (wasMaximized) {
        await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
    });

    windowManager.addListener(keeper);
  }

  /// 取消 debounce 並立即觸發儲存。
  void _flushNow() {
    _debounceTimer?.cancel();
    unawaited(_saveNow());
  }

  /// 從 SharedPreferences 讀取上次儲存的視窗 bounds；四個值任一缺漏則回傳 null。
  Rect? _loadSaved() {
    final x = _prefs.getDouble(_kX);
    final y = _prefs.getDouble(_kY);
    final w = _prefs.getDouble(_kWidth);
    final h = _prefs.getDouble(_kHeight);
    if (x == null || y == null || w == null || h == null) return null;
    return Rect.fromLTWH(x, y, w, h);
  }

  /// 重設 debounce timer，[_kSaveDebounce] 後觸發儲存。
  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_kSaveDebounce, () => unawaited(_saveNow()));
  }

  /// 立即讀取並儲存目前視窗狀態。
  Future<void> _saveNow() async {
    final isMax = await windowManager.isMaximized();
    await _prefs.setBool(_kMaximized, isMax);
    // 最大化時刻意不覆蓋 x/y/w/h，保留上次「非最大化」的值。
    if (!isMax) {
      final b = await windowManager.getBounds();
      await _prefs.setDouble(_kX, b.left);
      await _prefs.setDouble(_kY, b.top);
      await _prefs.setDouble(_kWidth, b.width);
      await _prefs.setDouble(_kHeight, b.height);
    }
  }

  @override
  void onWindowResize() => _scheduleSave();

  @override
  void onWindowMove() => _scheduleSave();

  /// 拖拉縮放結束時立即 flush，避免依賴 debounce 而漏寫最後一次狀態。
  @override
  void onWindowResized() => _flushNow();

  @override
  void onWindowMoved() => _flushNow();

  @override
  void onWindowMaximize() => _flushNow();

  @override
  void onWindowUnmaximize() => _flushNow();
}
