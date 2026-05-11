import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';

const double _colWidth = 90;
const double _nodeSize = 14;
const double _haloSize = 22;

/// 橫向時間軸(視覺隱喻 A · 變體 1):
/// - 左 → 右 = 新 → 舊
/// - 每欄 3 行:名稱 / 節點(軸線居中) / `MM/dd · N抽`
/// - `nowPulls != null` 時最左欄為「現在」(中空節點 + 同色 halo)
class TimelineHorizontal extends StatelessWidget {
  const TimelineHorizontal({
    super.key,
    required this.entries,
    required this.colors,
    this.nowPulls,
  });

  final List<TimelineEntry> entries;
  final BannerColors colors;
  final int? nowPulls;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;

    if (entries.isEmpty && nowPulls == null) {
      return Center(
        child: Text(
          l.timelineNoRecords,
          style: theme.textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        ),
      );
    }

    // LayoutBuilder 取得父層高度,確保 Stack 有明確高度可以讓背景軸線 Positioned.fill 正確繪製
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            height: constraints.maxHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 背景軸線:水平中央一條 2px 線,左右留 AppSpacing.s 內距
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s,
                    ),
                    child: Center(
                      child: Container(
                        height: 2,
                        color: tokens.textMuted.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                // 節點欄:橫向 Row,垂直置中於 Stack
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (nowPulls != null)
                      _NowColumn(nowPulls: nowPulls!, tokens: tokens, l: l),
                    for (final entry in entries)
                      _EntryColumn(
                        entry: entry,
                        colors: colors,
                        tokens: tokens,
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EntryColumn extends StatelessWidget {
  const _EntryColumn({
    required this.entry,
    required this.colors,
    required this.tokens,
  });
  final TimelineEntry entry;
  final BannerColors colors;
  final GachaTokens tokens;

  String _formatShortDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}/${two(t.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = colors.colorFor(entry.gachaType);
    final l = AppLocalizations.of(context)!;
    return SizedBox(
      width: _colWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _Node(color: accent, tokens: tokens),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_formatShortDate(entry.time)} · ${l.timelineSinceLast(entry.pullsSincePrev)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _NowColumn extends StatelessWidget {
  const _NowColumn({
    required this.nowPulls,
    required this.tokens,
    required this.l,
  });
  final int nowPulls;
  final GachaTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _colWidth,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          l.timelineNowLabel,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: tokens.accentPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _Node(color: tokens.accentPrimary, tokens: tokens, hollow: true),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l.timelineNowPulls(nowPulls),
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _Node extends StatelessWidget {
  const _Node({required this.color, required this.tokens, this.hollow = false});
  final Color color;
  final GachaTokens tokens;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _haloSize,
      height: _haloSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.25),
      ),
      child: Container(
        width: _nodeSize,
        height: _nodeSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hollow ? tokens.surfaceCard : color,
          border: Border.all(color: color, width: 2),
        ),
      ),
    );
  }
}
