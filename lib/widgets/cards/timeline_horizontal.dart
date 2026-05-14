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

const double _edgeFadeWidth = 32;
const Duration _scrollDuration = Duration(milliseconds: 240);
const Curve _scrollCurve = Curves.easeOutCubic;

enum _ScrollSide { left, right }

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
  State<TimelineHorizontal> createState() => _TimelineHorizontalState();
}

class _TimelineHorizontalState extends State<TimelineHorizontal> {
  late final ScrollController _controller;
  bool _hasLeft = false;
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

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final target = (_controller.offset + delta).clamp(0.0, pos.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: _scrollDuration,
      curve: _scrollCurve,
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
          l.timelineNoRecords,
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
              child: _EdgeFade(side: _ScrollSide.left),
            ),
          ),
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: _ArrowButton(
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
              child: _EdgeFade(side: _ScrollSide.right),
            ),
          ),
          Positioned(
            right: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: _ArrowButton(
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
          Tooltip(
            message: entry.name,
            waitDuration: const Duration(milliseconds: 300),
            child: Text(
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

class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.side});
  final _ScrollSide side;

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).gacha.surfaceCard;
    final isLeft = side == _ScrollSide.left;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [cardColor, cardColor.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.tokens,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final GachaTokens tokens;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Material(
            color: tokens.surfaceCard.withValues(alpha: 0.85),
            shape: CircleBorder(
              side: BorderSide(
                color: tokens.textMuted.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: 24,
                height: 24,
                child: Icon(icon, size: 16, color: tokens.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
