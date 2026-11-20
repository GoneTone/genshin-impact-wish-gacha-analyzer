import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_row.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/five_star_collection.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/five_star_overview.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/pity_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_horizontal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/search_filter_bar.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/sortable_table.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/inline_section_title.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/last_updated_label.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/loading_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rank_palette.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_legend.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_action_button.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_image_helper.dart';

/// 單一 banner 的詳細統計頁，顯示保底進度、圖表、記錄列表。
class BannerPage extends ConsumerStatefulWidget {
  /// 建立 [BannerPage]，需指定目標卡池的 [gachaType]。
  const BannerPage({super.key, required this.gachaType});

  /// 對應 [GachaType.gachaType] 的卡池類型字串。
  final String gachaType;

  @override
  ConsumerState<BannerPage> createState() => _BannerPageState();
}

/// [BannerPage] 的 State：持有「記錄列表」標題的 key，換頁時捲回該標題。
class _BannerPageState extends ConsumerState<BannerPage> {
  /// 「記錄列表」標題的 key，換頁後捲回它。
  final _recordsTitleKey = GlobalKey();

  /// 對應卡池字串（[BannerPage.gachaType]）。
  String get gachaType => widget.gachaType;

  /// 記錄換頁後把「記錄列表」標題捲到可視區頂端。
  ///
  /// shortcut: 標題保活，但若使用者拖捲太快、從沒建構過它就沒有 context，此時不捲。
  void _scrollToRecordsTitle() {
    final titleContext = _recordsTitleKey.currentContext;
    if (titleContext == null) return;
    Scrollable.ensureVisible(
      titleContext,
      alignment: 0,
      duration: const Duration(milliseconds: 250),
    );
  }

