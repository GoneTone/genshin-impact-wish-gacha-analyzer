// lib/pages/overview_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/stats_panel.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeData = ref.watch(
        wishRepositoryProvider.select((s) => s.activeData));

    if (activeData == null) {
      return EmptyState.noSync(context);
    }
    final all = activeData.allRecords;
    final stats = computeWishStats(all);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('綜合數據（全卡池合計）',
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
        ],
      ),
    );
  }
}
