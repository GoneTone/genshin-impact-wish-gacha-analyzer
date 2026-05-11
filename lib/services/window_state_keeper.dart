// lib/services/window_state_keeper.dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const Size _kMinWindowSize = Size(800, 450);
const double _kMargin = 100;
const double _kOnScreenOverlapRatio = 0.3;

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

class WindowStateKeeper with WindowListener {
  WindowStateKeeper._(this._prefs);

  static const _kX = 'window.state.x';
  static const _kY = 'window.state.y';
  static const _kWidth = 'window.state.width';
  static const _kHeight = 'window.state.height';
  static const _kMaximized = 'window.state.isMaximized';
  static const _kSaveDebounce = Duration(milliseconds: 800);

  final SharedPreferences _prefs;
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

    await windowManager.setPreventClose(true);
    windowManager.addListener(keeper);
  }

  Rect? _loadSaved() {
    final x = _prefs.getDouble(_kX);
    final y = _prefs.getDouble(_kY);
    final w = _prefs.getDouble(_kWidth);
    final h = _prefs.getDouble(_kHeight);
    if (x == null || y == null || w == null || h == null) return null;
    return Rect.fromLTWH(x, y, w, h);
  }

  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_kSaveDebounce, () => unawaited(_saveNow()));
  }

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

  @override
  void onWindowMaximize() {
    _debounceTimer?.cancel();
    unawaited(_saveNow());
  }

  @override
  void onWindowUnmaximize() {
    _debounceTimer?.cancel();
    unawaited(_saveNow());
  }

  @override
  void onWindowClose() async {
    _debounceTimer?.cancel();
    try {
      await _saveNow();
    } finally {
      await windowManager.destroy();
    }
  }
}
