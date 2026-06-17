import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 點擊捲動箭頭的動畫時長（timeline 與頁籤列共用）。
const Duration kScrollAffordanceDuration = Duration(milliseconds: 240);

/// 點擊捲動箭頭的動畫曲線（timeline 與頁籤列共用）。
const Curve kScrollAffordanceCurve = Curves.easeOutCubic;

/// 捲動可及性元件的方向。
enum ScrollSide {
  /// 左側：fade 從左往右漸隱。
  left,

  /// 右側：fade 從右往左漸隱。
  right,
}

/// 邊緣漸隱遮罩，用於提示使用者該方向仍可捲動。
///
/// 漸層自 [GachaTokens.surfaceCard]（不透明）漸隱到透明，會自動跟隨卡片／
/// dialog 背景色。寬度由外層 [Positioned] 決定，此元件本身不設寬度。
class ScrollEdgeFade extends StatelessWidget {
  /// 建立 [ScrollEdgeFade]。
  const ScrollEdgeFade({super.key, required this.side});

  /// 漸隱方向。
  final ScrollSide side;

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).gacha.surfaceCard;
    final isLeft = side == ScrollSide.left;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [cardColor, cardColor.withValues(alpha: 0)],
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
  });

  /// 按鈕圖示（左箭頭或右箭頭）。
  final IconData icon;

  /// 無障礙 tooltip 文字。
  final String tooltip;

  /// 主題 token，用於按鈕背景色與 icon 顏色。
  final GachaTokens tokens;

  /// 點擊後的回呼；為 `null` 時按鈕停用。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Material(
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
          ),
        ),
      ),
    );
  }
}
