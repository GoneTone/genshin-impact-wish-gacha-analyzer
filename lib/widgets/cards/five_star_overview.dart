import 'dart:math' as math;

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

/// 單一 chip 的外框邊長：icon、兩側金環，加上收進徽章外溢的 2px padding。
const double _chipExtent = _iconSize + _ringWidth * 2 + 2;

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

/// [FiveStarOverview] 的 sliver 版：依可用寬度切成列、按需建構。
///
/// 五星一覽常有數十個圖示，整塊一次建好會在捲入畫面的那一幀卡頓；
/// 拆成列後每次只多建一列。排版與 [Wrap] 版逐一相同（同間距、靠左、同換行點）。
class SliverFiveStarOverview extends StatefulWidget {
  /// 建立 [SliverFiveStarOverview]。
  const SliverFiveStarOverview({super.key, required this.items});

  /// 要顯示的五星物品（已依次數排序）。
  final List<FiveStarCollectionItem> items;

  @override
  State<SliverFiveStarOverview> createState() => _SliverFiveStarOverviewState();
}

/// [SliverFiveStarOverview] 的 State：依寬度快取列清單。
class _SliverFiveStarOverviewState extends State<SliverFiveStarOverview> {
  /// 產生 [_rows] 時的可用寬度。
  double? _extent;

  /// 依 [_extent] 切好的列清單。
  Widget? _rows;

  @override
  void didUpdateWidget(SliverFiveStarOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) _rows = null;
  }

  /// 依可用寬度 [extent] 把物品切成列，回傳按需建構的列清單。
  Widget _buildRows(double extent) {
    final items = widget.items;
    // 與 Wrap 相同的換行規則：n 個 chip 加 n-1 個間距不超過可用寬度。
    final perRow = math.max(
      1,
      ((extent + AppSpacing.m) / (_chipExtent + AppSpacing.m)).floor(),
    );
    return SliverList.separated(
      itemCount: (items.length / perRow).ceil(),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.m),
      itemBuilder: (context, row) {
        final start = row * perRow;
        final end = math.min(start + perRow, items.length);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = start; i < end; i++) ...[
              if (i > start) const SizedBox(width: AppSpacing.m),
              _FiveStarChip(item: items[i], interactive: true),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SliverToBoxAdapter();
    // SliverLayoutBuilder 每次捲動都會重跑（捲動位置也在約束裡）；
    // 寬度沒變就回傳同一個 widget，畫面上的列才不會每幀重建。
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final extent = constraints.crossAxisExtent;
        if (_rows == null || extent != _extent) {
          _extent = extent;
          _rows = _buildRows(extent);
        }
        return _rows!;
      },
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
                  fontFeatures: kTabularFigures,
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
