// lib/widgets/share/left_driven_equal_height.dart
//
// 兩欄版面：左欄以自然高度 layout，量得其高 H 後，強制右欄高度也為 H。
// 右欄超出 H 的部分由右欄自身（TimelineVertical 的 fillHeight 分支）clip，
// 本元件不負責裁切。寬度依固定 flex 11:9 + AppSpacing.l 間距切分。
// children 必須恰為兩個：index 0 = 左、index 1 = 右。
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class LeftDrivenEqualHeight extends MultiChildRenderObjectWidget {
  const LeftDrivenEqualHeight({super.key, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLeftDrivenEqualHeight();
}

class _LDParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderLeftDrivenEqualHeight extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _LDParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _LDParentData> {
  static const double _leftFlex = 11;
  static const double _rightFlex = 9;
  static const double _gap = AppSpacing.l;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LDParentData) {
      child.parentData = _LDParentData();
    }
  }

  ({double leftW, double rightW}) _split(double maxWidth) {
    final contentW = maxWidth - _gap;
    final leftW = contentW * _leftFlex / (_leftFlex + _rightFlex);
    return (leftW: leftW, rightW: contentW - leftW);
  }

  @override
  void performLayout() {
    assert(
      constraints.hasBoundedWidth,
      'LeftDrivenEqualHeight 需有界寬度（分享圖固定 1200）',
    );
    assert(childCount == 2, 'LeftDrivenEqualHeight 必須恰兩個 children');
    final maxW = constraints.maxWidth;
    final (:leftW, :rightW) = _split(maxW);

    final left = firstChild!;
    final right = childAfter(left)!;

    left.layout(BoxConstraints.tightFor(width: leftW), parentUsesSize: true);
    final leftH = left.size.height;
    right.layout(
      BoxConstraints.tightFor(width: rightW, height: leftH),
      parentUsesSize: true,
    );

    (left.parentData! as _LDParentData).offset = Offset.zero;
    (right.parentData! as _LDParentData).offset = Offset(leftW + _gap, 0);

    size = Size(maxW, leftH);
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final (:leftW, rightW: _) = _split(width);
    return firstChild!.getMinIntrinsicHeight(leftW);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final (:leftW, rightW: _) = _split(width);
    return firstChild!.getMaxIntrinsicHeight(leftW);
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      firstChild!.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      firstChild!.getMaxIntrinsicWidth(height);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final (:leftW, rightW: _) = _split(constraints.maxWidth);
    final leftSize = firstChild!.getDryLayout(
      BoxConstraints.tightFor(width: leftW),
    );
    return Size(constraints.maxWidth, leftSize.height);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
