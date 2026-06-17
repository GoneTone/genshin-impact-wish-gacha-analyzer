import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/scroll/scroll_affordance.dart';

/// 每個時間軸欄的固定寬度。
const double _colWidth = 90;

/// 節點內圓直徑。
const double _nodeSize = 14;

/// 節點外圍 halo（觸控熱區）直徑。
const double _haloSize = 22;

/// 邊緣漸隱遮罩的寬度。
const double _edgeFadeWidth = 32;

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
    required this.colors,
    required this.targetRank,
    this.nowPulls,
  });

  /// 要顯示的時間軸條目（由新到舊排序）。
  final List<TimelineEntry> entries;

  /// 各卡池節點的顏色映射。
  final BannerColors colors;

  /// 該卡池萃取的稀有度（5 或 4）。用於「暫無 N★ 紀錄」文案。
  final int targetRank;

  /// 傳入時在時間軸最左端加入「現在」欄，值為距上次目標稀有度的抽數。
  final int? nowPulls;

  @override
  State<TimelineHorizontal> createState() => _TimelineHorizontalState();
}

/// State for [TimelineHorizontal]; 管理橫向捲動控制器與邊緣箭頭可見性。
class _TimelineHorizontalState extends State<TimelineHorizontal> {
  /// 橫向 [SingleChildScrollView] 的捲動控制器。
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

  /// 相對捲動 [delta] px，夾在 0 與 maxScrollExtent 之間，使用動畫。
  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final target = (_controller.offset + delta).clamp(0.0, pos.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: kScrollAffordanceDuration,
      curve: kScrollAffordanceCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
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

    return Stack(
      children: [
        // 背景軸線
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
        // 內容層 (橫向 scroll)
        Positioned.fill(
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
              controller: _controller,
              scrollDirection: Axis.horizontal,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (widget.nowPulls != null)
                      _NowColumn(nowPulls: widget.nowPulls!, tokens: tokens),
                    for (final entry in widget.entries)
                      _EntryColumn(
                        entry: entry,
                        colors: widget.colors,
                        tokens: tokens,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 左 fade + 左箭頭
        if (_hasLeft) ...[
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _edgeFadeWidth,
            child: const IgnorePointer(
              child: ScrollEdgeFade(side: ScrollSide.left),
            ),
          ),
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: ScrollArrowButton(
                icon: Icons.chevron_left,
                tooltip: l.timelineScrollLeft,
                tokens: tokens,
                onPressed: () => _scrollBy(-_colWidth),
              ),
            ),
          ),
        ],
        // 右 fade + 右箭頭
        if (_hasRight) ...[
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: _edgeFadeWidth,
            child: const IgnorePointer(
              child: ScrollEdgeFade(side: ScrollSide.right),
            ),
          ),
          Positioned(
            right: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: ScrollArrowButton(
                icon: Icons.chevron_right,
                tooltip: l.timelineScrollRight,
                tokens: tokens,
                onPressed: () => _scrollBy(_colWidth),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 時間軸中單一高稀有度紀錄的直欄（名稱 / 節點 / 日期+抽數）。
class _EntryColumn extends StatelessWidget {
  const _EntryColumn({
    required this.entry,
    required this.colors,
    required this.tokens,
  });

  /// 該欄對應的時間軸條目。
  final TimelineEntry entry;

  /// 各卡池節點的顏色映射。
  final BannerColors colors;

  /// 主題 token。
  final GachaTokens tokens;

  /// 將 [DateTime] 格式化為 `MM/dd` 字串。
  static String _formatShortDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}/${two(t.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = colors.colorFor(entry.gachaType);
    final l = AppLocalizations.of(context)!;
    return Tooltip(
      message: entry.name,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 100),
      child: SizedBox(
        width: _colWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (entry.sourceRecord != null)
              GachaItemTapTarget(
                record: entry.sourceRecord!,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GachaItemIcon(record: entry.sourceRecord!, size: 32),
                    const SizedBox(height: AppSpacing.xs),
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
                  ],
                ),
              )
            else
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

/// 節點圓:外圍 halo + 內圓。`hollow=true` 時內圓填容器底色看起來只剩 border。
class _Node extends StatelessWidget {
  const _Node({required this.color, required this.tokens, this.hollow = false});

  /// 節點與 halo 的主色。
  final Color color;

  /// 主題 token，用於取得 [GachaTokens.surfaceCard]（hollow 填色）。
  final GachaTokens tokens;

  /// true 時內圓填 surfaceCard 使節點看起來只有邊框，用於「現在」節點。
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
