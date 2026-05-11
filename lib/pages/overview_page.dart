// lib/pages/overview_page.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_horizontal.dart';
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

          // Row 2: 兩 Pie + 跨卡池橫向時間軸
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 1024;
              final col = wide ? 3 : (c.maxWidth >= 800 ? 2 : 1);
              final tileWidth = col == 1
                  ? c.maxWidth
                  : (c.maxWidth - AppSpacing.m * (col - 1)) / col;
              return Wrap(
                spacing: AppSpacing.m,
                runSpacing: AppSpacing.m,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: ChartCard(
                      title: l.statsRarityDistribution,
                      chart: RarityPie(stats: stats),
                      legend: DistributionLegend(
                        entries: rarityDistributionEntries(stats, tokens),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: ChartCard(
                      title: l.statsItemTypeDistribution,
                      chart: ItemTypePie(stats: stats),
                      legend: DistributionLegend(
                        entries: itemTypeDistributionEntries(stats, tokens, l),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: ChartCard(
                      title: l.timelineCountFiveStar(stats.fiveStarCount),
                      chart: TimelineHorizontal(
                        entries: timelineEntries,
                        colors: bannerColors,
                      ),
                      legend: DistributionLegend(
                        entries: bannerDistributionEntries(
                          timelineEntries,
                          bannerColors,
                          l,
                        ),
                        showAllEntries: true,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: AppSpacing.xl),
          Text(
            l.timelineCountFiveStar(stats.fiveStarCount),
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
