import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/ads/ad_placement.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/five_star_collection.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/overview_sections.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/ads.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/ads/native_ad.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/banner_top_rarity_bars.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/five_star_overview.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/inline_section_title.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/last_updated_label.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/loading_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rank_palette.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_action_button.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_image_helper.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/width_layout_builder.dart';

/// 總覽頁，將 gacha 與 odes 分兩段各自呈現統計、圖表、timeline。
class OverviewPage extends ConsumerWidget {
  /// 建立 [OverviewPage]。
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    // 只訂閱用到的欄位：更新時進度每換一池就變一次，訂閱整個狀態會讓整頁跟著重算統計。
    final (:activeData, :isBootstrapping) = ref.watch(
      gachaRepositoryProvider.select(
        (s) => (activeData: s.activeData, isBootstrapping: s.isBootstrapping),
      ),
    );
    // 兩段各自判斷有沒有記錄：空狀態的段落不放廣告。
    final isAndroid = ref.watch(isAndroidProvider);
    final canRequestAds = ref.watch(adsProvider.select((s) => s.canRequestAds));
    final gachaAdsAllowed =
        isAndroid &&
        canRequestAds &&
        ref.watch(
          gachaRepositoryProvider.select(
            (g) => overviewSectionHasAdContent(
              category: GachaCategory.gacha,
              gacha: g,
            ),
          ),
        );
    final odesAdsAllowed =
        isAndroid &&
        canRequestAds &&
        ref.watch(
          gachaRepositoryProvider.select(
            (g) => overviewSectionHasAdContent(
              category: GachaCategory.odes,
              gacha: g,
            ),
          ),
        );

    if (isBootstrapping) {
      return const LoadingState();
    }
    if (activeData == null) {
      return noSyncPageBody(context);
    }

    final sections = buildOverviewSections(
      activeData.banners,
      index: ref.watch(hoyowikiIndexProvider),
    );
    final gachaSec = sections.gacha;
    final odesSec = sections.odes;
    final bannerColors = BannerColors.of(Theme.of(context).brightness);

    String shareWithAvg(String shareText, double? avg) {
      if (avg == null) return shareText;
      return '$shareText · ${l.pityAverageInterval(avg.toStringAsFixed(2))}';
    }

    final gachaStatCards = <Widget>[
      StatCard(
        label: l.statsTotal,
        value: '${gachaSec.stats.total}',
        accent: tokens.accentPrimary,
      ),
      StatCard(
        label: l.statsRankCount(l.rarityStar(5)),
        value: '${gachaSec.stats.fiveStarCount}',
        accent: tokens.fiveStar,
        subtitle: shareWithAvg(
          l.statsShareOfTotal(
            (gachaSec.stats.fiveStarRate * 100).toStringAsFixed(2),
          ),
          gachaSec.fiveStarAvg,
        ),
      ),
      StatCard(
        label: l.statsRankCount(l.rarityStar(4)),
        value: '${gachaSec.stats.fourStarCount}',
        accent: tokens.fourStar,
        subtitle: shareWithAvg(
          l.statsShareOfTotal(
            (gachaSec.stats.fourStarRate * 100).toStringAsFixed(2),
          ),
          gachaSec.fourStarAvg,
        ),
      ),
    ];

    final odesEventType = odesSec.types.firstWhere(
      (t) => t.gachaType == '2000',
    );
    final odesStandardType = odesSec.types.firstWhere(
      (t) => t.gachaType == '1000',
    );
    final odesStatCards = <Widget>[
      StatCard(
        label: l.statsTotal,
        value: '${odesSec.stats.total}',
        accent: tokens.accentPrimary,
      ),
      StatCard(
        label: '${odesEventType.resolveName(l)} ${l.rarityStar(5)}',
        value: '${odesSec.eventFiveCount}',
        accent: accentForRank(5, tokens),
      ),
      StatCard(
        label: '${odesStandardType.resolveName(l)} ${l.rarityStar(4)}',
        value: '${odesSec.standardFourCount}',
        accent: accentForRank(4, tokens),
      ),
    ];

