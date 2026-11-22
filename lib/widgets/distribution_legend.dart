import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// Pie 圖例或色票說明的單一條目資料。
class DistributionEntry {
  /// 建立 [DistributionEntry]。
  const DistributionEntry({
    required this.color,
    required this.name,
    required this.count,
    required this.rate,
  });

  /// 色塊顏色。
  final Color color;

  /// 條目名稱。
  final String name;

  /// 數量。
  final int count;

  /// 佔比，範圍 0.0 ~ 1.0。
  final double rate;
}

/// 以色塊、名稱、數量、百分比呈現分佈資料的圖例列表。
class DistributionLegend extends StatelessWidget {
  /// 建立 [DistributionLegend]。
  const DistributionLegend({
    super.key,
    required this.entries,
    this.showAllEntries = false,
    this.compact = false,
  });

  /// 圖例條目列表。
  final List<DistributionEntry> entries;

  /// false (預設):過濾 count == 0 的條目 — Pie 圖例的慣例
  /// true:全部顯示 — 適合純色彩說明(如時間軸卡池色票)
  final bool showAllEntries;

  /// true：窄欄用的精簡版，件數與百分比欄寬縮小並隨字級縮放；名稱放不下時數字改排到下一行。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    // 欄寬依內文字實際放大的倍率縮放；Android 14 起字級是非線性的，直接 scale(58) 會把寬度
    // 當成大字、放大得比內文少而斷行。
    final bodySize = theme.textTheme.bodyMedium?.fontSize ?? 14;
    final widthFactor =
        MediaQuery.textScalerOf(context).scale(bodySize) / bodySize;
    // Roboto 14dp 下「12345」約 41dp、「100.00%」約 55dp，各留一點餘裕才不會斷行。
    // shortcut: 件數只量到五位數，六位數以上會斷行；真有帳號抽到十萬抽再改成依內容量寬。
    final countWidth = compact ? 44 * widthFactor : 60.0;
    final rateWidth = compact ? 58 * widthFactor : 70.0;
    final visible = showAllEntries
        ? entries
        : entries.where((e) => e.count > 0).toList(growable: false);

    final nameStyle = theme.textTheme.bodyMedium?.copyWith(
      color: tokens.textPrimary,
    );

    /// [e] 的色塊與名稱；名稱超過可用寬度時才換行。
    Widget swatchAndName(DistributionEntry e) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: e.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Flexible(child: Text(e.name, style: nameStyle)),
      ],
    );

    /// [e] 的件數與百分比，各自靠右對齊在固定寬度欄內。
    Widget countAndRate(DistributionEntry e) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: countWidth,
          child: Text(
            '${e.count}',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.textPrimary,
              fontFeatures: kTabularFigures,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        SizedBox(
          width: rateWidth,
          child: Text(
            '${(e.rate * 100).toStringAsFixed(2)}%',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.textMuted,
              fontFeatures: kTabularFigures,
            ),
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in visible)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            // 精簡版名稱欄很窄，放大字級時長名稱會逐字斷行；整列放不下就把數字移到名稱下一行。
            child: compact
                ? CompactLegendRow(
                    name: swatchAndName(e),
                    numbers: countAndRate(e),
                  )
                : Row(
                    children: [
                      Expanded(child: swatchAndName(e)),
                      countAndRate(e),
                    ],
                  ),
          ),
      ],
    );
  }
}

/// 精簡圖例的單列：名稱靠起始側、數字靠結束側。
///
/// 一行放得下就排同一行並垂直置中；放不下時數字換到名稱下一行，但仍靠結束側，
/// 讓各列數字右緣對齊。不用 LayoutBuilder 是因為橫向圓餅卡外層有 IntrinsicHeight，
/// 會向圖例查詢 intrinsic 尺寸；OverflowBar 換行時無法只讓數字靠右。
/// 只供 [DistributionLegend] 使用；公開僅為了讓測試能直接給它緊約束高度。
@visibleForTesting
class CompactLegendRow extends MultiChildRenderObjectWidget {
  /// 建立 [CompactLegendRow]，[name] 與 [numbers] 依序成為兩個 child。
  CompactLegendRow({super.key, required Widget name, required Widget numbers})
    : super(children: [name, numbers]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCompactLegendRow(Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderCompactLegendRow).textDirection = Directionality.of(
      context,
    );
  }
}

