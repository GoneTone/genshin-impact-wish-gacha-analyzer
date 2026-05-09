// lib/pages/banner_page.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/pity_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/record_list_table.dart';

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
    final activeData = ref.watch(
        wishRepositoryProvider.select((s) => s.activeData));

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
        computePity(records, threshold: type.fourStarPity);
    final isEndedPool = type.gachaType == '100';

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
            return Wrap(
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.m,
              children: [
                SizedBox(
                  width: wide
                      ? (c.maxWidth - AppSpacing.m * 2) * 6 / 12
                      : c.maxWidth,
                  child: PityCard(
                    label: l.pityFiveStar,
                    pity: fivePity,
                    accent: tokens.fiveStar,
                    isEndedPool: isEndedPool,
                  ),
                ),
                SizedBox(
                  width: wide
                      ? (c.maxWidth - AppSpacing.m * 2) * 3 / 12
                      : (mid ? (c.maxWidth - AppSpacing.m) / 2 : c.maxWidth),
                  child: PityCard(
                    label: l.pityFourStar,
                    pity: fourPity,
                    accent: tokens.fourStar,
                    isEndedPool: isEndedPool,
                  ),
                ),
                SizedBox(
                  width: wide
                      ? (c.maxWidth - AppSpacing.m * 2) * 3 / 12
                      : (mid ? (c.maxWidth - AppSpacing.m) / 2 : c.maxWidth),
                  child: StatCard(
                    label: l.statsTotal,
                    value: '${stats.total}',
                    accent: tokens.accentPrimary,
                  ),
                ),
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
                    title: l.statsFiveStarRate,
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

          const SizedBox(height: AppSpacing.xl),
          Text(l.pageBannerRecordList,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.s),
          RecordListTable(records: records),
        ],
      ),
    );
  }
}
