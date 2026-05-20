import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';

/// 左側月份標籤欄的固定寬度。
const double _monthColumnWidth = 80;

/// 節點內圓直徑。
const double _nodeSize = 14;

/// 節點外圍 halo（觸控熱區）直徑。
const double _haloSize = 22;

/// 軸線 left 偏移：月份欄右緣 + halo 半徑，使軸線穿過節點中心。
const double _railLeft = _monthColumnWidth + (_haloSize / 2);

/// 直向時間軸(視覺隱喻 B):
/// - 上 → 下 = 新 → 舊
/// - 軸線一條連續貫穿;月份標籤貼於軸線左外側(獨立左欄,不打斷軸線)
/// - `nowPulls != null` 時最頂端為「現在」row;`isAcrossBanners` 決定 i18n 文案
class TimelineVertical extends StatefulWidget {
  const TimelineVertical({
    super.key,
    required this.entries,
    required this.colors,
    required this.targetRank,
    this.title,
    this.footerNote,
    this.fillHeight = false,
    this.nowPulls,
    this.isAcrossBanners = false,
  });

  /// 要顯示的時間軸條目（由新到舊排序）。
  final List<TimelineEntry> entries;

  /// 各卡池節點的顏色映射。
  final BannerColors colors;

  /// 可選的卡內小標題。傳入時於卡片 container 內最上方顯示一個與卡片風格
  /// 一致的小標題（`labelSmall`，與 share `_PieBox` title 同樣式）；不傳
  /// （App 既有用法，如 overview 外部已有 `InlineSectionTitle`）則完全不
  /// 顯示，版面與行為與原本逐字相同。空資料分支與有資料分支皆適用。
  final String? title;

  /// 可選的卡內最底部說明文字。傳入時於卡片 container 內**最底部**（原內容
  /// 之後、仍在 border + padding 內）以低調說明文字顯示（`bodySmall` +
  /// `textMuted` + 置中，分享圖用來標示「另有較早紀錄未顯示」）；不傳（App
  /// 既有用法）則完全不顯示，版面與行為與原本逐字相同。空資料分支與有資料
  /// 分支皆適用。由呼叫端傳入「已格式化字串」，本元件只負責畫，不懂 l10n。
  final String? footerNote;

  /// 傳 `true` 時，卡片容器會撐滿父給的高度約束（內容仍置頂、底部多出的
  /// 空間為卡內留白）；分享圖用來讓本欄與相鄰欄（左側雙圓餅卡）等高。
  /// 預設 `false`：容器高度依內容（App 既有用法逐字不變、零回歸）。
  /// 前置條件：`fillHeight: true` 須由父層給定「有界（bounded）的高度約束」；
  /// 若父層高度無界，內部 `OverflowBox` 會讓內容無限延伸、`ClipRect` 形同無作用，
  /// 等高／裁切意圖將失效。
  final bool fillHeight;

  /// 主要顯示稀有度（5 或 4）。用於「暫無 N★ 紀錄」、「距上次 N★ X 抽」等文案。
  /// 跨卡池且 banner 各自主稀有度不同（頌願綜合）時，傳入「最具代表性的那個」
  /// （目前以 types.first.primaryPity.rank 為準）。
  final int targetRank;

  /// 傳入時在時間軸最頂端加入「現在」row，值為距上次目標稀有度的抽數。
  final int? nowPulls;

  /// true 表示跨卡池場景，影響「現在」row 的 i18n 文案。
  final bool isAcrossBanners;

  @override
  State<TimelineVertical> createState() => _TimelineVerticalState();
}

/// State for [TimelineVertical]; manages pagination via [_visibleCount].
class _TimelineVerticalState extends State<TimelineVertical> {
  /// 首次渲染顯示的最大條目數。
  static const int _initialPageSize = 10;

  /// 每次點「載入更多」增加的條目數。
  static const int _pageStep = 10;

  /// 當前顯示的最大條目數；點「載入更多」後遞增。
  int _visibleCount = _initialPageSize;