/// [CompactLegendRow] 的 parent data，儲存各 child 的位移。
class _CompactLegendRowParentData extends ContainerBoxParentData<RenderBox> {}

/// [CompactLegendRow] 的 render object。
class _RenderCompactLegendRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CompactLegendRowParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _CompactLegendRowParentData
        > {
  /// 建立 [_RenderCompactLegendRow]。
  _RenderCompactLegendRow(this._textDirection);

  /// 決定起始／結束側；RTL 時名稱靠右、數字靠左。
  TextDirection get textDirection => _textDirection;

  /// [textDirection] 的儲存欄位。
  TextDirection _textDirection;

  /// 更新 [textDirection]，改變時重新 layout。
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// 色塊＋名稱。
  RenderBox get _name => firstChild!;

  /// 件數＋百分比。
  RenderBox get _numbers => lastChild!;

  /// 名稱與數字在寬度 [width] 內能否同一行；與先前 OverflowBar 相同，不留間距。
  bool _fitsOneLine(double width, double numbersWidth) =>
      _name.getMaxIntrinsicWidth(double.infinity) + numbersWidth <= width;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CompactLegendRowParentData) {
      child.parentData = _CompactLegendRowParentData();
    }
  }

  /// 依 [constraints] 算出本身尺寸與兩個 child 的位移；[layoutChild] 決定實際或 dry layout。
  ({Size size, Offset name, Offset numbers}) _arrange(
    BoxConstraints constraints,
    ChildLayouter layoutChild,
  ) {
    assert(childCount == 2, 'CompactLegendRow 必須恰兩個 children');
    final numbers = layoutChild(_numbers, constraints.loosen());
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : _name.getMaxIntrinsicWidth(double.infinity) + numbers.width;
    final oneLine = _fitsOneLine(width, numbers.width);
    // 名稱本身會縮到自然寬度；同一行時不給 width − numbers，免得浮點誤差差一點就讓名稱換行。
    final name = layoutChild(_name, BoxConstraints(maxWidth: width));
    final height = oneLine
        ? math.max(name.height, numbers.height)
        : name.height + numbers.height;
    final size = constraints.constrain(Size(width, height));
    final rtl = textDirection == TextDirection.rtl;
    // 以最終尺寸定位：父層給較高的緊約束時，同一行的內容仍在整列中垂直置中。
    return (
      size: size,
      name: Offset(
        rtl ? size.width - name.width : 0,
        oneLine ? (size.height - name.height) / 2 : 0,
      ),
      numbers: Offset(
        rtl ? 0 : size.width - numbers.width,
        oneLine ? (size.height - numbers.height) / 2 : name.height,
      ),
    );
  }

  @override
  void performLayout() {
    final arranged = _arrange(constraints, ChildLayoutHelper.layoutChild);
    (_name.parentData! as _CompactLegendRowParentData).offset = arranged.name;
    (_numbers.parentData! as _CompactLegendRowParentData).offset =
        arranged.numbers;
    size = arranged.size;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _arrange(constraints, ChildLayoutHelper.dryLayoutChild).size;

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _name.getMinIntrinsicWidth(height),
    _numbers.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _name.getMaxIntrinsicWidth(height) +
      _numbers.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsicHeight(width, (child, w) => child.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsicHeight(width, (child, w) => child.getMaxIntrinsicHeight(w));

  /// 以 [childHeight] 量寬度 [width] 下的列高，換行判斷與 [_arrange] 相同。
  double _intrinsicHeight(
    double width,
    double Function(RenderBox child, double width) childHeight,
  ) {
    final numbersWidth = _numbers.getMaxIntrinsicWidth(double.infinity);
    final numbersHeight = childHeight(_numbers, numbersWidth);
    final nameHeight = childHeight(_name, width);
    return _fitsOneLine(width, numbersWidth)
        ? math.max(nameHeight, numbersHeight)
        : nameHeight + numbersHeight;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
