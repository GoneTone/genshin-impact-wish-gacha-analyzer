import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_node.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_palette.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/scroll/scroll_affordance.dart';

/// 每個時間軸欄的固定寬度。
const double _colWidth = 90;

/// 邊緣漸隱遮罩的寬度。
const double _edgeFadeWidth = 32;

/// 月份標籤帶高度。每欄頂部保留此高（首欄填標籤、其餘留白），底部以等高
/// spacer 對稱補回，使節點 y 不因標籤帶位移、仍對齊背景軸線。標籤靠上對齊，
/// 多出的高度成為標籤與下方名稱之間的間隔。
const double _monthBandHeight = 26;

/// 名稱上方物品圖示的邊長。
const double _iconSize = 32;

/// 圖示加上它與名稱的間距；有圖示的欄要在底部對稱補回這段高度，節點才會落在軸線上。
const double _iconBlockHeight = _iconSize + AppSpacing.xs;

/// 節點上方名稱（12）與下方日期（10）共用的固定行高：兩行等高，節點才會在欄的正中間；
/// 1.4 倍容得下中文字型，名稱是中文時行高也不會跟著變高。
const StrutStyle _labelStrut = StrutStyle(
  fontSize: 12,
  height: 1.4,
  forceStrutHeight: true,
);

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
class TimelineHorizontal extends StatefulWidget {
  /// 建立 [TimelineHorizontal]。
  const TimelineHorizontal({
    super.key,
    required this.entries,
    required this.targetRank,
    this.nowPulls,
  });

  /// 要顯示的時間軸條目（由新到舊排序）。
  final List<TimelineEntry> entries;

  /// 該卡池萃取的稀有度（5 或 4）。用於「暫無 N★ 紀錄」文案。
  final int targetRank;

  /// 傳入時在時間軸最左端加入「現在」欄，值為距上次目標稀有度的抽數。
  final int? nowPulls;

  @override
  State<TimelineHorizontal> createState() => _TimelineHorizontalState();
}

