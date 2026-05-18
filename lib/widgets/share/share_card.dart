// lib/widgets/share/share_card.dart
//
// 分享圖固定寬版面（版面 B：左數字+雙圓餅，右垂直時間軸）。
// 所有外部相依由建構子注入；圖示為預解碼 ui.Image，避免離屏同步渲染時
// Image.asset 的 async 載入無法完成。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/overview_sections.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_uid_mask.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';

const double kShareCardWidth = 1200;

/// 一段內容描述（卡池模式 1 段；綜合模式 2 段）。
class _Section {
  const _Section({
    required this.title,
    required this.stats,
    required this.timeline,
    required this.timelineRank,
    required this.statLines,
  });
  final String title;
  final GachaStats stats;
  final List<TimelineEntry> timeline;
  final int timelineRank;

  /// 左欄數字摘要列：label + value + subtitle（subtitle 可空）。
  final List<(String label, String value, String? sub)> statLines;
}

class ShareCard extends StatelessWidget {
  const ShareCard._({
    required this.l,
    required this.appVersion,
    required this.appIcon,
    required this.options,
    required this.uid,
    required this.updatedAt,
    required List<_Section> sections,
  }) : _sections = sections;

  /// 單一卡池頁分享。
  factory ShareCard.banner({
    required AppLocalizations l,
    required String appVersion,
    required ui.Image appIcon,
    required ShareImageOptions options,
    required String uid,
    required DateTime updatedAt,
    required String title,
    required List<GachaRecord> records,
    required int targetRank,
  }) {
    final stats = computeGachaStats(records);
    // threshold: 0 — 此處只取 averageInterval，不需 pity progress/distance
    // （與 gacha_pity.dart 的 averageIntervalAcrossBanners 同一慣例）。
    final fiveAvg = computePity(records, threshold: 0, rank: 5).averageInterval;
    final fourAvg = computePity(records, threshold: 0, rank: 4).averageInterval;
    return ShareCard._(
      l: l,
      appVersion: appVersion,
      appIcon: appIcon,
      options: options,
      uid: uid,
      updatedAt: updatedAt,
      sections: [
        _Section(
          title: title,
          stats: stats,
          timeline: buildTimelineEntries(records, targetRank: targetRank),
          timelineRank: targetRank,
          statLines: [
            (l.statsTotal, '${stats.total}', null),
            (
              l.statsRankCount(l.rarityStar(5)),
              '${stats.fiveStarCount}',
              _rateAvg(l, stats.fiveStarRate, fiveAvg),
            ),
            (
              l.statsRankCount(l.rarityStar(4)),
              '${stats.fourStarCount}',
              _rateAvg(l, stats.fourStarRate, fourAvg),
            ),
          ],
        ),
      ],
    );
  }

  /// 綜合頁分享（祈願 + 頌願兩段）。
  factory ShareCard.overview({
    required AppLocalizations l,
    required String appVersion,
    required ui.Image appIcon,
    required ShareImageOptions options,
    required String uid,
    required DateTime updatedAt,
    required Map<String, List<GachaRecord>> banners,
  }) {
    final s = buildOverviewSections(banners);
    final g = s.gacha;
    final o = s.odes;
    // '2000'/'1000' 必定存在：o.types 來自 lib/data/gacha_types.dart 的靜態常數，
    // 頌願活動/常駐卡池為固定資料，故 firstWhere 無需 orElse。
    final odesEventType = o.types.firstWhere((t) => t.gachaType == '2000');
    final odesStdType = o.types.firstWhere((t) => t.gachaType == '1000');
    return ShareCard._(
      l: l,
      appVersion: appVersion,
      appIcon: appIcon,
      options: options,
      uid: uid,
      updatedAt: updatedAt,
      sections: [
        _Section(
          title: l.pageOverviewGachaSection,
          stats: g.stats,
          timeline: g.timeline,
          timelineRank: g.timelineRank,
          statLines: [
            (l.statsTotal, '${g.stats.total}', null),
            (
              l.statsRankCount(l.rarityStar(5)),
              '${g.stats.fiveStarCount}',
              _rateAvg(l, g.stats.fiveStarRate, g.fiveStarAvg),
            ),
            (
              l.statsRankCount(l.rarityStar(4)),
              '${g.stats.fourStarCount}',
              _rateAvg(l, g.stats.fourStarRate, g.fourStarAvg),
            ),
          ],
        ),
        _Section(
          title: l.pageOverviewOdesSection,
          stats: o.stats,
          timeline: o.timeline,
          timelineRank: o.timelineRank,
          statLines: [
            (l.statsTotal, '${o.stats.total}', null),
            (
              '${odesEventType.resolveName(l)} ${l.rarityStar(5)}',
              '${o.eventFiveCount}',
              null,
            ),
            (
              '${odesStdType.resolveName(l)} ${l.rarityStar(4)}',
              '${o.standardFourCount}',
              null,
            ),
          ],
        ),
      ],
    );
  }

