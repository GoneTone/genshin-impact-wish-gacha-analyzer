import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 點擊捲動箭頭的動畫時長（timeline 與頁籤列共用）。
const Duration kScrollAffordanceDuration = Duration(milliseconds: 240);

/// 點擊捲動箭頭的動畫曲線（timeline 與頁籤列共用）。
const Curve kScrollAffordanceCurve = Curves.easeOutCubic;

/// 點擊捲動箭頭時的相對捲動（timeline 與詳情左欄共用）。
extension ScrollAffordanceScroll on ScrollController {
  /// 以共用動畫相對捲動 [delta]，夾在 0 與 maxScrollExtent 之間；尚未接上捲動區時不動作。
  void animateBy(double delta) {
    if (!hasClients) return;
    animateTo(
      (offset + delta).clamp(0.0, position.maxScrollExtent),
      duration: kScrollAffordanceDuration,
      curve: kScrollAffordanceCurve,
    );
  }
}

/// 捲動可及性元件的方向。
enum ScrollSide {
  /// 起始側（由左往右時為左、由右往左時為右）：fade 從起始側往內漸隱。
  start,

  /// 結束側（由左往右時為右、由右往左時為左）：fade 從結束側往內漸隱。
  end,

  /// 底部：fade 從下往上漸隱。
  bottom,
}

/// 邊緣漸隱遮罩，用於提示使用者該方向仍可捲動。
///
/// 漸層自背景色（不透明）漸隱到透明：在 dialog 內用 dialog 的底色，其他地方用
/// [GachaTokens.surfaceCard]（卡片底色）。寬高由外層 [Positioned] 決定，此元件本身不設尺寸。
class ScrollEdgeFade extends StatelessWidget {
  /// 建立 [ScrollEdgeFade]。
  const ScrollEdgeFade({super.key, required this.side});

  /// 漸隱方向。
  final ScrollSide side;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialog = context.findAncestorWidgetOfExactType<Dialog>();
    // 與 Dialog 解析底色的順序一致；dialog 底色比卡片深，用卡片色會浮出一塊白框。
    final background = dialog == null
        ? theme.gacha.surfaceCard
        : dialog.backgroundColor ??
              theme.dialogTheme.backgroundColor ??
              theme.colorScheme.surfaceContainerHigh;
    final (begin, end) = switch (side) {
      ScrollSide.start => (
        AlignmentDirectional.centerStart,
        AlignmentDirectional.centerEnd,
      ),
      ScrollSide.end => (
        AlignmentDirectional.centerEnd,
        AlignmentDirectional.centerStart,
      ),
      ScrollSide.bottom => (Alignment.bottomCenter, Alignment.topCenter),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: begin,
          end: end,
          colors: [background, background.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// 浮在捲動區邊緣的圓形箭頭按鈕。
///
/// [onPressed] 為 `null` 時呈現停用樣式（icon 轉淡、游標不變手形、無法點擊），
/// 用於「已在最前／最後」的情境；非 `null` 時為可點的啟用樣式。
class ScrollArrowButton extends StatelessWidget {
  /// 建立 [ScrollArrowButton]。
  const ScrollArrowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.tokens,
    required this.onPressed,
    this.largeHitArea = false,
  });

  /// 按鈕圖示（左、右或下箭頭）。
  final IconData icon;

  /// 無障礙 tooltip 文字。
  final String tooltip;

  /// 主題 token，用於按鈕背景色與 icon 顏色。
  final GachaTokens tokens;

  /// 點擊後的回呼；為 `null` 時按鈕停用。
  final VoidCallback? onPressed;

  /// 為 true 時不論平台都外包 48dp 觸控區；false 時僅手機排版（[isCompactLayout]）放大。
  final bool largeHitArea;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final circle = _circle(enabled);
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          // 外圈多一層 48dp 觸控區，看得到的圓圈仍是 24dp。
          child: largeHitArea || isCompactLayout(context)
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onPressed,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(child: circle),
                  ),
                )
              : circle,
        ),
      ),
    );
  }

  /// 24dp 的圓形箭頭按鈕本體。
  Widget _circle(bool enabled) => Material(
    color: tokens.surfaceCard.withValues(alpha: 0.85),
    shape: CircleBorder(
      side: BorderSide(
        color: tokens.textMuted.withValues(alpha: 0.25),
        width: 1,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: SizedBox(
        width: 24,
        height: 24,
        child: Icon(
          icon,
          size: 16,
          color: enabled
              ? tokens.textPrimary
              : tokens.textMuted.withValues(alpha: 0.4),
        ),
      ),
    ),
  );
}
