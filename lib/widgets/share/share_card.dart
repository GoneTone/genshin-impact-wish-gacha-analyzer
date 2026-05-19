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

/// _PieBox 內圓餅固定高（與 [_PieBox.build] 內 `SizedBox(height: …)` 同值）。
/// 抽成具名常數讓左欄高度估算與實際渲染共用同一數值，改一處即同步。
const double _kPieDiameterBox = 200;

// ── 校準常數：以 widget test 實測精算（不再過度保守）─────────────────────
//
// 「右欄不超出左欄、也不反拉左欄圓餅卡」由離屏渲染下 fillHeight:true +
// 下方 IntrinsicHeight(Row stretch) 機制硬性保證（多資料集像素 diff=0）。
// 因此本估算**無需為了不超出而保守低估**；估算唯一職責是「避免 N 過大
// 致右欄內容 > H 造成 RenderFlex overflow」，故每筆只加極小 buffer 即可，
// 取精確實測值讓 N 盡量大、右卡接近填滿、留白縮到最小。
//
// 左欄 _PieBox：以同一 rarity _PieBox 控制變因（固定圓餅+padding，只變
//   legend 行數）量外框 Container getSize().height：
//   1 行=302、3 行=390、4 行=434 ⇒ 完美線性
//   perRow = (434−302)/3 = 44/行；base = 302 − 1*44 = 258
//   驗證：258+1*44=302 ✓ 258+3*44=390 ✓ 258+4*44=434 ✓
//   itemType _PieBox 結構同（同 labelSmall 標題+同 _kPieDiameterBox 圓餅
//   +同 padding，差別僅 legend 行數），套用同一公式。取精確值不下調。
const double _kPieBoxBase = 258; // 實測精確截距
const double _kPieBoxLegendRow = 44; // 實測精確 perRow

// 右欄 TimelineVertical：**務必在分享圖右欄真實外框寬度量**（實測分享圖
//   右欄 TimelineVertical 外框 ≈ 331px；meta 文字「MM/DD · 卡池 · 距上次」
//   在此寬度會換行成 2 行 → 行高才是真值，用更寬的近似值量會少算行高→N 過大
//   →右欄 overflow，正是本次需避免的陷阱）。固定 title+footer，量外框
//   Container getSize().height（now=null：高 = chrome + 各 entry 行高）：
//     same  n=1=164  n=2=234  n=10=794（第 0 筆帶月份 tag、其餘無）
//     cross n=1=164  n=2=246  n=10=902（每筆都帶月份 tag）
//   解線性方程：
//     無月份標籤每筆 NO = (234−164)/1 = 70（= (794−164)/9 ✓）
//     有月份標籤每筆 W  = (246−164)/1 = 82（= (902−164)/9 ✓）
//     chrome = 164 − 1*W = 82
//       （= container 垂直 padding 32 + labelSmall 標題 + AppSpacing.s 8
//          + footer 區 AppSpacing.s 8 + bodySmall 行高；一律假設有 footer，
//          截斷時 remaining>0 幾乎必然有 footer，無 footer 反而更鬆）
//   驗證：same n=10 = 82+82+9*70=794 ✓ cross n=10 = 82+10*82=902 ✓
//   _NowRow 增量：同 N now=null vs now=30 一律差 53（164→217、234→287…）。
// 各加極小 buffer（+3~4px）讓估算略高估、N 不會多算到 overflow，但遠比
//   bcd7a0d 一律 96/90 精準（精算非過度保守；不超出由 fillHeight+
//   IntrinsicHeight 保證，本估算僅防 N 過大致 RenderFlex overflow）。
const double _kEntryRowNoMonth = 73; // 實測 70 + 3 buffer
const double _kEntryRowWithMonth = 85; // 實測 82 + 3 buffer
const double _kTimelineChrome = 86; // 實測 82 + 4 buffer（padding+title+footer）
const double _kTimelineNowRow = 56; // 實測 53 + 3 buffer

/// 分享圖時間軸最多展示筆數（沿用 App TimelineVertical `_initialPageSize`）。
const int _kShareTimelineMaxEntries = 10;