  /// Dataset-change detection: resets [_visibleCount] when **both** length and
  /// first-entry time differ. OR logic would be overly aggressive — appending
  /// new records changes length but not firstTime, and should not reset the
  /// user's expand state.
  @override
  void didUpdateWidget(TimelineVertical oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFirstTime = oldWidget.entries.isNotEmpty
        ? oldWidget.entries.first.time
        : null;
    final newFirstTime = widget.entries.isNotEmpty
        ? widget.entries.first.time
        : null;
    final lengthChanged = oldWidget.entries.length != widget.entries.length;
    final firstTimeChanged = oldFirstTime != newFirstTime;
    if (lengthChanged && firstTimeChanged) {
      // length + firstTime 同時不同 → 視為不同資料集，reset
      setState(() {
        _visibleCount = _initialPageSize;
      });
    } else {
      // 同資料集（或局部變動）→ 只做 clamp
      final clamped = _visibleCount.clamp(0, widget.entries.length);
      if (clamped != _visibleCount) {
        setState(() {
          _visibleCount = clamped;
        });
      }
    }
  }

  /// 將 [_visibleCount] 遞增一個 [_pageStep]，上限為資料集長度。
  void _loadMore() {
    setState(() {
      _visibleCount = (_visibleCount + _pageStep).clamp(
        0,
        widget.entries.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;

    final title = widget.title;
    final footerNote = widget.footerNote;
    final fillHeight = widget.fillHeight;
    Widget container(Widget child) {
      // title 與 footerNote 皆未傳（App 既有用法）→ 回傳原 child 本體，
      // 渲染樹與加入此參數前逐字等價、零回歸。
      final Widget body = (title == null && footerNote == null)
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  Text(title, style: theme.textTheme.labelSmall),
                  const SizedBox(height: AppSpacing.s),
                ],
                child,
                if (footerNote != null) ...[
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    footerNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            );
      // fillHeight=true：父為有界高度時，外框撐滿該高度；內部 body 以
      // ClipRect + OverflowBox 解開高約束（自然高、不 RenderFlex overflow）
      // 並置頂，超出邊框 padding 區的部分由 ClipRect 直接裁掉。內容少時
      // OverflowBox 區域 = 有界高，body 自然高較矮 → 下方為卡內留白。
      // fillHeight=false（App 既有用法）：child 維持原 body，渲染樹與加入
      // 此參數前逐字等價、零回歸。
      final Widget content = fillHeight
          ? ClipRect(
              child: OverflowBox(
                minHeight: 0,
                maxHeight: double.infinity,
                alignment: Alignment.topCenter,
                child: body,
              ),
            )
          : body;
      return Container(
        constraints: fillHeight
            ? const BoxConstraints(minHeight: double.infinity)
            : null,
        decoration: BoxDecoration(
          color: tokens.surfaceCard,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.l,
          horizontal: AppSpacing.l,
        ),
        child: content,
      );
    }

    final entries = widget.entries;
    final nowPulls = widget.nowPulls;
    final colors = widget.colors;
    final targetRank = widget.targetRank;
    final isAcrossBanners = widget.isAcrossBanners;

    if (entries.isEmpty && nowPulls == null) {
      return container(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(
            child: Text(
              l.timelineNoRecordsForRank(l.rarityStar(targetRank)),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    final effectiveCount = _visibleCount.clamp(0, entries.length);
    final visibleEntries = entries.take(effectiveCount).toList(growable: false);

    // 計算每個 visible entry 是否為月份分組首 row
    final monthFlag = <bool>[];
    int? prevYearMonth;
    for (final entry in visibleEntries) {
      final ym = entry.time.year * 12 + entry.time.month;
      monthFlag.add(prevYearMonth != ym);
      prevYearMonth = ym;
    }

    final remaining = entries.length - effectiveCount;

    return container(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              // 背景軸線
              Positioned(
                left: _railLeft,
                top: 0,
                bottom: 0,
                width: 2,
                child: Container(
                  color: tokens.textMuted.withValues(alpha: 0.3),
                ),
              ),
              // 前景:Column of rows
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (nowPulls != null)
                    _NowRow(
                      nowPulls: nowPulls,
                      targetRank: targetRank,
                      isAcrossBanners: isAcrossBanners,
                      tokens: tokens,
                    ),
                  for (var i = 0; i < visibleEntries.length; i++)
                    _EntryRow(
                      entry: visibleEntries[i],
                      showMonthTag: monthFlag[i],
                      colors: colors,
                      tokens: tokens,
                    ),
                ],
              ),
            ],
          ),
          if (remaining > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s),
              child: Center(
                child: TextButton.icon(
                  onPressed: _loadMore,
                  icon: const Icon(Icons.expand_more),
                  label: Text(l.timelineLoadMore(remaining)),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 時間軸中單一高稀有度紀錄的 row。
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.showMonthTag,
    required this.colors,
    required this.tokens,
  });

  /// 該 row 對應的時間軸條目。
  final TimelineEntry entry;

  /// true 時在月份欄顯示月份標籤（每個月的第一筆）。
  final bool showMonthTag;

  /// 各卡池節點的顏色映射。
  final BannerColors colors;

  /// 主題 token。
  final GachaTokens tokens;

  /// 將 [DateTime] 格式化為 `MM/dd` 字串。
  static String _formatShortDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}/${two(t.day)}';
  }

  /// 依 [gachaType] 查詢對應的在地化卡池名稱；查無時回傳 [gachaType] 本身。
  String _bannerName(String gachaType, AppLocalizations l) => gachaTypes
      .firstWhere(
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
      )
      .resolveName(l);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final accent = colors.colorFor(entry.gachaType);
    final year = entry.time.year.toString();
    final month = entry.time.month.toString().padLeft(2, '0');

    return Padding(
      padding: EdgeInsets.only(
        top: showMonthTag ? AppSpacing.m : 0,
        bottom: AppSpacing.m,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 月份左欄(固定寬度,僅在 showMonthTag 時填字)
          SizedBox(
            width: _monthColumnWidth,
            child: showMonthTag
                ? Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.s, top: 4),
                    child: Text(
                      l.timelineMonthLabel(year, month),
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // 節點圓 (tooltip 目標 = halo 大小，會顯示在節點正上方)
          Tooltip(
            message: entry.name,
            preferBelow: false,
            waitDuration: const Duration(milliseconds: 100),
            child: SizedBox(
              width: _haloSize,
              child: Center(
                child: _Node(color: accent, tokens: tokens),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          // 名稱 + meta (各自 tooltip，目標 = 文字本身寬度)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: entry.name,
                    preferBelow: false,
                    waitDuration: const Duration(milliseconds: 100),
                    child: Text(
                      entry.name,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Tooltip(
                    message: entry.name,
                    preferBelow: false,
                    waitDuration: const Duration(milliseconds: 100),
                    child: Text(
                      '${_formatShortDate(entry.time)} · ${_bannerName(entry.gachaType, l)} · ${l.timelineSinceLast(entry.pullsSincePrev)}',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 時間軸最頂端的「現在」row（中空節點 + 距上次目標稀有度抽數）。
class _NowRow extends StatelessWidget {
  const _NowRow({
    required this.nowPulls,
    required this.targetRank,
    required this.isAcrossBanners,
    required this.tokens,
  });

  /// 距上次目標稀有度的當前累積抽數。
  final int nowPulls;

  /// 目標稀有度，用於 i18n 文案中的星數標示。
  final int targetRank;

  /// true 時套用跨卡池的 i18n 文案。
  final bool isAcrossBanners;

  /// 主題 token。
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final meta = isAcrossBanners
        ? l.timelineNowSinceCrossPool(l.rarityStar(targetRank), nowPulls)
        : l.timelineNowSinceLast(l.rarityStar(targetRank), nowPulls);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: _monthColumnWidth),
          SizedBox(
            width: _haloSize,
            child: Center(
              child: _Node(
                color: tokens.accentPrimary,
                tokens: tokens,
                hollow: true,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.timelineNowLabel,
                    style: TextStyle(
                      color: tokens.accentPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
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
