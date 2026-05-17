// lib/pages/overview_page.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/banner_top_rarity_bars.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/inline_section_title.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/loading_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rank_palette.dart';
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

    final wishTypes = gachaTypes
        .where((t) => t.category == GachaCategory.wish)
        .toList(growable: false);
    final odesTypes = gachaTypes
        .where((t) => t.category == GachaCategory.odes)
        .toList(growable: false);
    final wishBanners = <String, List<WishRecord>>{
      for (final t in wishTypes)
        t.gachaType: activeData.banners[t.gachaType] ?? const <WishRecord>[],
    };
    final odesBanners = <String, List<WishRecord>>{
      for (final t in odesTypes)
        t.gachaType: activeData.banners[t.gachaType] ?? const <WishRecord>[],
    };
    final wishAll = wishBanners.values.expand((r) => r).toList(growable: false);
    final odesAll = odesBanners.values.expand((r) => r).toList(growable: false);
    final wishStats = computeWishStats(wishAll);
    final odesStats = computeWishStats(odesAll);
    final bannerColors = BannerColors.of(Theme.of(context).brightness);

    final wish5StarAvg = averageIntervalAcrossBanners(
      wishBanners,
      rankFor: (_) => 5,
    );
    final wish4StarAvg = averageIntervalAcrossBanners(
      wishBanners,
      rankFor: (_) => 4,
    );

    String shareWithAvg(String shareText, double? avg) {
      if (avg == null) return shareText;
      return '$shareText · ${l.pityAverageInterval(avg.toStringAsFixed(2))}';
    }

    final wishStatCards = <Widget>[
      StatCard(
        label: l.statsTotal,
        value: '${wishStats.total}',
        accent: tokens.accentPrimary,
      ),
      StatCard(
        label: l.statsRankCount(l.rarityStar(5)),
        value: '${wishStats.fiveStarCount}',
        accent: tokens.fiveStar,
        subtitle: shareWithAvg(
          l.statsShareOfTotal(
            (wishStats.fiveStarRate * 100).toStringAsFixed(2),
          ),
          wish5StarAvg,
        ),
      ),
      StatCard(
        label: l.statsRankCount(l.rarityStar(4)),
        value: '${wishStats.fourStarCount}',
        accent: tokens.fourStar,
        subtitle: shareWithAvg(
          l.statsShareOfTotal(
            (wishStats.fourStarRate * 100).toStringAsFixed(2),
          ),
          wish4StarAvg,
        ),
      ),
    ];

    final odesEventType = odesTypes.firstWhere((t) => t.gachaType == '2000');
    final odesStandardType = odesTypes.firstWhere((t) => t.gachaType == '1000');
    final odesEventFiveCount = (odesBanners['2000'] ?? const <WishRecord>[])
        .where((r) => r.rankType == 5)
        .length;
    final odesStandardFourCount = (odesBanners['1000'] ?? const <WishRecord>[])
        .where((r) => r.rankType == 4)
        .length;
    final odesStatCards = <Widget>[
      StatCard(
        label: l.statsTotal,
        value: '${odesStats.total}',
        accent: tokens.accentPrimary,
      ),
      StatCard(
        label: '${odesEventType.resolveName(l)} ${l.rarityStar(5)}',
        value: '$odesEventFiveCount',
        accent: accentForRank(5, tokens),
      ),
      StatCard(
        label: '${odesStandardType.resolveName(l)} ${l.rarityStar(4)}',
        value: '$odesStandardFourCount',
        accent: accentForRank(4, tokens),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: l.pageOverviewTitle,
            icon: Icons.dashboard_outlined,
          ),
          _OverviewSection(
            title: l.pageOverviewWishSection,
            types: wishTypes,
            banners: wishBanners,
            stats: wishStats,
            bannerColors: bannerColors,
            statCards: wishStatCards,
            emptyTitle: l.emptyNoWishRecords,
          ),
          const SizedBox(height: AppSpacing.xxxl),
          Divider(
            color: Theme.of(context).gacha.borderEmphasis,
            height: 1,
            thickness: 1,
          ),
          const SizedBox(height: AppSpacing.xxxl),
          _OverviewSection(
            title: l.pageOverviewOdesSection,
            types: odesTypes,
            banners: odesBanners,
            stats: odesStats,
            bannerColors: bannerColors,
            statCards: odesStatCards,
            emptyTitle: l.emptyNoOdesRecords,
          ),
        ],
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.title,
    required this.types,
    required this.banners,
    required this.stats,
    required this.bannerColors,
    required this.statCards,
    required this.emptyTitle,
  });

  final String title;
  final List<GachaType> types;
  final Map<String, List<WishRecord>> banners;
  final WishStats stats;
  final BannerColors bannerColors;
  final List<Widget> statCards;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final hasData = banners.values.any((r) => r.isNotEmpty);

    if (!hasData) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineSectionTitle(icon: Icons.summarize_outlined, title: title),
          const SizedBox(height: AppSpacing.m),
          EmptyState.noRecords(context, title: emptyTitle, compact: true),
        ],
      );
    }

    final typesByGt = <String, GachaType>{
      for (final t in types) t.gachaType: t,
    };

    final timelineEntries = buildTimelineEntriesAcrossBanners(
      banners,
      rankFor: (gt) => typesByGt[gt]!.primaryPity.rank,
    );
    final timelineNowPulls = pullsSinceLastRankedAcrossBanners(
      banners,
      rankFor: (gt) => typesByGt[gt]!.primaryPity.rank,
    );
    final timelineRank = types.first.primaryPity.rank;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineSectionTitle(icon: Icons.summarize_outlined, title: title),
        const SizedBox(height: AppSpacing.m),

        // Stat row: 三聯卡片（無保底）
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 1024;
            final mid = c.maxWidth >= 800 && c.maxWidth < 1024;

            if (wide) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 6, child: statCards[0]),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(flex: 3, child: statCards[1]),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(flex: 3, child: statCards[2]),
                  ],
                ),
              );
            }
            if (mid) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  statCards[0],
                  const SizedBox(height: AppSpacing.m),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: statCards[1]),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(child: statCards[2]),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < statCards.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.m),
                  statCards[i],
                ],
              ],
            );
          },
        ),

        const SizedBox(height: AppSpacing.l),

        // Pie row: 稀有度 + 物品類型
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 1024;
            final mid = c.maxWidth >= 800 && c.maxWidth < 1024;

            final rarityCard = ChartCard(
              title: l.statsRarityDistribution,
              icon: Icons.pie_chart_outline,
              chart: RarityPie(stats: stats),
              legend: DistributionLegend(
                entries: rarityDistributionEntries(stats, tokens, l),
              ),
            );
            final itemTypeCard = ChartCard(
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
            );

            if (wide) {
              // 對齊 Stat row（flex 6/3/3 + 兩個 m gap）：
              // 第 1 卡寬 = (maxWidth - 24) / 2 = Stat row「總抽數」寬度。
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

        // 各卡池主稀有度件數
        ChartCard(
          title: l.bannerTopRarityCountTitle,
          icon: Icons.bar_chart,
          height: null,
          chart: BannerTopRarityBars(
            types: types,
            banners: banners,
            colors: bannerColors,
          ),
        ),

        const SizedBox(height: AppSpacing.xl),
        InlineSectionTitle(
          icon: Icons.timeline,
          title: l.timelineTopRarityTitle(
            l.rarityStar(timelineRank),
            timelineEntries.length,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        TimelineVertical(
          entries: timelineEntries,
          colors: bannerColors,
          targetRank: timelineRank,
          nowPulls: timelineNowPulls,
          isAcrossBanners: true,
        ),
      ],
    );
  }
}