double _pieBoxHeight(int legendRows) =>
    _kPieBoxBase + legendRows * _kPieBoxLegendRow;

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

  /// 左欄兩張 _PieBox 疊起來的目標總高（純計算，相容離屏同步單次渲染，
  /// 不可用量測→setState→重 build）。row 數與 [DistributionLegend]
  /// `showAllEntries:false`（過濾 count==0）一致，故與實渲染逐像素對齊。
  double get _leftColumnHeight {
    final rarityRows = rarityDistributionEntries(
      section.stats,
      tokens,
      l,
    ).where((e) => e.count > 0).length;
    final itemRows = itemTypeDistributionEntries(
      section.stats,
      brightness,
      l,
    ).where((e) => e.count > 0).length;
    return _pieBoxHeight(rarityRows) + AppSpacing.m + _pieBoxHeight(itemRows);
  }

  /// 前 [n] 筆時間軸 entry 中，有幾筆會顯示月份標籤（較高的 _EntryRow）。
  ///
  /// 規則必須與 [TimelineVertical] 完全一致（timeline_vertical.dart）：
  /// ```
  /// int? prevYearMonth;
  /// for (entry) { ym = year*12+month; flag = prevYearMonth != ym; prev = ym; }
  /// ```
  /// 即第 0 筆必顯示（prevYearMonth==null）；之後與前一筆 (year,month) 不同
  /// 才顯示。_NowRow 不參與此分組（TimelineVertical 迴圈只跑 entries）。
  int _monthTagCount(int n) {
    var count = 0;
    int? prevYearMonth;
    for (var i = 0; i < n; i++) {
      final t = section.timeline[i].time;
      final ym = t.year * 12 + t.month;
      if (prevYearMonth != ym) count++;
      prevYearMonth = ym;
    }
    return count;
  }

  /// 在左欄真實高度 H 內塞得下的**最多**筆數（精算迭代，使 fillHeight 撐齊
  /// 後右卡接近填滿、留白縮到最小）。每筆依「是否顯示月份標籤」分兩種行高
  /// 精估（非一律最壞上界），故 N 接近真實可放數。多出的較早筆數併入底部
  /// footerNote。「右欄不超出/不反拉左欄」由 fillHeight + IntrinsicHeight
  /// 機制保證，本估算僅防 N 過大致 RenderFlex overflow。
  int get _maxTimelineEntries {
    final total = section.timeline.length;
    final hasNowRow = section.timelineNowPulls != null;
    // chrome 一律假設有 footer（截斷時 remaining>0 幾乎必然有 footer；若最終
    // 無 footer 反而更鬆、仍不 overflow）。
    final avail =
        _leftColumnHeight -
        _kTimelineChrome -
        (hasNowRow ? _kTimelineNowRow : 0);
    if (avail <= 0) return 0;
    final maxN = total < _kShareTimelineMaxEntries
        ? total
        : _kShareTimelineMaxEntries;
    // 找最大 N（≤ maxN）使前 N 筆估高 ≤ avail。
    for (var n = maxN; n >= 0; n--) {
      final m = _monthTagCount(n);
      final est = (n - m) * _kEntryRowNoMonth + m * _kEntryRowWithMonth;
      if (est <= avail) return n;
    }
    return 0;
  }

  /// 右欄時間軸：重用 App TimelineVertical（自帶 container）。標題與底部
  /// 「還有 N 筆較早」提示皆透過 title / footerNote 進到卡片 border 內。
  /// 展示筆數 N 由 [_maxTimelineEntries] 保守估算，確保右側卡內容估算高
  /// ≤ 左欄兩 _PieBox 疊高；因 N 已使右內容 ≤ H，下方 IntrinsicHeight 的
  /// 較高側恆為左欄，右欄 fillHeight 撐到左欄高、絕不反拉左欄圓餅卡。
  /// footerNote 僅在 remaining > 0 時傳入。
  Widget _timeline() {
    final rank = section.timelineRank;
    final n = _maxTimelineEntries;
    final shown = section.timeline.take(n).toList(growable: false);
    final remaining = section.timeline.length - shown.length;
    return TimelineVertical(
      title: l.timelineTopRarityTitle(l.rarityStar(rank), shown.length),
      footerNote: remaining > 0
          ? l.shareImageTimelineMore(remaining, l.rarityStar(rank))
          : null,
      fillHeight: true,
      entries: shown,
      colors: colors,
      targetRank: rank,
      nowPulls: section.timelineNowPulls,
      isAcrossBanners: section.isAcrossBanners,
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
        // 下方：左欄雙圓餅 + 右欄時間軸，IntrinsicHeight + stretch 下兩欄等高
        // （取較高者，通常為左欄兩張圓餅卡疊起來）。右欄 TimelineVertical 傳
        // fillHeight: true 讓其卡片撐滿被拉高的高度；5★ 筆數少時時間軸卡底部
        // 會留卡內空白，這是已決定的取捨。
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              // 右欄：時間軸。標題與底部「還有 N 筆較早」提示皆透過
              // TimelineVertical 的 title / footerNote 進到卡片 container 內，
              // 與 _PieBox 卡內 labelSmall 標題同風格。take(10) → 其內部
              // remaining=0 不出現「載入更多」按鈕；footerNote 僅在實際有未
              // 顯示的較早紀錄（remaining > 0）時才傳入。
              Expanded(flex: 9, child: _timeline()),
            ],
          ),
        ),
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
          SizedBox(height: _kPieDiameterBox, child: pie),
          const SizedBox(height: AppSpacing.s),
          legend,
        ],
      ),
    );
  }
}
