import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

@immutable
class FiveStarListColors {
  const FiveStarListColors({
    required this.character,
    required this.weapon,
    required this.chronicled,
    required this.standard,
    required this.beginner,
    required this.fallback,
  });
  final Color character;
  final Color weapon;
  final Color chronicled;
  final Color standard;
  final Color beginner;
  final Color fallback;

  Color colorFor(String gachaType) => switch (gachaType) {
    '301' => character,
    '302' => weapon,
    '500' => chronicled,
    '200' => standard,
    '100' => beginner,
    _ => fallback,
  };
}

class FiveStarList extends StatelessWidget {
  const FiveStarList({super.key, required this.banners});

  /// gachaType → records desc by time。
  final Map<String, List<WishRecord>> banners;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;

    final entries = _build(banners);
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Text(
            l.timelineNoRecords,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.textMuted,
            ),
          ),
        ),
      );
    }

    final colors = FiveStarListColors(
      character: tokens.character,
      weapon: tokens.weapon,
      chronicled: tokens.accentPrimary,
      standard: tokens.threeStar,
      beginner: tokens.textMuted,
      fallback: tokens.textMuted,
    );

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            _Row(
              entry: entries[i],
              isStripe: i.isOdd,
              colors: colors,
              tokens: tokens,
              l: l,
            ),
        ],
      ),
    );
  }

  static List<_Entry> _build(Map<String, List<WishRecord>> banners) {
    final out = <_Entry>[];
    for (final entry in banners.entries) {
      final gachaType = entry.key;
      final records = entry.value;
      final asc = records.reversed.toList(growable: false);
      var pull = 0;
      for (final r in asc) {
        pull++;
        if (r.rankType == 5) {
          out.add(
            _Entry(
              name: r.name,
              gachaType: gachaType,
              time: r.time,
              pullsSincePrev: pull,
            ),
          );
          pull = 0;
        }
      }
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }
}

class _Entry {
  const _Entry({
    required this.name,
    required this.gachaType,
    required this.time,
    required this.pullsSincePrev,
  });
  final String name;
  final String gachaType;
  final DateTime time;
  final int pullsSincePrev;
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.isStripe,
    required this.colors,
    required this.tokens,
    required this.l,
  });
  final _Entry entry;
  final bool isStripe;
  final FiveStarListColors colors;
  final GachaTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final accent = colors.colorFor(entry.gachaType);
    final type = gachaTypes.firstWhere(
      (t) => t.gachaType == entry.gachaType,
      orElse: () => GachaType(
        gachaType: entry.gachaType,
        nameKey: entry.gachaType,
        fiveStarPity: 90,
        fourStarPity: 10,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.m,
        horizontal: AppSpacing.l,
      ),
      decoration: BoxDecoration(
        color: isStripe ? tokens.surfaceCardHigh : null,
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              entry.name,
              style: TextStyle(
                color: tokens.fiveStar,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              type.resolveName(l),
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              l.timelineSinceLast(entry.pullsSincePrev),
              style: TextStyle(
                color: tokens.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              _formatDate(entry.time),
              style: TextStyle(color: tokens.textMuted),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