/// State for [TimelineHorizontal]; 管理橫向捲動控制器與邊緣箭頭可見性。
class _TimelineHorizontalState extends State<TimelineHorizontal>
    with AutomaticKeepAliveClientMixin {
  /// 放在按需建構的清單裡時，捲出畫面也保留橫向捲動位置。
  @override
  bool get wantKeepAlive => true;

  /// 橫向 [ListView] 的捲動控制器。
  late final ScrollController _controller;

  /// true 時顯示左側漸隱遮罩與箭頭。
  bool _hasLeft = false;

  /// true 時顯示右側漸隱遮罩與箭頭。
  bool _hasRight = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController()..addListener(_updateAffordance);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateAffordance());
  }

  @override
  void didUpdateWidget(covariant TimelineHorizontal old) {
    super.didUpdateWidget(old);
    if (old.entries != widget.entries || old.nowPulls != widget.nowPulls) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateAffordance());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 依捲動位置更新 [_hasLeft] / [_hasRight]，觸發箭頭顯示或隱藏。
  void _updateAffordance() {
    if (!mounted || !_controller.hasClients) return;
    final pos = _controller.position;
    final hasLeft = _controller.offset > 1;
    final hasRight = _controller.offset < pos.maxScrollExtent - 1;
    if (hasLeft != _hasLeft || hasRight != _hasRight) {
      setState(() {
        _hasLeft = hasLeft;
        _hasRight = hasRight;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;

    if (widget.entries.isEmpty && widget.nowPulls == null) {
      return Center(
        child: Text(
          l.timelineNoRecordsForRank(l.rarityStar(widget.targetRank)),
          style: theme.textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        ),
      );
    }

    // 每欄是否為其月份分組首欄（左→右 = 新→舊，某月最新一筆即該組起點）。
    final monthStart = <bool>[];
    int? prevYearMonth;
    for (final entry in widget.entries) {
      final ym = entry.time.year * 12 + entry.time.month;
      monthStart.add(prevYearMonth != ym);
      prevYearMonth = ym;
    }

    final nowOffset = widget.nowPulls != null ? 1 : 0;

    /// 第 [index] 欄（含最左的「現在」欄）。
    Widget columnAt(int index, {bool trailingSpacer = true}) =>
        index < nowOffset
        ? _NowColumn(nowPulls: widget.nowPulls!, tokens: tokens)
        : _EntryColumn(
            entry: widget.entries[index - nowOffset],
            targetRank: widget.targetRank,
            tokens: tokens,
            isMonthStart: monthStart[index - nowOffset],
            // 月份交界畫分隔線；最左欄（最新月份起點）不畫。
            showMonthDivider:
                monthStart[index - nowOffset] && index > nowOffset,
            trailingSpacer: trailingSpacer,
          );

    // 帶圖示的欄最高；沒有就取第一筆紀錄（月份標籤帶讓它仍比「現在」欄高）。
    final iconIndex = widget.entries.indexWhere(_EntryColumn.hasIcon);
    final tallestIndex = widget.entries.isEmpty
        ? 0
        : nowOffset + (iconIndex < 0 ? 0 : iconIndex);

    return LayoutBuilder(
      builder: (context, constraints) {
        final unbounded = !constraints.hasBoundedHeight;
        // 依內容定高時，欄底的對稱留白（只為讓節點落在置中軸線上）不算進時間軸高度：
        // 軸線、清單與箭頭往下多延伸這段高度，超出部分只有留白，被 Stack 裁掉。
        final overflow = unbounded && widget.entries.isNotEmpty
            ? _EntryColumn.trailingSpacerFor(
                widget.entries[tallestIndex - nowOffset],
              )
            : 0.0;
        return Stack(
          children: [
            // 高度不受限時，以不繪製、不含底部留白的最高欄撐出時間軸高度；
            // 清單本身是 Positioned.fill，無法自行決定高度。
            if (unbounded)
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: SizedBox(
                  width: double.infinity,
                  child: Center(
                    child: columnAt(tallestIndex, trailingSpacer: false),
                  ),
                ),
              ),
            // 背景軸線
            Positioned.fill(
              bottom: -overflow,
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
            // 內容層 (橫向 scroll)
            Positioned.fill(
              bottom: -overflow,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                // 按需建構：五星可能上百欄，整排常駐會讓外層每次捲動都重算所有欄。
                child: ListView.builder(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  itemExtent: _colWidth,
                  itemCount: widget.entries.length + nowOffset,
                  // 包 Center 等同原本 Row 的 crossAxisAlignment.center：
                  // 欄高依內容，月份分隔線長度不變。
                  // 拖曳游標只套在欄上：欄數少時右側空白拖不動，不該顯示左右箭頭游標。
                  itemBuilder: (context, index) => MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: Center(child: columnAt(index)),
                  ),
                ),
              ),
            ),
            // 左 fade + 左箭頭
            if (_hasLeft) ...[
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: _edgeFadeWidth,
                child: const IgnorePointer(
                  child: ScrollEdgeFade(side: ScrollSide.start),
                ),
              ),
              PositionedDirectional(
                start: 4,
                top: 0,
                bottom: -overflow,
                child: Center(
                  child: ScrollArrowButton(
                    icon: Icons.chevron_left,
                    tooltip: l.timelineScrollLeft,
                    tokens: tokens,
                    onPressed: () => _controller.animateBy(-_colWidth),
                  ),
                ),
              ),
            ],
            // 右 fade + 右箭頭
            if (_hasRight) ...[
              PositionedDirectional(
                end: 0,
                top: 0,
                bottom: 0,
                width: _edgeFadeWidth,
                child: const IgnorePointer(
                  child: ScrollEdgeFade(side: ScrollSide.end),
                ),
              ),
              PositionedDirectional(
                end: 4,
                top: 0,
                bottom: -overflow,
                child: Center(
                  child: ScrollArrowButton(
                    icon: Icons.chevron_right,
                    tooltip: l.timelineScrollRight,
                    tokens: tokens,
                    onPressed: () => _controller.animateBy(_colWidth),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 時間軸中單一高稀有度紀錄的直欄（名稱 / 節點 / 日期+抽數）。
class _EntryColumn extends StatelessWidget {
  const _EntryColumn({
    required this.entry,
    required this.targetRank,
    required this.tokens,
    required this.isMonthStart,
    required this.showMonthDivider,
    this.trailingSpacer = true,
  });

  /// [entry] 欄底部對稱留白的高度：補回頂部標籤帶（與圖示）高度，使節點落在欄的垂直中心。
  static double trailingSpacerFor(TimelineEntry entry) =>
      _monthBandHeight + (hasIcon(entry) ? _iconBlockHeight : 0);

  /// [entry] 欄是否在名稱上方畫物品圖示（頌願物品沒有圖示）。
  static bool hasIcon(TimelineEntry entry) =>
      entry.sourceRecord != null && showsGachaItemIcon(entry.sourceRecord!);

  /// 該欄對應的時間軸條目。
  final TimelineEntry entry;

  /// 該卡池萃取的稀有度（5 或 4），用於查保底門檻。
  final int targetRank;

  /// 主題 token。
  final GachaTokens tokens;

  /// 是否為其月份分組首欄；true 時頂部標籤帶顯示年/月。
  final bool isMonthStart;

  /// 是否在左側畫月份分隔線（月份交界、且非最左欄時為 true）。
  final bool showMonthDivider;

  /// 是否加上底部對稱留白；撐高度用的隱形欄不加，見 [trailingSpacerFor]。
  final bool trailingSpacer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final rank = entry.sourceRecord?.rankType ?? targetRank;
    final pity = pityThresholdFor(entry.gachaType, rank);
    final tier = luckTierFor(entry.pullsSincePrev, pity);
    final luck = luckColorFor(tier, tokens);
    final monthLabel = isMonthStart
        ? l.timelineMonthLabel(
            entry.time.year.toString(),
            entry.time.month.toString().padLeft(2, '0'),
          )
        : null;
    return Tooltip(
      message: entry.name,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 100),
      child: Container(
        width: _colWidth,
        decoration: showMonthDivider
            ? BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(color: tokens.borderEmphasis),
                ),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 月份標籤帶（首欄填年/月，其餘留白佔位）。
            SizedBox(
              height: _monthBandHeight,
              child: monthLabel == null
                  ? null
                  : Align(
                      alignment: Alignment.topCenter,
                      child: Text(
                        monthLabel,
                        maxLines: 1,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ),
            ),
            if (hasIcon(entry))
              GachaItemTapTarget(
                record: entry.sourceRecord!,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GachaItemIcon(record: entry.sourceRecord!, size: _iconSize),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      entry.name,
                      maxLines: 1,
                      strutStyle: _labelStrut,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: luck,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                entry.name,
                maxLines: 1,
                strutStyle: _labelStrut,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: luck,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            TimelineNode(color: luck, tokens: tokens),
            const SizedBox(height: AppSpacing.xs),
            Text.rich(
              TextSpan(
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 10,
                  fontFeatures: kTabularFigures,
                ),
                children: [
                  TextSpan(text: '${formatShortMonthDay(entry.time)} · '),
                  TextSpan(
                    text: l.timelineSinceLast(entry.pullsSincePrev),
                    style: TextStyle(color: luck),
                  ),
                ],
              ),
              maxLines: 1,
              strutStyle: _labelStrut,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            // 對稱補回標籤帶（與圖示）高度，使節點維持在原垂直中心、對齊軸線。
            if (trailingSpacer) SizedBox(height: trailingSpacerFor(entry)),
          ],
        ),
      ),
    );
  }
}

/// 時間軸最左端的「現在」欄（中空節點 + 距上次目標稀有度抽數）。
class _NowColumn extends StatelessWidget {
  const _NowColumn({required this.nowPulls, required this.tokens});

  /// 距上次目標稀有度的當前累積抽數。
  final int nowPulls;

  /// 主題 token。
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
            strutStyle: _labelStrut,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.accentPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TimelineNode(
            color: tokens.accentPrimary,
            tokens: tokens,
            hollow: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l.timelineNowPulls(nowPulls),
            maxLines: 1,
            strutStyle: _labelStrut,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontFeatures: kTabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}
