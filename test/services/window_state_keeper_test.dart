// test/services/window_state_keeper_test.dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/window_state_keeper.dart';

void main() {
  group('computeDefaultWindowSize', () {
    test('橫向 1920×1080 → 1742×980 (16:9)', () {
      final size = computeDefaultWindowSize(const Size(1920, 1080));
      expect(size.width, closeTo(1742.22, 0.5));
      expect(size.height, 980);
    });

    test('直向 1080×1920 → 551×980 (9:16)', () {
      final size = computeDefaultWindowSize(const Size(1080, 1920));
      expect(size.width, closeTo(551.25, 0.5));
      expect(size.height, 980);
    });

    test('正方形 1000×1000 → 900×900 (扣 100 fallback)', () {
      final size = computeDefaultWindowSize(const Size(1000, 1000));
      expect(size.width, 900);
      expect(size.height, 900);
    });

    test('極端小螢幕 150×100 → fallback 800×450', () {
      final size = computeDefaultWindowSize(const Size(150, 100));
      expect(size.width, 800);
      expect(size.height, 450);
    });

    test('結果小於最小尺寸時 clamp 到 800×450', () {
      // workArea 201×200：橫向分支，height=101，width=101*16/9≈179
      // → 同時小於最小 (800, 450) → clamp
      final size = computeDefaultWindowSize(const Size(201, 200));
      expect(size.width, 800);
      expect(size.height, 450);
    });
  });

  group('resolveInitialBounds', () {
    const primary = Rect.fromLTWH(0, 0, 1920, 1080);

    test('saved == null → 公式 + 居中 primary', () {
      final r = resolveInitialBounds(
        saved: null,
        displayVisibleRects: const [primary],
      );
      // 1920×1080 → window 1742×980；置中 → x≈89, y=50
      expect(r.width, closeTo(1742, 1));
      expect(r.height, 980);
      expect(r.left, closeTo(89, 1));
      expect(r.top, 50);
    });

    test('saved 完全在 primary 內 → 原樣回傳', () {
      const saved = Rect.fromLTWH(100, 100, 1280, 720);
      final r = resolveInitialBounds(
        saved: saved,
        displayVisibleRects: const [primary],
      );
      expect(r, saved);
    });

    test('saved 與螢幕重疊 < 30% → 公式 + 居中', () {
      // saved 大部分在 primary 外（模擬拔掉外接螢幕）
      const saved = Rect.fromLTWH(2500, 100, 1280, 720);
      final r = resolveInitialBounds(
        saved: saved,
        displayVisibleRects: const [primary],
      );
      expect(r.width, closeTo(1742, 1));
      expect(r.height, 980);
    });

    test('saved 與螢幕重疊 ≥ 30% → 原樣回傳', () {
      // saved Rect(1000, 100, 1280, 720)，與 primary 重疊面積 ≈ 920×720 = 662400
      // savedArea = 921600，ratio ≈ 0.72 > 0.3
      const saved = Rect.fromLTWH(1000, 100, 1280, 720);
      final r = resolveInitialBounds(
        saved: saved,
        displayVisibleRects: const [primary],
      );
      expect(r, saved);
    });

    test('saved 落在第二顯示器 → 原樣回傳', () {
      const secondary = Rect.fromLTWH(1920, 0, 1920, 1080);
      const saved = Rect.fromLTWH(2000, 100, 1280, 720);
      final r = resolveInitialBounds(
        saved: saved,
        displayVisibleRects: const [primary, secondary],
      );
      expect(r, saved);
    });

    test('displays 為空 → 用內建 fallback rect 公式 + 居中', () {
      final r = resolveInitialBounds(
        saved: null,
        displayVisibleRects: const [],
      );
      // fallback rect = 1280×720；公式：height=620, width=620*16/9≈1102
      expect(r.width, closeTo(1102, 1));
      expect(r.height, 620);
    });
  });
}
