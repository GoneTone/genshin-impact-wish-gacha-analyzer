// lib/pages/overview_page.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/banner_five_star_bars.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/loading_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final state = ref.watch(wishRepositoryProvider);
    final activeData = state.activeData;

    if (state.isBootstrapping) {
      return const LoadingState();
    }
    if (activeData == null) {
      return EmptyState.noSync(context);
    }
    final all = activeData.allRecords;
    final stats = computeWishStats(all);
    final bannerColors = BannerColors.fromTokens(tokens);
    final timelineEntries = buildTimelineEntriesAcrossBanners(
      activeData.banners,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: l.pageOverviewTitle),

          // Row 1: 三聯 Stat 卡（無保底，因綜合頁不適用）
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 1024;
              final mid = c.maxWidth >= 800 && c.maxWidth < 1024;

              final totalCard = StatCard(
                label: l.statsTotal,
                value: '${stats.total}',
                accent: tokens.accentPrimary,
              );
              final fiveCard = StatCard(
                label: l.statsFiveStarCount,
                value: '${stats.fiveStarCount}',
                accent: tokens.fiveStar,
                subtitle: l.statsShareOfTotal(
                  (stats.fiveStarRate * 100).toStringAsFixed(2),
                ),
              );
              final fourCard = StatCard(
                label: l.statsFourStarCount,
                value: '${stats.fourStarCount}',
                accent: tokens.fourStar,
                subtitle: l.statsShareOfTotal(
                  (stats.fourStarRate * 100).toStringAsFixed(2),
                ),
              );

              if (wide) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 6, child: totalCard),
                      const SizedBox(width: AppSpacing.m),
                      Expanded(flex: 3, child: fiveCard),
                      const SizedBox(width: AppSpacing.m),
                      Expanded(flex: 3, child: fourCard),
                    ],
                  ),
                );
              }
              if (mid) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    totalCard,
                    const SizedBox(height: AppSpacing.m),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: fiveCard),
                          const SizedBox(width: AppSpacing.m),
                          Expanded(child: fourCard),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  totalCard,
                  const SizedBox(height: AppSpacing.m),
                  fiveCard,
                  const SizedBox(height: AppSpacing.m),
                  fourCard,
                ],
              );
            },
          ),

          const SizedBox(height: AppSpacing.l),

          // Row 2: 兩 Pie（稀有度 + 物品類型）— wide mode 下與 Row 1 邊界對齊
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 1024;
              final mid = c.maxWidth >= 800 && c.maxWidth < 1024;

              final rarityCard = ChartCard(
                title: l.statsRarityDistribution,
                chart: RarityPie(stats: stats),
                legend: DistributionLegend(
                  entries: rarityDistributionEntries(stats, tokens),
                ),
              );
              final itemTypeCard = ChartCard(
                title: l.statsItemTypeDistribution,
                chart: ItemTypePie(stats: stats),
                legend: DistributionLegend(
                  entries: itemTypeDistributionEntries(stats, tokens, l),
                ),
              );

              if (wide) {
                // 對齊 Row 1（flex 6/3/3 + 兩個 m gap）：
                // 第 1 卡寬 = (maxWidth - 24) / 2 = Row 1「總抽數」寬度。
                final card1Width = (c.maxWidth - AppSpacing.m * 2) / 2;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: card1Width, child: rarityCard),
                      const SizedBox(width: AppSpacing.m),
                      Expanded(child: itemTypeCard),
                    ],
                  ),
                );
              }
              if (mid) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: rarityCard),
                      const SizedBox(width: AppSpacing.m),
                      Expanded(child: itemTypeCard),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  rarityCard,
                  const SizedBox(height: AppSpacing.m),
                  itemTypeCard,
                ],
              );
            },
          ),

          const SizedBox(height: AppSpacing.m),

          // 各卡池 5★ 件數（佔整行，因需足夠寬度容納 5 條水平 bar）
          ChartCard(
            title: l.bannerFiveStarCountTitle,
            height: null,
            chart: BannerFiveStarBars(
              banners: activeData.banners,
              colors: bannerColors,
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          Text(
            l.timelineCountFiveStar(timelineEntries.length),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.s),
          TimelineVertical(
            entries: timelineEntries,
            colors: bannerColors,
            nowPulls: pullsSinceLastFiveStarAcrossBanners(activeData.banners),
            isAcrossBanners: true,
          ),
        ],
      ),
    );
  }
}
