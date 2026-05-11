import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

const double _colWidth = 90;
const double _nodeSize = 14;
const double _haloSize = 22;

/// 從跨卡池 timeline entries 統計各卡池的 5★ 數量,輸出可餵給
/// [DistributionLegend] (記得搭配 `showAllEntries: true`) 的條目,作為
/// [TimelineHorizontal] 在跨卡池場景下的顏色圖例。
///
/// 一律輸出 `gachaTypes` 列出的全部卡池(包括 count == 0 的),讓使用者
/// 可以從顏色直接對應卡池;rate 仍以 (count / total) 計算,total = 0 時為 0。
List<DistributionEntry> bannerDistributionEntries(
  List<TimelineEntry> entries,
  BannerColors colors,
  AppLocalizations l,
) {
  final countByGachaType = <String, int>{};
  for (final e in entries) {
    countByGachaType[e.gachaType] = (countByGachaType[e.gachaType] ?? 0) + 1;
  }
  final total = entries.length;
  return [
    for (final type in gachaTypes)
      DistributionEntry(
        color: colors.colorFor(type.gachaType),
        name: type.resolveName(l),
        count: countByGachaType[type.gachaType] ?? 0,
        rate: total == 0 ? 0 : (countByGachaType[type.gachaType] ?? 0) / total,
      ),
  ];
}

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

    // 軸線固定在 viewport(timeline 慣例:節點滑過軸線)。
    // 兩個 Positioned.fill 都拿到 tight constraints,確保 SingleChildScrollView
    // 的 viewport 寬度 = Stack 寬度,Row 內容 (N × _colWidth) 一旦超過就 scroll。
    return Stack(
      children: [
        // 背景軸線:viewport 水平中央,跨整個可見寬度
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
            child: Center(
              child: Container(
                height: 2,
                color: tokens.textMuted.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
        // 內容層:橫向 scroll,Row 寬度 = N × _colWidth
        // ScrollConfiguration 加入 mouse / trackpad 為 drag devices — 桌面端
        // 預設只接受 touch,沒有這層使用者用滑鼠拖不動 scroll view。
        Positioned.fill(
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: const {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (nowPulls != null)
                      _NowColumn(nowPulls: nowPulls!, tokens: tokens),
                    for (final entry in entries)
                      _EntryColumn(
                        entry: entry,
                        colors: colors,
                        tokens: tokens,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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

  static String _formatShortDate(DateTime t) {
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
  const _NowColumn({required this.nowPulls, required this.tokens});
  final int nowPulls;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SizedBox(
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
