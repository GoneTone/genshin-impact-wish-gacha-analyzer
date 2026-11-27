import 'package:flutter/widgets.dart';

/// 依可用寬度建構子 widget 的 [LayoutBuilder]；只有高度變（鍵盤開合、橫向標題列收合）時沿用上次的子 widget，整頁不跟著重建。
class WidthLayoutBuilder extends StatelessWidget {
  /// 建立 [WidthLayoutBuilder]。
  const WidthLayoutBuilder({super.key, required this.builder});

  /// 依可用寬度 `width` 建構子 widget。
  final Widget Function(BuildContext context, double width) builder;

  @override
  Widget build(BuildContext context) {
    // 快取放在 build 的區域變數：父層重建（資料、主題變了）時一定換新的，不會沿用舊結果。
    Widget? child;
    double? childWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (child != null && childWidth == constraints.maxWidth) return child!;
        childWidth = constraints.maxWidth;
        return child = builder(context, constraints.maxWidth);
      },
    );
  }
}
