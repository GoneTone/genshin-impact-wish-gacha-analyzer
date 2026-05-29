import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/five_star_collection.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';

/// 圓形 icon 邊長。
const double _iconSize = 48;

/// 金色外環寬度。
const double _ringWidth = 2;

/// 徽章高度（直徑）。
const double _badgeSize = 19;

/// 五星一覽：把不重複五星物品以橫向 [Wrap] 排列，每個 chip 為圓形 icon +
/// 金色外環 + 右下角累計次數徽章。一行排滿自動換行、不限行數。空清單不顯示。
class FiveStarOverview extends StatelessWidget {
  /// 建立 [FiveStarOverview]。
  const FiveStarOverview({
    super.key,
    required this.items,
    this.interactive = true,
  });

  /// 聚合後的五星清單（已排序）。
  final List<FiveStarCollectionItem> items;

  /// true 時 chip 可點開詳情並顯示 tooltip；分享圖（靜態圖）傳 false。
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.m,
      children: [
        for (final item in items)
          _FiveStarChip(item: item, interactive: interactive),
      ],
    );
  }
}

/// 單一五星 chip：圓形 icon + 金環 + 右下角次數徽章；[interactive] 時可點 / hover。
class _FiveStarChip extends StatelessWidget {
  /// 建立 [_FiveStarChip]。
  const _FiveStarChip({required this.item, required this.interactive});

  /// 對應的五星條目。
  final FiveStarCollectionItem item;

  /// 是否可互動。
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final gold = tokens.fiveStar;
    // 金底徽章上的文字：dark 主題金色偏亮用深字、light 主題金色偏暗用白字，
    // 兩個主題下都維持足夠對比。
    final onGold = theme.brightness == Brightness.dark
        ? tokens.surfaceBackground
        : Colors.white;

    final stack = SizedBox(
      width: _iconSize + _ringWidth * 2,
      height: _iconSize + _ringWidth * 2,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: gold, width: _ringWidth),
              boxShadow: [
                BoxShadow(color: gold.withValues(alpha: 0.35), blurRadius: 6),
              ],
            ),
            child: GachaItemIcon(
              record: item.representative,
              size: _iconSize,
              circular: true,
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: _badgeSize),
              height: _badgeSize,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: gold,
                borderRadius: BorderRadius.circular(_badgeSize / 2),
                border: Border.all(color: tokens.surfaceCard, width: 2),
              ),
              child: Text(
                '${item.count}',
                style: TextStyle(
                  color: onGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // 徽章以 right/bottom: -2 微微外溢 SizedBox；靠右下 padding 把溢出量收進
    // chip 自身的 box，避免放進會裁切的容器時邊角被切掉。
    final chip = Padding(
      padding: const EdgeInsets.only(right: 2, bottom: 2),
      child: stack,
    );

    if (!interactive) return chip;
    return Tooltip(
      message: item.representative.name,
      waitDuration: const Duration(milliseconds: 100),
      child: GachaItemTapTarget(record: item.representative, child: chip),
    );
  }
}
