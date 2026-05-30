import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/five_star_collection.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
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
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/five_star_overview.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/left_driven_equal_height.dart';

/// 分享圖固定寬度（邏輯像素）。
const double kShareCardWidth = 1200;

/// _PieBox 內圓餅固定高（與 [_PieBox.build] 內 `SizedBox(height: …)` 同值）。
const double _kPieDiameterBox = 200;

/// 分享圖時間軸最多展示筆數（沿用 App TimelineVertical `_initialPageSize`，
/// 避免出現「載入更多」按鈕）。超出右欄高度的部分由 Stack(Clip.hardEdge)
/// 直接裁掉，不再精算截斷。
const int _kShareTimelineMaxEntries = 10;

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
    this.fiveStar = const [],
  });

  /// 段落標題文字（例如祈願段名稱或卡池名稱）。
  final String title;

  /// 此段合計統計資料。
  final GachaStats stats;

  /// 時間軸條目清單。
  final List<TimelineEntry> timeline;

  /// 時間軸目標星級。
  final int timelineRank;

  /// 時間軸最頂端「現在」row 的累積抽數（重用 App TimelineVertical 的語意）。
  final int? timelineNowPulls;

  /// 跨卡池（綜合）時影響 TimelineVertical 的「現在」row 文案。
  final bool isAcrossBanners;

  /// 左欄數字摘要列：label + value + subtitle（subtitle 可空）+ accent 語意。
  final List<(String label, String value, String? sub, _StatAccent accent)>
  statLines;

  /// 此段尾端的五星一覽清單（祈願段才有；頌願段為空 → 不顯示）。
  final List<FiveStarCollectionItem> fiveStar;
}

