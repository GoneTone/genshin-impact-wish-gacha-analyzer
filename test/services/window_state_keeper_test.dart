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
      // workArea 200×201：橫向分支，height=101，width=101*16/9≈179
      // → 同時小於最小 (800, 450) → clamp
      final size = computeDefaultWindowSize(const Size(201, 200));
      expect(size.width, 800);
      expect(size.height, 450);
    });
  });
}
