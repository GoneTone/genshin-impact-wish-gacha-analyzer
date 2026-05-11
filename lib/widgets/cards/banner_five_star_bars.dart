import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';

class BannerFiveStarBars extends StatelessWidget {
  const BannerFiveStarBars({
    super.key,
    required this.banners,
    required this.colors,
  });

  final Map<String, List<WishRecord>> banners;
  final BannerColors colors;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final counts = <String, int>{
      for (final t in gachaTypes)
        t.gachaType: computeWishStats(
          banners[t.gachaType] ?? const [],
        ).fiveStarCount,
    };
    final maxCount = counts.values.fold<int>(0, (m, v) => v > m ? v : m);

    final rows = gachaTypes
        .map((type) {
          final records = banners[type.gachaType] ?? const <WishRecord>[];
          final fiveStarCount = counts[type.gachaType]!;
          final isEnded = type.gachaType == '100';
          final String subtitle;
          if (isEnded) {
            subtitle = l.pityBeginnerEnded;
          } else if (fiveStarCount == 0) {
            subtitle = l.pityNoFiveStar;
          } else {
            final pity = computePity(
              records,
              threshold: type.fiveStarPity,
            ).current;
            subtitle = l.bannerFiveStarPullsSinceLast(pity);
          }
          return _BannerRow(
            name: type.resolveName(l),
            color: colors.colorFor(type.gachaType),
            fiveStarCount: fiveStarCount,
            subtitle: subtitle,
            ratio: maxCount == 0 ? 0.0 : fiveStarCount / maxCount,
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
    required this.fiveStarCount,
    required this.subtitle,
    required this.ratio,
  });

  final String name;
  final Color color;
  final int fiveStarCount;
  final String subtitle;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            name,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: _Bar(color: color, ratio: ratio, tokens: tokens),
        ),
        const SizedBox(width: AppSpacing.s),
        SizedBox(
          width: 156,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$fiveStarCount',
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
  const _Bar({required this.color, required this.ratio, required this.tokens});
  final Color color;
  final double ratio;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: ratio.clamp(0.0, 1.0),
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
