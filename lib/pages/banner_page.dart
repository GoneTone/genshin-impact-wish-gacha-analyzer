// lib/pages/banner_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/record_list_table.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/stats_panel.dart';

class BannerPage extends ConsumerWidget {
  const BannerPage({super.key, required this.gachaType});

  final String gachaType;

  String _resolveDisplayName(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return gachaTypes
        .firstWhere(
          (t) => t.gachaType == gachaType,
          orElse: () => GachaType(
            gachaType: gachaType,
            nameKey: gachaType,
            fiveStarPity: 90,
            fourStarPity: 10,
          ),
        )
        .resolveName(l);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeData = ref.watch(
        wishRepositoryProvider.select((s) => s.activeData));

    if (activeData == null) {
      return const EmptyState(
        icon: Icons.cloud_off_outlined,
        title: '尚未同步任何資料',
        message: '點右上「更新資料」開始',
      );
    }
    final records = activeData.banners[gachaType] ?? const [];
    final stats = computeWishStats(records);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${_resolveDisplayName(context)}（gacha_type=$gachaType）',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 720;
              if (stack) {
                return Column(children: [
                  SizedBox(height: 220, child: RarityPie(stats: stats)),
                  const SizedBox(height: 16),
                  SizedBox(height: 220, child: ItemTypePie(stats: stats)),
                ]);
              }
              return SizedBox(
                height: 220,
                child: Row(children: [
                  Expanded(child: RarityPie(stats: stats)),
                  Expanded(child: ItemTypePie(stats: stats)),
                ]),
              );
            },
          ),
          const SizedBox(height: 16),
          StatsPanel(stats: stats),
          const SizedBox(height: 24),
          Text('紀錄列表',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          RecordListTable(records: records),
        ],
      ),
    );
  }
}
