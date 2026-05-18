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
class TimelineVertical extends StatefulWidget {
  const TimelineVertical({
    super.key,
    required this.entries,
    required this.colors,
    required this.targetRank,
    this.nowPulls,
    this.isAcrossBanners = false,
  });

  final List<TimelineEntry> entries;
  final BannerColors colors;

  /// 主要顯示稀有度（5 或 4）。用於「暫無 N★ 紀錄」、「距上次 N★ X 抽」等文案。
  /// 跨卡池且 banner 各自主稀有度不同（頌願綜合）時，傳入「最具代表性的那個」
  /// （目前以 types.first.primaryPity.rank 為準）。
  final int targetRank;
  final int? nowPulls;
  final bool isAcrossBanners;

  @override
  State<TimelineVertical> createState() => _TimelineVerticalState();
}

class _TimelineVerticalState extends State<TimelineVertical> {
  static const int _initialPageSize = 10;
  static const int _pageStep = 10;

  int _visibleCount = _initialPageSize;

  /// Dataset-change detection: resets [_visibleCount] when **both** length and
  /// first-entry time differ. OR logic would be overly aggressive — appending
  /// new records changes length but not firstTime, and should not reset the
  /// user's expand state.
  @override
  void didUpdateWidget(TimelineVertical oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFirstTime = oldWidget.entries.isNotEmpty
        ? oldWidget.entries.first.time
        : null;
    final newFirstTime = widget.entries.isNotEmpty
        ? widget.entries.first.time
        : null;
    final lengthChanged = oldWidget.entries.length != widget.entries.length;
    final firstTimeChanged = oldFirstTime != newFirstTime;
    if (lengthChanged && firstTimeChanged) {
      // length + firstTime 同時不同 → 視為不同資料集，reset
      setState(() {
        _visibleCount = _initialPageSize;
      });
    } else {
      // 同資料集（或局部變動）→ 只做 clamp
      final clamped = _visibleCount.clamp(0, widget.entries.length);
      if (clamped != _visibleCount) {
        setState(() {
          _visibleCount = clamped;
        });
      }
    }
  }

  void _loadMore() {
    setState(() {
      _visibleCount = (_visibleCount + _pageStep).clamp(
        0,
        widget.entries.length,
      );
    });
  }

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

    final entries = widget.entries;
    final nowPulls = widget.nowPulls;
    final colors = widget.colors;
    final targetRank = widget.targetRank;
    final isAcrossBanners = widget.isAcrossBanners;

    if (entries.isEmpty && nowPulls == null) {
      return container(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(
            child: Text(
              l.timelineNoRecordsForRank(l.rarityStar(targetRank)),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    final effectiveCount = _visibleCount.clamp(0, entries.length);
    final visibleEntries = entries.take(effectiveCount).toList(growable: false);

    // 計算每個 visible entry 是否為月份分組首 row
    final monthFlag = <bool>[];
    int? prevYearMonth;
    for (final entry in visibleEntries) {
      final ym = entry.time.year * 12 + entry.time.month;
      monthFlag.add(prevYearMonth != ym);
      prevYearMonth = ym;
    }

    final remaining = entries.length - effectiveCount;

    return container(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              // 背景軸線
              Positioned(
                left: _railLeft,
                top: 0,
                bottom: 0,
                width: 2,
                child: Container(
                  color: tokens.textMuted.withValues(alpha: 0.3),
                ),
              ),
              // 前景:Column of rows
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (nowPulls != null)
                    _NowRow(
                      nowPulls: nowPulls,
                      targetRank: targetRank,
                      isAcrossBanners: isAcrossBanners,
                      tokens: tokens,
                    ),
                  for (var i = 0; i < visibleEntries.length; i++)
                    _EntryRow(
                      entry: visibleEntries[i],
                      showMonthTag: monthFlag[i],
                      colors: colors,
                      tokens: tokens,
                    ),
                ],
              ),
            ],
          ),
          if (remaining > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s),
              child: Center(
                child: TextButton.icon(
                  onPressed: _loadMore,
                  icon: const Icon(Icons.expand_more),
                  label: Text(l.timelineLoadMore(remaining)),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.textSecondary,
                  ),
                ),
              ),
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
          category: GachaCategory.gacha,
          pities: const [
            PityRule(rank: 5, threshold: 90),
            PityRule(rank: 4, threshold: 10),
          ],
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
          // 節點圓 (tooltip 目標 = halo 大小，會顯示在節點正上方)
          Tooltip(
            message: entry.name,
            preferBelow: false,
            waitDuration: const Duration(milliseconds: 100),
            child: SizedBox(
              width: _haloSize,
              child: Center(
                child: _Node(color: accent, tokens: tokens),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          // 名稱 + meta (各自 tooltip，目標 = 文字本身寬度)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: entry.name,
                    preferBelow: false,
                    waitDuration: const Duration(milliseconds: 100),
                    child: Text(
                      entry.name,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Tooltip(
                    message: entry.name,
                    preferBelow: false,
                    waitDuration: const Duration(milliseconds: 100),
                    child: Text(
                      '${_formatShortDate(entry.time)} · ${_bannerName(entry.gachaType, l)} · ${l.timelineSinceLast(entry.pullsSincePrev)}',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
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
    required this.targetRank,
    required this.isAcrossBanners,
    required this.tokens,
  });

  final int nowPulls;
  final int targetRank;
  final bool isAcrossBanners;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final meta = isAcrossBanners
        ? l.timelineNowSinceCrossPool(l.rarityStar(targetRank), nowPulls)
        : l.timelineNowSinceLast(l.rarityStar(targetRank), nowPulls);
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