  final AppLocalizations l;
  final String appVersion;
  final ui.Image appIcon;
  final ShareImageOptions options;
  final String uid;
  final DateTime updatedAt;
  final List<_Section> _sections;

  static String? _rateAvg(AppLocalizations l, double rate, double? avg) {
    final pct = l.statsShareOfTotal((rate * 100).toStringAsFixed(2));
    if (avg == null) return pct;
    return '$pct · ${l.pityAverageInterval(avg.toStringAsFixed(2))}';
  }

  String get _uidText => options.showFullUid ? uid : maskUidForShare(uid);

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final colors = BannerColors.of(options.brightness);
    return Container(
      width: kShareCardWidth,
      color: tokens.surfaceBackground,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShareHeader(
            l: l,
            appVersion: appVersion,
            appIcon: appIcon,
            uidText: _uidText,
            updatedAt: updatedAt,
            tokens: tokens,
          ),
          const SizedBox(height: AppSpacing.xl),
          for (var i = 0; i < _sections.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: AppSpacing.xl),
              Divider(color: tokens.borderEmphasis, height: 1, thickness: 1),
              const SizedBox(height: AppSpacing.xl),
            ],
            _SectionView(
              l: l,
              section: _sections[i],
              colors: colors,
              brightness: options.brightness,
              tokens: tokens,
            ),
          ],
        ],
      ),
    );
  }
}

class _ShareHeader extends StatelessWidget {
  const _ShareHeader({
    required this.l,
    required this.appVersion,
    required this.appIcon,
    required this.uidText,
    required this.updatedAt,
    required this.tokens,
  });
  final AppLocalizations l;
  final String appVersion;
  final ui.Image appIcon;
  final String uidText;
  final DateTime updatedAt;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ts = DateFormat('yyyy-MM-dd HH:mm').format(updatedAt);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: RawImage(image: appIcon, fit: BoxFit.contain),
        ),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l.appName} v$appVersion',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppRepo.githubUrl,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.m),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'UID $uidText',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l.shareImageUpdatedAt(ts),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({
    required this.l,
    required this.section,
    required this.colors,
    required this.brightness,
    required this.tokens,
  });
  final AppLocalizations l;
  final _Section section;
  final BannerColors colors;
  final Brightness brightness;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(section.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.m),
        // IntrinsicHeight：讓左欄（數字+雙圓餅）與右欄（時間軸）等高，
        // 分享版面兩欄底部對齊。
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左欄：數字摘要 + 雙圓餅
              Expanded(
                flex: 11,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final line in section.statLines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s),
                        child: _StatTile(line: line, tokens: tokens),
                      ),
                    const SizedBox(height: AppSpacing.s),
                    Row(
                      children: [
                        Expanded(
                          child: _PieBox(
                            title: l.statsRarityDistribution,
                            pie: RarityPie(
                              stats: section.stats,
                              animationDuration: Duration.zero,
                            ),
                            legend: DistributionLegend(
                              entries: rarityDistributionEntries(
                                section.stats,
                                tokens,
                                l,
                              ),
                            ),
                            tokens: tokens,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(
                          child: _PieBox(
                            title: l.statsItemTypeDistribution,
                            pie: ItemTypePie(
                              stats: section.stats,
                              animationDuration: Duration.zero,
                            ),
                            legend: DistributionLegend(
                              entries: itemTypeDistributionEntries(
                                section.stats,
                                brightness,
                                l,
                              ),
                            ),
                            tokens: tokens,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.l),
              // 右欄：垂直時間軸（最新 10 筆）
              Expanded(
                flex: 9,
                child: _ShareTimeline(
                  l: l,
                  entries: section.timeline.take(10).toList(growable: false),
                  rank: section.timelineRank,
                  colors: colors,
                  tokens: tokens,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.line, required this.tokens});
  final (String, String, String?) line;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.borderSubtle),
      ),
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Row(
        children: [
          Expanded(
            child: Text(
              line.$1,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  line.$2,
                  maxLines: 1,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
                if (line.$3 != null)
                  Text(
                    line.$3!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PieBox extends StatelessWidget {
  const _PieBox({
    required this.title,
    required this.pie,
    required this.legend,
    required this.tokens,
  });
  final String title;
  final Widget pie;
  final Widget legend;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.borderSubtle),
      ),
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.labelSmall),
          const SizedBox(height: AppSpacing.s),
          SizedBox(height: 200, child: pie),
          const SizedBox(height: AppSpacing.s),
          legend,
        ],
      ),
    );
  }
}

class _ShareTimeline extends StatelessWidget {
  const _ShareTimeline({
    required this.l,
    required this.entries,
    required this.rank,
    required this.colors,
    required this.tokens,
  });
  final AppLocalizations l;
  final List<TimelineEntry> entries;
  final int rank;
  final BannerColors colors;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.borderSubtle),
      ),
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.shareImageTimelineTitle(entries.length, l.rarityStar(rank)),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: AppSpacing.s),
          if (entries.isEmpty)
            Text(
              l.statsNoData,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            )
          else
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors.colorFor(e.gachaType),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Text(
                      '${e.pullsSincePrev}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
