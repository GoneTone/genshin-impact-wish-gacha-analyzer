import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 節點內圓直徑。
const double _nodeSize = 14;

/// 節點外圍 halo（觸控熱區）直徑。
const double _haloSize = 22;

/// 時間軸節點圓：外圍 halo + 內圓。[hollow] 為 true 時內圓填容器底色，看起來只剩
/// border（用於「現在」節點）。橫向（TimelineHorizontal）與直向（TimelineVertical）共用。
class TimelineNode extends StatelessWidget {
  /// 建立 [TimelineNode]。
  const TimelineNode({
    super.key,
    required this.color,
    required this.tokens,
    this.hollow = false,
  });

  /// 節點與 halo 的主色。
  final Color color;

  /// 主題 token，用於取得 [GachaTokens.surfaceCard]（hollow 填色）。
  final GachaTokens tokens;

  /// true 時內圓填 surfaceCard 使節點看起來只有邊框，用於「現在」節點。
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _haloSize,
      height: _haloSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.25),
      ),
      child: Container(
        width: _nodeSize,
        height: _nodeSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hollow ? tokens.surfaceCard : color,
          border: Border.all(color: color, width: 2),
        ),
      ),
    );
  }
}