  /// 依 [gachaType] 查找對應的 [GachaType]；找不到時回傳含預設值的佔位物件。
  GachaType _resolveType() => gachaTypes.firstWhere(
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
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final state = ref.watch(gachaRepositoryProvider);
    final activeData = state.activeData;

    if (state.isBootstrapping) {
      return const LoadingState();
    }
    if (activeData == null) {
      return noSyncPageBody(context);
    }
    final type = _resolveType();
    final records = activeData.banners[gachaType] ?? const [];

    if (records.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(
          isCompactLayout(context) ? AppSpacing.m : AppSpacing.l,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: type.resolveName(l),
              icon: _iconForGachaType(type),
              trailing: phoneLandscapeLastUpdated(context),
            ),
            // 填滿標題下方的高度再置中，直向、橫向與電腦視窗都落在中間（固定高度只會在那一段裡置中）。
            Expanded(child: EmptyState.noRecords(context)),
          ],
        ),
      );
    }

    final hoyowikiIndex = ref.watch(hoyowikiIndexProvider);
    final stats = computeGachaStats(records, index: hoyowikiIndex);
    final primary = type.primaryPity;
    final secondary = type.secondaryPity;
    final primaryPityData = computePity(
      records,
      threshold: primary.threshold,
      rank: primary.rank,
    );
    final secondaryPityData = secondary == null
        ? null
        : computePity(
            records,
            threshold: secondary.threshold,
            rank: secondary.rank,
          );
    final isEndedPool = type.gachaType == '100';

    final filterState = ref.watch(recordFilterProvider(gachaType));
    final allRows = buildRecordRows(
      records,
      index: hoyowikiIndex,
      mainRank: primary.rank,
    );
    final filtered = filterRecordRows(allRows, filterState.filter);
    final sorted = sortRecordRows(filtered, filterState.sort);
    final availableItemTypes =
        allRows
            .map((row) => row.itemTypeKey)
            .where((k) => k.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final fiveStarItems = buildFiveStarCollection(
      records,
      index: hoyowikiIndex,
    );

    final pagePadding = isCompactLayout(context) ? AppSpacing.m : AppSpacing.l;
    // 按需建構：畫面外的區塊不建構、不繪製、不產生語意，捲動時只重算看得到的部分。
    void cycleSort(SortColumn col) =>
        ref.read(recordFilterProvider(gachaType).notifier).cycleSort(col);
    return CustomScrollView(
      scrollCacheExtent: pageScrollCacheExtent(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.all(pagePadding),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverList.list(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: PageHeader(
                          title: type.resolveName(l),
                          icon: _iconForGachaType(type),
                          trailing: phoneLandscapeLastUpdated(context),
                        ),
                      ),
                      ShareActionButton(
                        enabled: records.isNotEmpty,
                        onGenerate: () => _generateBannerShare(
                          context,
                          ref,
                          l,
                          type,
                          activeData.uid,
                          activeData.lastUpdated,
                          records,
                        ),
                      ),
                    ],
                  ),

                  // Row 1: 三聯 Stat 卡（主 / 副保底用 PityCard，總抽數用 StatCard）
                  LayoutBuilder(
                    builder: (context, c) {
                      final wide =
                          c.maxWidth >= 1024 ||
                          phoneOrientationOf(context) ==
                              PhoneOrientation.landscape;
                      final mid = c.maxWidth < 1024;

                      final primaryCard = PityCard(
                        label: l.pityRank(l.rarityStar(primary.rank)),
                        rank: primary.rank,
                        pity: primaryPityData,
                        accent: accentForRank(primary.rank, tokens),
                        isEndedPool: isEndedPool,
                      );
                      final secondaryCard =
                          (secondary == null || secondaryPityData == null)
                          ? null
                          : PityCard(
                              label: l.pityRank(l.rarityStar(secondary.rank)),
                              rank: secondary.rank,
                              pity: secondaryPityData,
                              accent: accentForRank(secondary.rank, tokens),
                              isEndedPool: isEndedPool,
                            );
                      final totalCard = StatCard(
                        label: l.statsTotal,
                        value: '${stats.total}',
                        accent: tokens.accentPrimary,
                      );

                      if (wide) {
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 6, child: primaryCard),
                              if (secondaryCard != null) ...[
                                const SizedBox(width: AppSpacing.m),
                                Expanded(flex: 3, child: secondaryCard),
                              ],
                              const SizedBox(width: AppSpacing.m),
                              Expanded(flex: 3, child: totalCard),
                            ],
                          ),
                        );
                      }
                      if (mid) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            primaryCard,
                            const SizedBox(height: AppSpacing.m),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (secondaryCard != null) ...[
                                    Expanded(child: secondaryCard),
                                    const SizedBox(width: AppSpacing.m),
                                  ],
                                  Expanded(child: totalCard),
                                ],
                              ),
                            ),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          primaryCard,
                          const SizedBox(height: AppSpacing.m),
                          if (secondaryCard != null) ...[
                            secondaryCard,
                            const SizedBox(height: AppSpacing.m),
                          ],
                          totalCard,
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: AppSpacing.l),

                  // Row 2: 兩 Pie + Timeline
                  LayoutBuilder(
                    builder: (context, c) {
                      final wide = c.maxWidth >= 1024;
                      final layout = ChartCardLayout.of(context, c.maxWidth);
                      final landscape =
                          layout == ChartCardLayout.compactTitleBeside;
                      final col = wide
                          ? 3
                          : (c.maxWidth >= 800 || landscape ? 2 : 1);
                      final tileWidth = col == 1
                          ? c.maxWidth
                          : (c.maxWidth - AppSpacing.m * (col - 1)) / col;
                      final rarityCard = RarityChartCard(
                        stats: stats,
                        layout: layout,
                      );
                      final itemTypeCard = ItemTypeChartCard(
                        stats: stats,
                        layout: layout,
                      );
                      return Wrap(
                        spacing: AppSpacing.m,
                        runSpacing: AppSpacing.m,
                        children: [
                          if (col == 1) ...[
                            SizedBox(width: tileWidth, child: rarityCard),
                            SizedBox(width: tileWidth, child: itemTypeCard),
                          ] else
                            // 兩張圓餅卡同列時等高：精簡版高度跟著圖例列數走，不拉齊會一高一低。
                            SizedBox(
                              width: tileWidth * 2 + AppSpacing.m,
                              child: IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // 手機橫向的保底列是 6/3/3：第一張寬度要等於主保底卡，中間的縫才對齊（同總覽頁）。
                                    if (col == 2 && landscape)
                                      SizedBox(
                                        width:
                                            (c.maxWidth - AppSpacing.m * 2) / 2,
                                        child: rarityCard,
                                      )
                                    else
                                      Expanded(child: rarityCard),
                                    const SizedBox(width: AppSpacing.m),
                                    Expanded(child: itemTypeCard),
                                  ],
                                ),
                              ),
                            ),
                          // 除了電腦版三欄同列需與圓餅卡等高，時間軸都獨佔一列：撐滿寬、高度依內容。
                          SizedBox(
                            width: wide ? tileWidth : c.maxWidth,
                            child: ChartCard(
                              height: wide ? kChartCardHeight : null,
                              title: l.timelineTopRarityTitle(
                                l.rarityStar(primary.rank),
                                _countAtRank(stats, primary.rank),
                              ),
                              icon: Icons.timeline,
                              legend: const LuckLegend(),
                              chart: TimelineHorizontal(
                                entries: buildTimelineEntries(
                                  records,
                                  targetRank: primary.rank,
                                ),
                                targetRank: primary.rank,
                                nowPulls: pullsSinceLastRanked(
                                  records,
                                  rank: primary.rank,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
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
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xl),
                ),
              ],
              SliverList.list(
                children: [
                  _KeepAlive(
                    child: KeyedSubtree(
                      key: _recordsTitleKey,
                      child: InlineSectionTitle(
                        icon: Icons.table_chart_outlined,
                        title: l.pageBannerRecordList,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  // 加 key：上方「五星一覽」出現或消失會讓索引位移，清單才能依 key 找回原本的狀態。
                  // 清單子項只拿到寬度限制，高度變化不會重建這裡；卡片模式與下方表格用同一個寬度判斷。
                  LayoutBuilder(
                    key: const ValueKey('banner-search'),
                    builder: (context, c) => SearchFilterBar(
                      state: filterState,
                      availableItemTypes: availableItemTypes,
                      trailing: recordListUsesCards(context, c.maxWidth)
                          ? RecordSortButton(
                              sort: filterState.sort,
                              mainRank: primary.rank,
                              onTap: cycleSort,
                            )
                          : null,
                      onFilterChanged: (f) => ref
                          .read(recordFilterProvider(gachaType).notifier)
                          .setFilter(f),
                      onClear: () => ref
                          .read(recordFilterProvider(gachaType).notifier)
                          .clear(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  SortableTable(
                    key: const ValueKey('banner-table'),
                    rows: sorted,
                    sort: filterState.sort,
                    mainRank: primary.rank,
                    onSortColumnTapped: cycleSort,
                    // 卡片模式的排序按鈕放在上方篩選列。
                    showSortButton: false,
                    onPageChanged: (_) => _scrollToRecordsTitle(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 產生並分享此 banner 的統計截圖。
  Future<void> _generateBannerShare(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    GachaType type,
    String uid,
    DateTime updatedAt,
    List<GachaRecord> records,
  ) async {
    final appVersion = ref.read(appVersionProvider);
    await generateAndShareImage(
      context: context,
      l: l,
      suggestedName:
          'genshin_gacha_share_${type.gachaType}_${fileTimestamp()}.png',
      recordsForPreload: records,
      buildCard: (icon, options) => ShareCard.banner(
        l: l,
        appVersion: appVersion,
        appIcon: icon,
        options: options,
        uid: uid,
        updatedAt: updatedAt.toLocal(),
        title: type.resolveName(l),
        records: records,
        targetRank: type.primaryPity.rank,
        index: ref.read(hoyowikiIndexProvider),
      ),
    );
  }
}

/// 讓子樹在按需建構的清單裡捲出畫面後仍保留，使 [GlobalKey] 隨時取得得到 context。
class _KeepAlive extends StatefulWidget {
  /// 建立 [_KeepAlive]。
  const _KeepAlive({required this.child});

  /// 要保留的子樹。
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

/// [_KeepAlive] 的 State：永遠要求保活。
class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// 取 [GachaStats] 中對應稀有度的件數，作為 timeline 標題的 N。
int _countAtRank(GachaStats stats, int rank) => switch (rank) {
  5 => stats.fiveStarCount,
  4 => stats.fourStarCount,
  3 => stats.threeStarCount,
  2 => stats.twoStarCount,
  _ => 0,
};

/// 將 [GachaType] 對應至頁面標題圖示。
IconData _iconForGachaType(GachaType type) {
  return switch (type.nameKey) {
    'gachaTypeCharacter' => Icons.person_outline,
    'gachaTypeWeapon' => Icons.shield_outlined,
    'gachaTypeChronicled' => Icons.collections_bookmark_outlined,
    'gachaTypeStandard' => Icons.history,
    'gachaTypeBeginner' => Icons.school_outlined,
    'gachaTypeOdesEvent' => Icons.auto_awesome,
    'gachaTypeOdesStandard' => Icons.auto_awesome_motion,
    _ => Icons.casino_outlined,
  };
}
