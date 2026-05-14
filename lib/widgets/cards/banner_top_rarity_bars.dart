import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';

/// 卡池主稀有度件數長條圖。
///
/// 每個 [GachaType] 依其 `primaryPity.rank` 決定該池要計數的稀有度（祈願是
/// 5★、頌願常駐是 4★），bar 長度為各池件數相對最大值的比例。
class BannerTopRarityBars extends StatelessWidget {
  const BannerTopRarityBars({
    super.key,
    required this.types,
    required this.banners,
    required this.colors,
  });

  final List<GachaType> types;
  final Map<String, List<WishRecord>> banners;
  final BannerColors colors;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    final counts = <String, int>{
      for (final t in types)
        t.gachaType: (banners[t.gachaType] ?? const [])
            .where((r) => r.rankType == t.primaryPity.rank)
            .length,
    };
    final maxCount = counts.values.fold<int>(0, (m, v) => v > m ? v : m);

    final rows = types
        .map((type) {
          final records = banners[type.gachaType] ?? const <WishRecord>[];
          final topCount = counts[type.gachaType]!;
          final isEnded = type.gachaType == '100';
          final String subtitle;
          if (isEnded) {
            subtitle = l.pityBeginnerEnded;
          } else if (topCount == 0) {
            subtitle = l.pityNoFiveStar;
          } else {
            final pity = computePity(
              records,
              threshold: type.primaryPity.threshold,
              rank: type.primaryPity.rank,
            ).current;
            subtitle = l.bannerTopRarityPullsSinceLast(
              type.primaryPity.rank,
              pity,
            );
          }
          return _BannerRow(
            name: type.resolveName(l),
            color: colors.colorFor(type.gachaType),
            topCount: topCount,
            subtitle: subtitle,
            ratio: maxCount == 0 ? 0.0 : topCount / maxCount,
          );
        })
        .toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s),
          rows[i],
        ],
      ],
    );
  }
}

class _BannerRow extends StatelessWidget {
  const _BannerRow({
    required this.name,
    required this.color,
    required this.topCount,
    required this.subtitle,
    required this.ratio,
  });

  final String name;
  final Color color;
  final int topCount;
  final String subtitle;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    return Row(
      children: [
        SizedBox(
          width:
              96, // name label column, tuned for longest banner name at bodyMedium
          child: Text(
            name,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: _Bar(color: color, ratio: ratio),
        ),
        const SizedBox(width: AppSpacing.s),
        SizedBox(
          width: 156, // count + separator + subtitle (ellipsis) column
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$topCount',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text('·', style: TextStyle(color: tokens.textMuted)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.ratio});
  final Color color;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: ratio.clamp(0.0, 1.0),
          heightFactor: 1.0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.55), color],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
