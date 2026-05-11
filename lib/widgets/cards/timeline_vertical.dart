import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';

const double _monthColumnWidth = 80;
const double _nodeSize = 14;
const double _haloSize = 22;
const double _railLeft = _monthColumnWidth + (_haloSize / 2);

/// 直向時間軸(視覺隱喻 B):
/// - 上 → 下 = 新 → 舊
/// - 軸線一條連續貫穿;月份標籤貼於軸線左外側(獨立左欄,不打斷軸線)
/// - `nowPulls != null` 時最頂端為「現在」row;`isAcrossBanners` 決定 i18n 文案
class TimelineVertical extends StatelessWidget {
  const TimelineVertical({
    super.key,
    required this.entries,
    required this.colors,
    this.nowPulls,
    this.isAcrossBanners = false,
  });

  final List<TimelineEntry> entries;
  final BannerColors colors;
  final int? nowPulls;
  final bool isAcrossBanners;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;

    Widget container(Widget child) => Container(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.l,
        horizontal: AppSpacing.l,
      ),
      child: child,
    );

    if (entries.isEmpty && nowPulls == null) {
      return container(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(
            child: Text(
              l.timelineNoRecords,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    // 計算每個 entry 是否為月份分組首 row
    final monthFlag = <bool>[];
    int? prevYearMonth;
    for (final entry in entries) {
      final ym = entry.time.year * 12 + entry.time.month;
      monthFlag.add(prevYearMonth != ym);
      prevYearMonth = ym;
    }

    return container(
      Stack(
        children: [
          // 背景軸線
          Positioned(
            left: _railLeft,
            top: 0,
            bottom: 0,
            width: 2,
            child: Container(color: tokens.textMuted.withValues(alpha: 0.3)),
          ),
          // 前景:Column of rows
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (nowPulls != null)
                _NowRow(
                  nowPulls: nowPulls!,
                  isAcrossBanners: isAcrossBanners,
                  tokens: tokens,
                ),
              for (var i = 0; i < entries.length; i++)
                _EntryRow(
                  entry: entries[i],
                  showMonthTag: monthFlag[i],
                  colors: colors,
                  tokens: tokens,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.showMonthTag,
    required this.colors,
    required this.tokens,
  });

  final TimelineEntry entry;
  final bool showMonthTag;
  final BannerColors colors;
  final GachaTokens tokens;

  static String _formatShortDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}/${two(t.day)}';
  }

  String _bannerName(String gachaType, AppLocalizations l) => gachaTypes
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final accent = colors.colorFor(entry.gachaType);
    final year = entry.time.year.toString();
    final month = entry.time.month.toString().padLeft(2, '0');

    return Padding(
      padding: EdgeInsets.only(
        top: showMonthTag ? AppSpacing.m : 0,
        bottom: AppSpacing.m,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 月份左欄(固定寬度,僅在 showMonthTag 時填字)
          SizedBox(
            width: _monthColumnWidth,
            child: showMonthTag
                ? Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.s, top: 4),
                    child: Text(
                      l.timelineMonthLabel(year, month),
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // 節點圓
          SizedBox(
            width: _haloSize,
            child: Center(
              child: _Node(color: accent, tokens: tokens),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          // 主內容
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatShortDate(entry.time)} · ${_bannerName(entry.gachaType, l)} · ${l.timelineSinceLast(entry.pullsSincePrev)}',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NowRow extends StatelessWidget {
  const _NowRow({
    required this.nowPulls,
    required this.isAcrossBanners,
    required this.tokens,
  });

  final int nowPulls;
  final bool isAcrossBanners;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final meta = isAcrossBanners
        ? l.timelineNowSinceCrossPool(nowPulls)
        : l.timelineNowSinceLast(nowPulls);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: _monthColumnWidth),
          SizedBox(
            width: _haloSize,
            child: Center(
              child: _Node(
                color: tokens.accentPrimary,
                tokens: tokens,
                hollow: true,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.timelineNowLabel,
                    style: TextStyle(
                      color: tokens.accentPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 節點圓:外圍 halo + 內圓。`hollow=true` 時內圓填容器底色看起來只剩 border。
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
