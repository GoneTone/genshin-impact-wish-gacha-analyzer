// lib/pages/banner_page.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/pity_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/search_filter_bar.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/sortable_table.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/loading_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

class BannerPage extends ConsumerWidget {
  const BannerPage({super.key, required this.gachaType});

  final String gachaType;

  GachaType _resolveType() => gachaTypes.firstWhere(
        (t) => t.gachaType == gachaType,
        orElse: () => GachaType(
          gachaType: gachaType,
          nameKey: gachaType,
          fiveStarPity: 90,
          fourStarPity: 10,
        ),
      );

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
    final type = _resolveType();
    final records = activeData.banners[gachaType] ?? const [];

    if (records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(title: type.resolveName(l)),
            SizedBox(
              height: 320,
              child: EmptyState.noRecords(context),
            ),
          ],
        ),
      );
    }

    final stats = computeWishStats(records);
    final fivePity =
        computePity(records, threshold: type.fiveStarPity);
    final fourPity =
        computePity(records, threshold: type.fourStarPity, rank: 4);
    final isEndedPool = type.gachaType == '100';

    final filterState = ref.watch(recordFilterProvider(gachaType));
    final filtered = sortRecords(
        filterRecords(records, filterState.filter), filterState.sort);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: type.resolveName(l)),

          // Row 1: 三聯 Stat 卡（5★ 和 4★ 用 PityCard，總抽數用 StatCard）
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 1024;
            final mid = c.maxWidth >= 800 && c.maxWidth < 1024;

            final fiveCard = PityCard(
              label: l.pityFiveStar,
              pity: fivePity,
              accent: tokens.fiveStar,
              isEndedPool: isEndedPool,
            );
            final fourCard = PityCard(
              label: l.pityFourStar,
              pity: fourPity,
              accent: tokens.fourStar,
              isEndedPool: isEndedPool,
            );
            final totalCard = StatCard(
              label: l.statsTotal,
              value: '${stats.total}',
              accent: tokens.accentPrimary,
            );

            if (wide) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 6, child: fiveCard),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(flex: 3, child: fourCard),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(flex: 3, child: totalCard),
                  ],
                ),
              );
            }
            if (mid) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  fiveCard,
                  const SizedBox(height: AppSpacing.m),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: fourCard),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(child: totalCard),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                fiveCard,
                const SizedBox(height: AppSpacing.m),
                fourCard,
                const SizedBox(height: AppSpacing.m),
                totalCard,
              ],
            );
          }),

          const SizedBox(height: AppSpacing.l),

          // Row 2: 兩 Pie + Timeline placeholder
          LayoutBuilder(builder: (context, c) {
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
                    chart: TimelineCard(records: records),
                  ),
                ),
              ],
            );
          }),

          const SizedBox(height: AppSpacing.xl),
          Text(l.pageBannerRecordList,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.s),
          SearchFilterBar(
            state: filterState,
            onFilterChanged: (f) => ref
                .read(recordFilterProvider(gachaType).notifier)
                .setFilter(f),
            onSortChanged: (s) => ref
                .read(recordFilterProvider(gachaType).notifier)
                .setSort(s),
            onClear: () => ref
                .read(recordFilterProvider(gachaType).notifier)
                .clear(),
          ),
          const SizedBox(height: AppSpacing.m),
          SortableTable(records: filtered),
        ],
      ),
    );
  }
}
