// lib/services/window_state_keeper.dart
import 'dart:ui';

import 'package:flutter/foundation.dart';

const Size _kMinWindowSize = Size(800, 450);
const double _kMargin = 100;

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
    if (overlapArea / savedArea >= 0.3) {
      return saved;
    }
  }
  return formulaCentered();
}