    final pagePadding = pagePaddingOf(context);
    final brightness = Theme.of(context).brightness;
    // 廣告在頁面層級監聽：放進按需建構的子項，捲出畫面就會被釋放、捲回來又重新載入；
    // 寬度要等版面才知道，LayoutBuilder 裡不能用此處的 ref.watch，改由 Consumer 監聽。
    return WidthLayoutBuilder(
      builder: (context, width) {
        final fits = width - pagePadding * 2 >= kNativeMinWidth;
        return Consumer(
          builder: (context, adsRef, _) {
            /// 讀取 [placement] 已載入的廣告；條件不符時不監聽，回傳 null。
            LoadedNative? adOf(NativeAdPlacement placement, bool allowed) =>
                allowed && fits
                ? adsRef
                      .watch(
                        nativeAdProvider((
                          placement: placement,
                          scope: 'overview',
                          brightness: brightness,
                        )),
                      )
                      .value
                : null;
            return _buildScroll(
              context,
              ref,
              l,
              activeData,
              gachaSec,
              odesSec,
              gachaStatCards,
              odesStatCards,
              bannerColors,
              pagePadding,
              adOf(NativeAdPlacement.overviewGacha, gachaAdsAllowed),
              adOf(NativeAdPlacement.overviewOdes, odesAdsAllowed),
            );
          },
        );
      },
    );
  }

  /// 總覽頁的捲動內容；[gachaAd]／[odesAd] 非 null 時在該段「類型分布」與「各卡池主稀有度件數」之間插入原生廣告。
  Widget _buildScroll(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    BannerStorage activeData,
    GachaSectionData gachaSec,
    OdesSectionData odesSec,
    List<Widget> gachaStatCards,
    List<Widget> odesStatCards,
    BannerColors bannerColors,
    double pagePadding,
    LoadedNative? gachaAd,
    LoadedNative? odesAd,
  ) {
    // 按需建構：標題列與區塊內容都是清單裡的獨立項目，畫面外的五星一覽與時間軸不會被建構。
    return CustomScrollView(
      scrollCacheExtent: pageScrollCacheExtent(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.all(pagePadding),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: PageHeader(
                        title: l.pageOverviewTitle,
                        icon: Icons.dashboard_outlined,
                        trailing: phoneLandscapeLastUpdated(context),
                      ),
                    ),
                    ShareActionButton(
                      enabled: activeData.banners.values.any(
                        (r) => r.isNotEmpty,
                      ),
                      onGenerate: () =>
                          _generateOverviewShare(context, ref, l, activeData),
                    ),
                  ],
                ),
              ),
              _OverviewSection(
                adPlacement: NativeAdPlacement.overviewGacha,
                title: l.pageOverviewGachaSection,
                types: gachaSec.types,
                banners: gachaSec.banners,
                stats: gachaSec.stats,
                bannerColors: bannerColors,
                statCards: gachaStatCards,
                emptyTitle: l.emptyNoGachaRecords,
                timeline: gachaSec.timeline,
                timelineNowPulls: gachaSec.timelineNowPulls,
                timelineRank: gachaSec.timelineRank,
                fiveStarItems: buildFiveStarCollectionAcrossBanners(
                  gachaSec.banners,
                  index: ref.watch(hoyowikiIndexProvider),
                ),
                nativeAd: gachaAd,
              ),
              SliverList.list(
                children: [
                  const SizedBox(height: AppSpacing.xxxl),
                  Divider(
                    color: Theme.of(context).gacha.borderEmphasis,
                    height: 1,
                    thickness: 1,
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                ],
              ),
              _OverviewSection(
                adPlacement: NativeAdPlacement.overviewOdes,
                title: l.pageOverviewOdesSection,
                types: odesSec.types,
                banners: odesSec.banners,
                stats: odesSec.stats,
                bannerColors: bannerColors,
                statCards: odesStatCards,
                emptyTitle: l.emptyNoOdesRecords,
                timeline: odesSec.timeline,
                timelineNowPulls: odesSec.timelineNowPulls,
                timelineRank: odesSec.timelineRank,
                nativeAd: odesAd,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 產生並分享總覽統計截圖。
  Future<void> _generateOverviewShare(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    BannerStorage activeData,
  ) async {
    final appVersion = ref.read(appVersionProvider);
    await generateAndShareImage(
      context: context,
      l: l,
      suggestedName: 'genshin_gacha_share_overview_${fileTimestamp()}.png',
      recordsForPreload: activeData.banners.values.expand((records) => records),
      buildCard: (icon, options) => ShareCard.overview(
        l: l,
        appVersion: appVersion,
        appIcon: icon,
        options: options,
        uid: activeData.uid,
        updatedAt: activeData.lastUpdated.toLocal(),
        banners: activeData.banners,
        index: ref.read(hoyowikiIndexProvider),
      ),
    );
  }
}

/// 總覽頁中 gacha 或 odes 的單一段落，包含 stat 卡、圖表與 timeline；以 sliver 回傳，讓每個區塊按需建構。
class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.title,
    required this.types,
    required this.banners,
    required this.stats,
    required this.bannerColors,
    required this.statCards,
    required this.emptyTitle,
    required this.timeline,
    required this.timelineNowPulls,
    required this.timelineRank,
    this.fiveStarItems = const [],
    this.nativeAd,
    required this.adPlacement,
  });

  /// 段落標題文字。
  final String title;

  /// 此段落包含的 [GachaType] 清單。
  final List<GachaType> types;

  /// 各卡池的祈願記錄 map。
  final Map<String, List<GachaRecord>> banners;

  /// 此段落的聚合統計。
  final GachaStats stats;

  /// 各卡池顏色對照。
  final BannerColors bannerColors;

  /// 三張 stat 卡 widget（總抽、主稀有度、次稀有度）。
  final List<Widget> statCards;

  /// 無記錄時顯示的空狀態標題。
  final String emptyTitle;

  /// 跨卡池合併後的 timeline 條目。
  final List<TimelineEntry> timeline;

  /// 距離最後一次主稀有度的現有累積抽數。
  final int timelineNowPulls;

  /// timeline 目標稀有度。
  final int timelineRank;

  /// 此段的五星一覽清單；空清單時不顯示該區塊（頌願段一律空）。
  final List<FiveStarCollectionItem> fiveStarItems;

  /// 已載入、可顯示的原生廣告；null 時版面與沒有廣告時相同。
  final LoadedNative? nativeAd;

  /// 此段廣告的位置，決定廣告外框樣式。
  final NativeAdPlacement adPlacement;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final hasData = banners.values.any((r) => r.isNotEmpty);

    if (!hasData) {
      return SliverList.list(
        children: [
          InlineSectionTitle(icon: Icons.summarize_outlined, title: title),
          const SizedBox(height: AppSpacing.m),
          EmptyState.noRecords(context, title: emptyTitle, compact: true),
        ],
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverList.list(
          children: [
            InlineSectionTitle(icon: Icons.summarize_outlined, title: title),
            const SizedBox(height: AppSpacing.m),

            // Stat row: 三聯卡片（無保底）
            WidthLayoutBuilder(
              builder: (context, width) {
                final wide = width >= 1024;
                final mid = width < 1024;

                if (wide) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 6, child: statCards[0]),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(flex: 3, child: statCards[1]),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(flex: 3, child: statCards[2]),
                      ],
                    ),
                  );
                }
                if (mid) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      statCards[0],
                      const SizedBox(height: AppSpacing.m),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: statCards[1]),
                            const SizedBox(width: AppSpacing.m),
                            Expanded(child: statCards[2]),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < statCards.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.m),
                      statCards[i],
                    ],
                  ],
                );
              },
            ),

            const SizedBox(height: AppSpacing.m),

            // Pie row: 稀有度 + 物品類型
            WidthLayoutBuilder(
              builder: (context, width) {
                final wide = width >= 1024;
                final mid = width >= 800 && width < 1024;

                final layout = ChartCardLayout.of(context, width);
                final rarityCard = RarityChartCard(
                  stats: stats,
                  layout: layout,
                );
                final itemTypeCard = ItemTypeChartCard(
                  stats: stats,
                  layout: layout,
                );

                if (wide) {
                  // 對齊 Stat row（flex 6/3/3 + 兩個 m gap）：
                  // 第 1 卡寬 = (maxWidth - 24) / 2 = Stat row「總抽數」寬度。
                  final card1Width = (width - AppSpacing.m * 2) / 2;
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: card1Width, child: rarityCard),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(child: itemTypeCard),
                      ],
                    ),
                  );
                }
                if (mid || layout == ChartCardLayout.compactTitleBeside) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: rarityCard),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(child: itemTypeCard),
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    rarityCard,
                    const SizedBox(height: AppSpacing.m),
                    itemTypeCard,
                  ],
                );
              },
            ),

            const SizedBox(height: AppSpacing.m),
            if (nativeAd != null) ...[
              NativeAdBlock(ad: nativeAd!, placement: adPlacement),
              const SizedBox(height: AppSpacing.m),
            ],

            // 各卡池主稀有度件數
            ChartCard(
              title: l.bannerTopRarityCountTitle,
              icon: Icons.bar_chart,
              height: null,
              chart: BannerTopRarityBars(
                types: types,
                banners: banners,
                colors: bannerColors,
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            if (fiveStarItems.isNotEmpty) ...[
              InlineSectionTitle(
                icon: Icons.star_outline,
                title: l.rarityOverviewTitle(l.rarityStar(5)),
              ),
              const SizedBox(height: AppSpacing.s),
            ],
          ],
        ),
        // 五星一覽獨立成按列建構的 sliver：數十個圖示一次建好會在捲入的那一幀卡頓。
        if (fiveStarItems.isNotEmpty) ...[
          SliverFiveStarOverview(items: fiveStarItems),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        ],
        SliverList.list(
          children: [
            InlineSectionTitle(
              icon: Icons.timeline,
              title: l.timelineTopRarityTitle(
                l.rarityStar(timelineRank),
                timeline.length,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            TimelineVertical(
              entries: timeline,
              colors: bannerColors,
              targetRank: timelineRank,
              nowPulls: timelineNowPulls,
              isAcrossBanners: true,
              showLuckLegend: true,
            ),
          ],
        ),
      ],
    );
  }
}
