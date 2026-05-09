import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 顯示傳入 records 中的 5★ 紀錄；橫向 scrollable，窄寬度改縱向。
class TimelineCard extends StatelessWidget {
  const TimelineCard({
    super.key,
    required this.records,
    this.bannerColorOf,
  });

  /// 必須以時間 desc 排序（最新在前）。
  final List<WishRecord> records;

  /// 跨卡池版本：傳入後每個膠囊以對應卡池色當左側 stripe。
  final Color Function(String gachaType)? bannerColorOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;
    final fiveStars = _buildEntries(records);

    if (fiveStars.isEmpty) {
      return Center(
        child: Text(
          l.timelineNoRecords,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: tokens.textMuted),
        ),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 320;
      if (narrow) {
        return ListView.separated(
          scrollDirection: Axis.vertical,
          itemCount: fiveStars.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: AppSpacing.xs),
          itemBuilder: (_, i) => _Chip(
            entry: fiveStars[i],
            bannerColorOf: bannerColorOf,
            tokens: tokens,
            l: l,
          ),
        );
      }
      return ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: fiveStars.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s),
        itemBuilder: (_, i) => _Chip(
          entry: fiveStars[i],
          bannerColorOf: bannerColorOf,
          tokens: tokens,
          l: l,
        ),
      );
    });
  }

  /// 從 records 倒序累計，每碰到 5★ 計算「離上一個 5★ 多少抽」。
  static List<_Entry> _buildEntries(List<WishRecord> records) {
    // records 以時間 desc 排序；改 chronological 順序累計再 reverse。
    final asc = records.reversed.toList(growable: false);
    final out = <_Entry>[];
    var pull = 0;
    for (final r in asc) {
      pull++;
      if (r.rankType == 5) {
        out.add(_Entry(
          name: r.name,
          gachaType: r.gachaType,
          time: r.time,
          pullsSincePrev: pull,
        ));
        pull = 0;
      }
    }
    return out.reversed.toList(growable: false);
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

class _Chip extends StatelessWidget {
  const _Chip({
    required this.entry,
    required this.bannerColorOf,
    required this.tokens,
    required this.l,
  });
  final _Entry entry;
  final Color Function(String)? bannerColorOf;
  final GachaTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final accent = bannerColorOf?.call(entry.gachaType) ?? tokens.fiveStar;
    return Tooltip(
      message: _formatDate(entry.time),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.m, vertical: AppSpacing.s),
        decoration: BoxDecoration(
          color: tokens.surfaceCardHigh,
          border: Border(left: BorderSide(color: accent, width: 3)),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.name,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l.timelineSinceLast(entry.pullsSincePrev),
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
