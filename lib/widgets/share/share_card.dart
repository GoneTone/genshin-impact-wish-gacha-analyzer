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
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rank_palette.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';

const double kShareCardWidth = 1200;

/// stat 卡 accent 來源（與 App overview_page 對齊）：
/// primary→tokens.accentPrimary、rank5→accentForRank(5)、rank4→accentForRank(4)。
/// factory 階段拿不到 tokens，故先記語意，於 [_SectionView.build] 再映射為 Color。
enum _StatAccent { primary, rank5, rank4 }

/// 一段內容描述（卡池模式 1 段；綜合模式 2 段）。
class _Section {
  const _Section({
    required this.title,
    required this.stats,
    required this.timeline,
    required this.timelineRank,
    required this.timelineNowPulls,
    required this.isAcrossBanners,
    required this.statLines,
  });
  final String title;
  final GachaStats stats;
  final List<TimelineEntry> timeline;
  final int timelineRank;

  /// 時間軸最頂端「現在」row 的累積抽數（重用 App TimelineVertical 的語意）。
  final int? timelineNowPulls;

  /// 跨卡池（綜合）時影響 TimelineVertical 的「現在」row 文案。
  final bool isAcrossBanners;

  /// 左欄數字摘要列：label + value + subtitle（subtitle 可空）+ accent 語意。
  final List<(String label, String value, String? sub, _StatAccent accent)>
  statLines;
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
          timelineNowPulls: pullsSinceLastRanked(records, rank: targetRank),
          isAcrossBanners: false,
          statLines: [
            (l.statsTotal, '${stats.total}', null, _StatAccent.primary),
            (
              l.statsRankCount(l.rarityStar(5)),
              '${stats.fiveStarCount}',
              _rateAvg(l, stats.fiveStarRate, fiveAvg),
              _StatAccent.rank5,
            ),
            (
              l.statsRankCount(l.rarityStar(4)),
              '${stats.fourStarCount}',
              _rateAvg(l, stats.fourStarRate, fourAvg),
              _StatAccent.rank4,
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
          timelineNowPulls: g.timelineNowPulls,
          isAcrossBanners: true,
          statLines: [
            (l.statsTotal, '${g.stats.total}', null, _StatAccent.primary),
            (
              l.statsRankCount(l.rarityStar(5)),
              '${g.stats.fiveStarCount}',
              _rateAvg(l, g.stats.fiveStarRate, g.fiveStarAvg),
              _StatAccent.rank5,
            ),
            (
              l.statsRankCount(l.rarityStar(4)),
              '${g.stats.fourStarCount}',
              _rateAvg(l, g.stats.fourStarRate, g.fourStarAvg),
              _StatAccent.rank4,
            ),
          ],
        ),
        _Section(
          title: l.pageOverviewOdesSection,
          stats: o.stats,
          timeline: o.timeline,
          timelineRank: o.timelineRank,
          timelineNowPulls: o.timelineNowPulls,
          isAcrossBanners: true,
          statLines: [
            (l.statsTotal, '${o.stats.total}', null, _StatAccent.primary),
            (
              '${odesEventType.resolveName(l)} ${l.rarityStar(5)}',
              '${o.eventFiveCount}',
              null,
              _StatAccent.rank5,
            ),
            (
              '${odesStdType.resolveName(l)} ${l.rarityStar(4)}',
              '${o.standardFourCount}',
              null,
              _StatAccent.rank4,
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
    final content = Column(
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
    );
    return Container(
      width: kShareCardWidth,
      color: tokens.surfaceBackground,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: content,
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

  Color _accentColor(_StatAccent a) => switch (a) {
    _StatAccent.primary => tokens.accentPrimary,
    _StatAccent.rank5 => accentForRank(5, tokens),
    _StatAccent.rank4 => accentForRank(4, tokens),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(section.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.m),
        // 頂部：三張 App StatCard 橫排，IntrinsicHeight + stretch 下等高。
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            key: const Key('shareStatRow'),
            children: [
              for (var i = 0; i < section.statLines.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: StatCard(
                    label: section.statLines[i].$1,
                    value: section.statLines[i].$2,
                    subtitle: section.statLines[i].$3,
                    accent: _accentColor(section.statLines[i].$4),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.l),
        // 下方：左欄雙圓餅 + 右欄時間軸，兩欄頂端對齊、各自然高。
        // 重用未改的 TimelineVertical（mainAxisSize.min）會讓較矮那欄底部留
        // surfaceBackground，這是「與 App 一致」的預期取捨，非缺陷。
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左欄：稀有度 + 類型雙圓餅（含圖例）
            Expanded(
              flex: 11,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PieBox(
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
                  const SizedBox(height: AppSpacing.m),
                  _PieBox(
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
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.l),
            // 右欄：時間軸。標題透過 TimelineVertical.title 進到卡片 container
            // 內，與 _PieBox 卡內 labelSmall 標題同風格；底部剩餘提示維持卡外
            // （bodySmall）。take(10) → 其內部 remaining=0 不出現「載入更多」。
            Expanded(
              flex: 9,
              child: _TimelineColumn(
                l: l,
                section: section,
                colors: colors,
                tokens: tokens,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 右欄時間軸：TimelineVertical（自帶 container，標題透過 title 參數進到
/// 卡內、最多顯示 10 筆）+ 底部卡外剩餘筆數提示（僅 remaining > 0 時）。
class _TimelineColumn extends StatelessWidget {
  const _TimelineColumn({
    required this.l,
    required this.section,
    required this.colors,
    required this.tokens,
  });
  final AppLocalizations l;
  final _Section section;
  final BannerColors colors;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rank = section.timelineRank;
    final shown = section.timeline.take(10).toList(growable: false);
    final remaining = section.timeline.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TimelineVertical(
          title: l.timelineTopRarityTitle(l.rarityStar(rank), shown.length),
          entries: shown,
          colors: colors,
          targetRank: rank,
          nowPulls: section.timelineNowPulls,
          isAcrossBanners: section.isAcrossBanners,
        ),
        if (remaining > 0) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            l.shareImageTimelineMore(remaining, l.rarityStar(rank)),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.textMuted),
          ),
        ],
      ],
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
