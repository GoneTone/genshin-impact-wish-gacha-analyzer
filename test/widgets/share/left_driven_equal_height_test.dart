import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/left_driven_equal_height.dart';

const _leftKey = Key('ldeh-left');
const _rightKey = Key('ldeh-right');

Future<void> _pump(WidgetTester t, double leftH, double rightNaturalH) async {
  // 預設測試畫面僅 800px 寬，SizedBox(width: 1000) 會被夾擠；放大畫面讓
  // LeftDrivenEqualHeight 真的拿到 1000px 寬度（對齊分享圖固定寬度的情境）。
  await t.binding.setSurfaceSize(const Size(1400, 800));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 1000,
          child: LeftDrivenEqualHeight(
            children: [
              SizedBox(key: _leftKey, height: leftH),
              SizedBox(key: _rightKey, height: rightNaturalH),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('右欄高被強制 = 左欄高（右自然較高 → 不撐大整體）', (t) async {
    await _pump(t, 300, 1000);
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byKey(_rightKey)).height, closeTo(300, 0.01));
    expect(t.getSize(find.byKey(_leftKey)).height, closeTo(300, 0.01));
    expect(
      t.getSize(find.byType(LeftDrivenEqualHeight)).height,
      closeTo(300, 0.01),
    );
  });

  testWidgets('右欄高被強制 = 左欄高（右自然較矮 → 仍撐到左欄高）', (t) async {
    await _pump(t, 300, 50);
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byKey(_rightKey)).height, closeTo(300, 0.01));
  });

  testWidgets('寬度依 11:9 + AppSpacing.l 間距切分', (t) async {
    await _pump(t, 200, 200);
    const contentW = 1000 - AppSpacing.l;
    expect(
      t.getSize(find.byKey(_leftKey)).width,
      closeTo(contentW * 11 / 20, 0.01),
    );
    expect(
      t.getSize(find.byKey(_rightKey)).width,
      closeTo(contentW * 9 / 20, 0.01),
    );
    final leftRight = t.getTopRight(find.byKey(_leftKey)).dx;
    final rightLeft = t.getTopLeft(find.byKey(_rightKey)).dx;
    expect(rightLeft - leftRight, closeTo(AppSpacing.l, 0.01));
  });
}
