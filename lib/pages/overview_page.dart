// lib/pages/overview_page.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final activeData = ref.watch(
        wishRepositoryProvider.select((s) => s.activeData));

    if (activeData == null) {
      return EmptyState.noSync(context);
    }
    final all = activeData.allRecords;
    final stats = computeWishStats(all);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: l.pageOverviewTitle),

          // Row 1: 三聯 Stat 卡（無保底，因綜合頁不適用）
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 1024;
            final mid = c.maxWidth >= 800 && c.maxWidth < 1024;
            return Wrap(
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.m,
              children: [
                SizedBox(
                  width: wide
                      ? (c.maxWidth - AppSpacing.m * 2) * 6 / 12
                      : (mid ? c.maxWidth : c.maxWidth),
                  child: StatCard(
                    label: l.statsTotal,
                    value: '${stats.total}',
                    accent: tokens.accentPrimary,
                  ),
                ),
                SizedBox(
                  width: wide
                      ? (c.maxWidth - AppSpacing.m * 2) * 3 / 12
                      : (mid ? (c.maxWidth - AppSpacing.m) / 2 : c.maxWidth),
                  child: StatCard(
                    label: l.statsFiveStarRate,
                    value: '${stats.fiveStarCount}',
                    accent: tokens.fiveStar,
                    subtitle:
                        '${(stats.fiveStarRate * 100).toStringAsFixed(2)}%',
                  ),
                ),
                SizedBox(
                  width: wide
                      ? (c.maxWidth - AppSpacing.m * 2) * 3 / 12
                      : (mid ? (c.maxWidth - AppSpacing.m) / 2 : c.maxWidth),
                  child: StatCard(
                    label: l.statsFourStarRate,
                    value: '${stats.fourStarCount}',
                    accent: tokens.fourStar,
                    subtitle:
                        '${(stats.fourStarRate * 100).toStringAsFixed(2)}%',
                  ),
                ),
              ],
            );
          }),

          const SizedBox(height: AppSpacing.l),

          // Row 2: 兩 Pie + Timeline placeholder（Phase 2 才填 timeline）
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
                    title: '${l.statsFiveStarRate} / ${l.statsFourStarRate} / ${l.statsThreeStarRate}',
                    chart: RarityPie(stats: stats),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: ChartCard(
                    title: '${l.kindCharacter} / ${l.kindWeapon}',
                    chart: ItemTypePie(stats: stats),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: ChartCard(
                    title: '5★',
                    chart: Center(
                      child: Text(l.settingsPlaceholderPhase2,
                          style: TextStyle(color: tokens.textMuted)),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
