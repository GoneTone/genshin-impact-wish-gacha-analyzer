import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_row.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/pity_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_horizontal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/search_filter_bar.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/sortable_table.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/inline_section_title.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/loading_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rank_palette.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_action_button.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_image_helper.dart';

/// 單一 banner 的詳細統計頁，顯示保底進度、圖表、記錄列表。
class BannerPage extends ConsumerWidget {
  /// 建立 [BannerPage]，需指定目標卡池的 [gachaType]。
  const BannerPage({super.key, required this.gachaType});

  /// 對應 [GachaType.gachaType] 的卡池類型字串。
  final String gachaType;

  /// 依 [gachaType] 查找對應的 [GachaType]；找不到時回傳含預設值的佔位物件。
  GachaType _resolveType() => gachaTypes.firstWhere(
    (t) => t.gachaType == gachaType,
    orElse: () => GachaType(
      gachaType: gachaType,
      nameKey: gachaType,
      category: GachaCategory.gacha,
      pities: const [
        PityRule(rank: 5, threshold: 90),
        PityRule(rank: 4, threshold: 10),
      ],
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final state = ref.watch(gachaRepositoryProvider);
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
            PageHeader(
              title: type.resolveName(l),
              icon: _iconForGachaType(type),
            ),
            SizedBox(height: 320, child: EmptyState.noRecords(context)),
          ],
        ),
      );
    }

    final stats = computeGachaStats(records);
    final primary = type.primaryPity;
    final secondary = type.secondaryPity;
    final primaryPityData = computePity(
      records,
      threshold: primary.threshold,
      rank: primary.rank,
    );
    final secondaryPityData = secondary == null
        ? null
        : computePity(
            records,
            threshold: secondary.threshold,
            rank: secondary.rank,
          );
    final isEndedPool = type.gachaType == '100';

    final filterState = ref.watch(recordFilterProvider(gachaType));
    final allRows = buildRecordRows(records, mainRank: primary.rank);
    final filtered = filterRecordRows(allRows, filterState.filter);
    final sorted = sortRecordRows(filtered, filterState.sort);
    final availableItemTypes =
        records
            .map((r) => r.itemType)
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: PageHeader(
                  title: type.resolveName(l),
                  icon: _iconForGachaType(type),
                ),
              ),
              ShareActionButton(
                enabled: records.isNotEmpty,
                onGenerate: () => _generateBannerShare(
                  context,
                  ref,
                  l,
                  type,
                  activeData.uid,
                  activeData.lastUpdated,
                  records,
                ),
              ),
            ],
          ),

          // Row 1: 三聯 Stat 卡（主 / 副保底用 PityCard，總抽數用 StatCard）
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 1024;
              final mid = c.maxWidth >= 800 && c.maxWidth < 1024;

              final primaryCard = PityCard(
                label: l.pityRank(l.rarityStar(primary.rank)),
                rank: primary.rank,
                pity: primaryPityData,
                accent: accentForRank(primary.rank, tokens),
                isEndedPool: isEndedPool,
              );
              final secondaryCard =
                  (secondary == null || secondaryPityData == null)
                  ? null
                  : PityCard(
                      label: l.pityRank(l.rarityStar(secondary.rank)),
                      rank: secondary.rank,
                      pity: secondaryPityData,
                      accent: accentForRank(secondary.rank, tokens),
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
                      Expanded(flex: 6, child: primaryCard),
                      if (secondaryCard != null) ...[
                        const SizedBox(width: AppSpacing.m),
                        Expanded(flex: 3, child: secondaryCard),
                      ],
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
                    primaryCard,
                    const SizedBox(height: AppSpacing.m),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (secondaryCard != null) ...[
                            Expanded(child: secondaryCard),
                            const SizedBox(width: AppSpacing.m),
                          ],
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
                  primaryCard,
                  const SizedBox(height: AppSpacing.m),
                  if (secondaryCard != null) ...[
                    secondaryCard,
                    const SizedBox(height: AppSpacing.m),
                  ],
                  totalCard,
                ],
              );
            },
          ),

          const SizedBox(height: AppSpacing.l),

          // Row 2: 兩 Pie + Timeline placeholder
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
                      icon: Icons.pie_chart_outline,
                      chart: RarityPie(stats: stats),
                      legend: DistributionLegend(
                        entries: rarityDistributionEntries(stats, tokens, l),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: ChartCard(
                      title: l.statsItemTypeDistribution,
                      icon: Icons.donut_small_outlined,
                      chart: ItemTypePie(stats: stats),
                      legend: DistributionLegend(
                        entries: itemTypeDistributionEntries(
                          stats,
                          Theme.of(context).brightness,
                          l,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: ChartCard(
                      title: l.timelineTopRarityTitle(
                        l.rarityStar(primary.rank),
                        _countAtRank(stats, primary.rank),
                      ),
                      icon: Icons.timeline,
                      chart: TimelineHorizontal(
                        entries: buildTimelineEntries(
                          records,
                          targetRank: primary.rank,
                        ),
                        colors: BannerColors.of(Theme.of(context).brightness),
                        targetRank: primary.rank,
                        nowPulls: pullsSinceLastRanked(
                          records,
                          rank: primary.rank,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: AppSpacing.xl),
          InlineSectionTitle(
            icon: Icons.table_chart_outlined,
            title: l.pageBannerRecordList,
          ),
          const SizedBox(height: AppSpacing.s),
          SearchFilterBar(
            state: filterState,
            availableItemTypes: availableItemTypes,
            onFilterChanged: (f) =>
                ref.read(recordFilterProvider(gachaType).notifier).setFilter(f),
            onClear: () =>
                ref.read(recordFilterProvider(gachaType).notifier).clear(),
          ),
          const SizedBox(height: AppSpacing.m),
          SortableTable(
            rows: sorted,
            sort: filterState.sort,
            mainRank: primary.rank,
            onSortColumnTapped: (col) => ref
                .read(recordFilterProvider(gachaType).notifier)
                .cycleSort(col),
          ),
        ],
      ),
    );
  }

  /// 產生並分享此 banner 的統計截圖。
  Future<void> _generateBannerShare(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    GachaType type,
    String uid,
    DateTime updatedAt,
    List<GachaRecord> records,
  ) async {
    final appVersion = ref.read(appVersionProvider);
    await generateAndShareImage(
      context: context,
      l: l,
      suggestedName:
          'genshin_gacha_share_${type.gachaType}_${fileTimestamp()}.png',
      buildCard: (icon, options) => ShareCard.banner(
        l: l,
        appVersion: appVersion,
        appIcon: icon,
        options: options,
        uid: uid,
        updatedAt: updatedAt.toLocal(),
        title: type.resolveName(l),
        records: records,
        targetRank: type.primaryPity.rank,
      ),
    );
  }
}

/// 取 [GachaStats] 中對應稀有度的件數，作為 timeline 標題的 N。
int _countAtRank(GachaStats stats, int rank) => switch (rank) {
  5 => stats.fiveStarCount,
  4 => stats.fourStarCount,
  3 => stats.threeStarCount,
  2 => stats.twoStarCount,
  _ => 0,
};

/// 將 [GachaType] 對應至頁面標題圖示。
IconData _iconForGachaType(GachaType type) {
  return switch (type.nameKey) {
    'gachaTypeCharacter' => Icons.person_outline,
    'gachaTypeWeapon' => Icons.shield_outlined,
    'gachaTypeChronicled' => Icons.collections_bookmark_outlined,
    'gachaTypeStandard' => Icons.history,
    'gachaTypeBeginner' => Icons.school_outlined,
    'gachaTypeOdesEvent' => Icons.auto_awesome,
    'gachaTypeOdesStandard' => Icons.auto_awesome_motion,
    _ => Icons.casino_outlined,
  };
}