/// 分享圖固定寬版面（版面 B：左數字+雙圓餅，右垂直時間軸）。
///
/// 所有外部相依由建構子注入；圖示為預解碼 [ui.Image]，避免離屏同步渲染時
/// Image.asset 的 async 載入無法完成。
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
    required HoYoWikiIndex index,
  }) {
    final stats = computeGachaStats(records, index: index);
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
          fiveStar: buildFiveStarCollection(records, index: index),
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
    required HoYoWikiIndex index,
  }) {
    final s = buildOverviewSections(banners, index: index);
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
          fiveStar: buildFiveStarCollectionAcrossBanners(
            s.gacha.banners,
            index: index,
          ),
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

  /// 當前語系的本地化字串。
  final AppLocalizations l;

  /// App 版本號，顯示於頂部 header。
  final String appVersion;

  /// 預解碼的 App icon，以 [RawImage] 同步繪製。
  final ui.Image appIcon;

  /// 分享圖選項（亮暗模式、UID 顯示方式）。
  final ShareImageOptions options;

  /// 使用者 UID（依 [options] 決定是否遮蔽）。
  final String uid;

  /// 資料最後更新時間，顯示於 header 右側。
  final DateTime updatedAt;

  /// 各段內容（卡池模式 1 段；綜合模式 2 段）。
  final List<_Section> _sections;

  /// 格式化「佔比 · 平均間隔」副標題字串；avg 為 null 時只回傳佔比。
  static String? _rateAvg(AppLocalizations l, double rate, double? avg) {
    final pct = l.statsShareOfTotal((rate * 100).toStringAsFixed(2));
    if (avg == null) return pct;
    return '$pct · ${l.pityAverageInterval(avg.toStringAsFixed(2))}';
  }

  /// 依 [options] 決定顯示完整或遮蔽後的 UID。
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

/// 分享圖頂部 header：App icon + 名稱/版本 + GitHub URL + UID + 更新時間。
class _ShareHeader extends StatelessWidget {
  const _ShareHeader({
    required this.l,
    required this.appVersion,
    required this.appIcon,
    required this.uidText,
    required this.updatedAt,
    required this.tokens,
  });

  /// 當前語系的本地化字串。
  final AppLocalizations l;

  /// App 版本號。
  final String appVersion;

  /// 預解碼的 App icon。
  final ui.Image appIcon;

  /// 已依選項遮蔽或完整的 UID 字串。
  final String uidText;

  /// 資料最後更新時間。
  final DateTime updatedAt;

  /// 主題 token，用於文字顏色。
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

/// 一段祈願/頌願內容的版面：標題 + StatCard 橫排 + 左圓餅/右時間軸。
class _SectionView extends StatelessWidget {
  const _SectionView({
    required this.l,
    required this.section,
    required this.colors,
    required this.brightness,
    required this.tokens,
  });

  /// 當前語系的本地化字串。
  final AppLocalizations l;

  /// 此段資料。
  final _Section section;

  /// 卡池色彩對應表（依亮暗模式選取）。
  final BannerColors colors;

  /// 亮暗模式，用於 ItemTypePie 圖例色彩。
  final Brightness brightness;

  /// 主題 token。
  final GachaTokens tokens;

  /// 將 [_StatAccent] 語意映射為實際 [Color]。
  Color _accentColor(_StatAccent a) => switch (a) {
    _StatAccent.primary => tokens.accentPrimary,
    _StatAccent.rank5 => accentForRank(5, tokens),
    _StatAccent.rank4 => accentForRank(4, tokens),
  };

  /// 右欄時間軸：重用 App TimelineVertical（自帶 container）。標題透過 title
  /// 進到卡片 border 內。最多取 [_kShareTimelineMaxEntries] 筆（避免出現
  /// 「載入更多」按鈕），以**自然高度**繪製；超出右欄區域（= 左欄兩 _PieBox
  /// 疊高）的部分由外層 Stack(Clip.hardEdge) 直接裁掉，不報 overflow、不反拉
  /// 左欄。不再傳 footerNote / fillHeight（已移除「還有 N 筆」與撐齊邏輯）。
  Widget _timeline() {
    final rank = section.timelineRank;
    final n = section.timeline.length < _kShareTimelineMaxEntries
        ? section.timeline.length
        : _kShareTimelineMaxEntries;
    final shown = section.timeline.take(n).toList(growable: false);
    return TimelineVertical(
      title: l.timelineTopRarityTitle(l.rarityStar(rank), shown.length),
      entries: shown,
      colors: colors,
      targetRank: rank,
      nowPulls: section.timelineNowPulls,
      isAcrossBanners: section.isAcrossBanners,
      fillHeight: true,
    );
  }

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
        // 下方：左欄雙圓餅 + 右欄時間軸，右欄高度由左欄量測後強制等高
        // （LeftDrivenEqualHeight）。右欄 fillHeight：內容少→卡內底部留白、
        // 內容多→底部由 TimelineVertical 自身 ClipRect 裁切。
        LeftDrivenEqualHeight(
          children: [
            // index 0 = 左欄：稀有度 + 類型雙圓餅（含圖例）
            Column(
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
            // index 1 = 右欄：時間軸（fillHeight，超出自身裁切）
            _timeline(),
          ],
        ),
        // 五星一覽掛在該段尾端（祈願段才有；頌願段為空 → 不顯示），
        // 確保綜合分享圖的五星落在祈願區底下、而非整張圖最末的頌願區後。
        if (section.fiveStar.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.l),
          Text(
            l.rarityOverviewTitle(l.rarityStar(5)),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.m),
          FiveStarOverview(items: section.fiveStar, interactive: false),
        ],
      ],
    );
  }
}

/// 圓餅圖容器：標題 + 固定高圓餅 + 圖例，帶卡片邊框背景。
class _PieBox extends StatelessWidget {
  const _PieBox({
    required this.title,
    required this.pie,
    required this.legend,
    required this.tokens,
  });

  /// 卡片標題文字。
  final String title;

  /// 圓餅圖 widget（RarityPie 或 ItemTypePie）。
  final Widget pie;

  /// 圖例 widget（DistributionLegend）。
  final Widget legend;

  /// 主題 token，用於背景色與邊框色。
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
          SizedBox(height: _kPieDiameterBox, child: pie),
          const SizedBox(height: AppSpacing.s),
          legend,
        ],
      ),
    );
  }
}
