import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_row.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/item_type_kind.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/pager.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_palette.dart';

/// 記錄列表是否用卡片列呈現：手機排版（含橫向）或可用寬度小於 [kCompactBreakpoint]。
bool recordListUsesCards(BuildContext context, double width) =>
    isCompactLayout(context) || width < kCompactBreakpoint;

/// [SortableTable.midListAd] 插在當頁第幾筆之後。
const kMidListAdAfter = 10;

/// 可排序的祈願記錄表格，含分頁功能。
class SortableTable extends StatefulWidget {
  /// 建立 [SortableTable]。
  const SortableTable({
    super.key,
    required this.rows,
    required this.sort,
    required this.mainRank,
    required this.onSortColumnTapped,
    this.showSortButton = true,
    this.onPageChanged,
    this.midListAd,
  });

  /// 已 filter / sort 完的 rows;元件本身不做篩選排序。
  final List<RecordRow> rows;

  /// 當前排序設定；`null` 表示未排序。
  final TableSort? sort;

  /// 該卡池的主稀有度 rank（卡池預設 5、常駐頌願 4），用於「保底內」欄
  /// 標題與 tooltip 中的 N★。
  final int mainRank;

  /// 使用者點擊欄位標題時的回呼。
  final ValueChanged<SortColumn> onSortColumnTapped;

  /// 卡片模式下是否在表格上方顯示排序按鈕；呼叫端把按鈕放到別處時傳 false。
  final bool showSortButton;

  /// 頁碼實際改變後的回呼，參數為新頁碼（0-based）；停留在同一頁不會觸發。
  final ValueChanged<int>? onPageChanged;

  /// 卡片模式且當頁超過 [kMidListAdAfter] 筆時，在同一個外框內插在第 [kMidListAdAfter] 筆之後的廣告列；`null` 時不插入。
  final Widget? midListAd;

  @override
  State<SortableTable> createState() => _SortableTableState();
}

/// [SortableTable] 的 State：管理排序狀態與條紋背景。
class _SortableTableState extends State<SortableTable>
    with AutomaticKeepAliveClientMixin {
  /// 放在按需建構的清單裡時，捲出畫面也保留本地狀態。
  @override
  bool get wantKeepAlive => true;

  /// 每頁顯示的記錄筆數。
  static const _pageSize = 20;

  /// 當前頁碼（0-based）。
  int _page = 0;

  @override
  void didUpdateWidget(SortableTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 僅在 rows 數量變化時重置頁碼（filter 變化會影響長度）。
    // sort 變化長度不變，刻意保留使用者當前頁。
    if (oldWidget.rows.length != widget.rows.length) {
      _page = 0;
    }
  }

  /// 依 rows 數量計算總頁數，最小為 1。
  int get _totalPages =>
      (widget.rows.length / _pageSize).ceil().clamp(1, 99999);

  /// 切換頁碼；頁碼沒變就什麼都不做，變了才通知 [SortableTable.onPageChanged]。
  void _setPage(int page) {
    if (page == _page) return;
    setState(() => _page = page);
    widget.onPageChanged?.call(page);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    if (widget.rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Center(
          child: Text(
            l.emptyNoFilterMatch,
            style: TextStyle(color: tokens.textMuted),
          ),
        ),
      );
    }

    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.rows.length);
    final slice = widget.rows.sublist(start, end);

    /// 卡片列外框。
    Widget frame(Widget child) => Container(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    /// slice 第 [from] 到 [to] 筆的卡片列；斑馬紋沿用整頁的奇偶。
    Widget cards(int from, int to) => Column(
      children: [
        for (var i = from; i < to; i++)
          _RecordCard(
            row: slice[i],
            isStripe: i.isOdd,
            mainRank: widget.mainRank,
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recordListUsesCards(context, constraints.maxWidth)) ...[
            if (widget.showSortButton) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: RecordSortButton(
                  sort: widget.sort,
                  mainRank: widget.mainRank,
                  onTap: widget.onSortColumnTapped,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
            ],
            if (widget.midListAd != null && slice.length > kMidListAdAfter)
              frame(
                Column(
                  children: [
                    cards(0, kMidListAdAfter),
                    Divider(height: 1, color: tokens.borderSubtle),
                    // 廣告上下緊鄰可點的記錄卡：留足內距並加分隔線，降低誤觸。
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.m,
                      ),
                      child: widget.midListAd!,
                    ),
                    Divider(height: 1, color: tokens.borderSubtle),
                    cards(kMidListAdAfter, slice.length),
                  ],
                ),
              )
            else
              frame(cards(0, slice.length)),
          ] else
            Container(
              decoration: BoxDecoration(
                color: tokens.surfaceCard,
                border: Border.all(color: tokens.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _Header(
                    theme: theme,
                    tokens: tokens,
                    l: l,
                    sort: widget.sort,
                    mainRank: widget.mainRank,
                    onTap: widget.onSortColumnTapped,
                  ),
                  for (var i = 0; i < slice.length; i++)
                    _Row(
                      row: slice[i],
                      isStripe: i.isOdd,
                      theme: theme,
                      tokens: tokens,
                      l: l,
                      mainRank: widget.mainRank,
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.m),
          Pager(
            page: _page,
            totalPages: _totalPages,
            totalItems: widget.rows.length,
            onChanged: _setPage,
          ),
        ],
      ),
    );
  }
}

/// 欄位的顯示名稱（和表格標題相同）。
String _columnLabel(SortColumn column, AppLocalizations l) => switch (column) {
  SortColumn.time => l.tableTime,
  SortColumn.name => l.tableName,
  SortColumn.kind => l.tableKind,
  SortColumn.rarity => l.tableRarity,
  SortColumn.totalIndex => l.tableTotalIndex,
  SortColumn.mainPity => l.tableMainPity,
};

/// 排序方向的箭頭。
String _arrow(SortDirection direction) =>
    direction == SortDirection.desc ? '↓' : '↑';

/// 5★／4★ 的強調色；其他稀有度為 null。
Color? _accentFor(GachaRecord record, GachaTokens tokens) =>
    switch (record.rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => null,
    };

/// 「保底內」抽數的歐非色：依距上次主稀有度的抽數相對該卡池保底門檻的比例分綠／黃／紅。
Color _pityColor(RecordRow row, int mainRank, GachaTokens tokens) =>
    luckColorFor(
      luckTierFor(
        row.mainPityIndex,
        pityThresholdFor(row.record.gachaType, mainRank),
      ),
      tokens,
    );

/// 卡片列的排序按鈕：顯示目前排序，點擊從底部滑出欄位選單（效果同點表格標題）。
class RecordSortButton extends StatelessWidget {
  /// 建立 [RecordSortButton]。
  const RecordSortButton({
    super.key,
    required this.sort,
    required this.mainRank,
    required this.onTap,
  });

  /// 目前排序；null 為預設順序。
  final TableSort? sort;

  /// 該卡池的主稀有度 rank。
  final int mainRank;

  /// 選了某一欄時的回呼（同點表格標題）。
  final ValueChanged<SortColumn> onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final current = sort;
    return OutlinedButton.icon(
      icon: const Icon(Icons.sort, size: 18),
      label: Text(
        current == null
            ? l.tableSortDefault
            : l.tableSortButton(
                '${_columnLabel(current.column, l)} ${_arrow(current.direction)}',
              ),
      ),
      onPressed: () => _showSheet(context, l),
    );
  }

  /// 底部選單：列出 6 個欄位，目前排序那欄標示方向並打勾。
  Future<void> _showSheet(BuildContext context, AppLocalizations l) async {
    final picked = await showModalBottomSheet<SortColumn>(
      context: context,
      // 頁面在外殼的內層導覽器裡；開在最上層才會蓋過標題列與底部狀態列。
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
              child: Text(
                l.tableSortSheetTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final column in SortColumn.values)
              ListTile(
                title: Text(_columnLabel(column, l)),
                trailing: sort?.column == column
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_arrow(sort!.direction)),
                          const SizedBox(width: AppSpacing.xs),
                          const Icon(Icons.check),
                        ],
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(column),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onTap(picked);
  }
}

/// 窄寬度時的一筆記錄：第一行圖示、名稱、星級；第二行時間、總抽序、保底內。整張可點開物品詳情。
class _RecordCard extends StatelessWidget {
  /// 建立 [_RecordCard]。
  const _RecordCard({
    required this.row,
    required this.isStripe,
    required this.mainRank,
  });

  /// 祈願記錄資料。
  final RecordRow row;

  /// 是否為斑馬紋的深色列。
  final bool isStripe;

  /// 該卡池主稀有度 rank。
  final int mainRank;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final record = row.record;
    final accent = _accentFor(record, tokens);
    final meta = theme.textTheme.bodySmall?.copyWith(
      color: tokens.textMuted,
      fontFeatures: kTabularFigures,
    );
    return GachaItemTapTarget(
      record: record,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        color: isStripe ? tokens.surfaceCardHigh : null,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.s,
          horizontal: AppSpacing.m,
        ),
        child: Row(
          children: [
            GachaItemIcon(record: record, size: 36),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          record.name,
                          style: accent == null
                              ? null
                              : TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.bold,
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      if (row.itemTypeKey.isNotEmpty) ...[
                        Text(itemTypeKeyLabel(row.itemTypeKey, l), style: meta),
                        const SizedBox(width: AppSpacing.s),
                      ],
                      if (accent != null)
                        _Pill(rank: record.rankType, color: accent, l: l)
                      else
                        Text(l.rarityStar(record.rankType)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // 單一段文字：放不下時整行以省略號結尾，不會因為字級放大而溢出。
                  // 卡片沒有表頭，保底說明掛在這一行（卡片點了會開詳情，所以用預設的長按觸發）。
                  Tooltip(
                    message: l.tableMainPityTooltip(l.rarityStar(mainRank)),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text:
                                '${formatAbsoluteDateTime(record.time)}'
                                ' (${relativeTime(record.time, l)})'
                                ' · #${row.totalIndex}'
                                ' · ${l.tableMainPity} ',
                          ),
                          TextSpan(
                            text: '${row.mainPityIndex}',
                            style: TextStyle(
                              color: _pityColor(row, mainRank, tokens),
                            ),
                          ),
                        ],
                      ),
                      style: meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 表格標題列，含各欄位的排序觸發按鈕。
class _Header extends StatelessWidget {
  /// 建立 [_Header]。
  const _Header({
    required this.theme,
    required this.tokens,
    required this.l,
    required this.sort,
    required this.mainRank,
    required this.onTap,
  });

  /// 主題資料。
  final ThemeData theme;

  /// 主題色彩 token。
  final GachaTokens tokens;

  /// 國際化字串。
  final AppLocalizations l;

  /// 當前排序設定；`null` 表示未排序。
  final TableSort? sort;

  /// 該卡池的主稀有度 rank，用於「保底內」欄標題的 N★ 顯示。
  final int mainRank;

  /// 使用者點擊欄位標題時的回呼。
  final ValueChanged<SortColumn> onTap;

  @override
  Widget build(BuildContext context) {
    final style = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: tokens.textSecondary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.m,
        horizontal: AppSpacing.l,
      ),
      color: tokens.surfaceCardHigh,
      child: DefaultTextStyle.merge(
        style: style ?? const TextStyle(),
        child: Row(
          children: [
            // 與 _Row 內部最左側 stripe 對齊
            const SizedBox(width: 2 + AppSpacing.s),
            _HeaderCell(
              flex: 4,
              label: l.tableTime,
              column: SortColumn.time,
              sort: sort,
              tokens: tokens,
              l: l,
              onTap: onTap,
            ),
            _HeaderCell(
              flex: 5,
              label: l.tableName,
              column: SortColumn.name,
              sort: sort,
              tokens: tokens,
              l: l,
              onTap: onTap,
            ),
            _HeaderCell(
              flex: 2,
              label: l.tableKind,
              column: SortColumn.kind,
              sort: sort,
              tokens: tokens,
              l: l,
              onTap: onTap,
            ),
            _HeaderCell(
              flex: 2,
              label: l.tableRarity,
              column: SortColumn.rarity,
              sort: sort,
              tokens: tokens,
              l: l,
              onTap: onTap,
            ),
            _HeaderCell(
              flex: 2,
              label: l.tableTotalIndex,
              column: SortColumn.totalIndex,
              sort: sort,
              tokens: tokens,
              l: l,
              onTap: onTap,
              alignEnd: true,
            ),
            _HeaderCell(
              flex: 2,
              label: l.tableMainPity,
              tooltip: l.tableMainPityTooltip(l.rarityStar(mainRank)),
              column: SortColumn.mainPity,
              sort: sort,
              tokens: tokens,
              l: l,
              onTap: onTap,
              alignEnd: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// 單一欄位的可排序標題儲存格。
class _HeaderCell extends StatelessWidget {
  /// 建立 [_HeaderCell]。
  const _HeaderCell({
    required this.flex,
    required this.label,
    required this.column,
    required this.sort,
    required this.tokens,
    required this.l,
    required this.onTap,
    this.tooltip,
    this.alignEnd = false,
  });

  /// [Expanded] 的 flex 值。
  final int flex;

  /// 欄位顯示名稱。
  final String label;

  /// 欄位額外 Tooltip 說明（可選）。
  final String? tooltip;

  /// 對應的排序欄位。
  final SortColumn column;

  /// 當前排序設定；`null` 表示未排序。
  final TableSort? sort;

  /// 主題色彩 token。
  final GachaTokens tokens;

  /// 國際化字串。
  final AppLocalizations l;

  /// 使用者點擊時的回呼。
  final ValueChanged<SortColumn> onTap;

  /// 是否靠右對齊（數字欄位）。
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final isActive = sort?.column == column;
    final IconData icon;
    final Color iconColor;
    final String tip;
    if (!isActive || sort == null) {
      icon = Icons.unfold_more;
      iconColor = tokens.textMuted;
      tip = l.sortHintClickToSort;
    } else if (sort!.direction == SortDirection.desc) {
      icon = Icons.arrow_downward;
      iconColor = tokens.textSecondary;
      tip = l.sortDirectionDesc;
    } else {
      icon = Icons.arrow_upward;
      iconColor = tokens.textSecondary;
      tip = l.sortDirectionAsc;
    }
    final children = <Widget>[
      Flexible(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      const SizedBox(width: 4),
      Icon(icon, size: 14, color: iconColor),
    ];
    final cell = InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: () => onTap(column),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
    return Expanded(
      flex: flex,
      child: Align(
        alignment: alignEnd
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: tooltip == null
            ? Tooltip(message: tip, child: cell)
            : Tooltip(message: '${tooltip!} · $tip', child: cell),
      ),
    );
  }
}

/// 單筆祈願記錄的資料列。
class _Row extends StatelessWidget {
  /// 建立 [_Row]。
  const _Row({
    required this.row,
    required this.isStripe,
    required this.theme,
    required this.tokens,
    required this.l,
    required this.mainRank,
  });

  /// 祈願記錄資料。
  final RecordRow row;

  /// 是否為斑馬紋的深色列。
  final bool isStripe;

  /// 主題資料。
  final ThemeData theme;

  /// 主題色彩 token。
  final GachaTokens tokens;

  /// 國際化字串。
  final AppLocalizations l;

  /// 該卡池主稀有度 rank，用於換算「保底內」欄歐非色。
  final int mainRank;

  @override
  Widget build(BuildContext context) {
    final record = row.record;
    final accent = _accentFor(record, tokens);
    final highlight = accent == null
        ? null
        : TextStyle(color: accent, fontWeight: FontWeight.bold);
    final mutedNum = TextStyle(
      color: tokens.textMuted,
      fontFeatures: kTabularFigures,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.m,
        horizontal: AppSpacing.l,
      ),
      color: isStripe ? tokens.surfaceCardHigh : null,
      child: Row(
        children: [
          if (accent != null)
            Container(width: 2, height: 28, color: accent)
          else
            const SizedBox(width: 2),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            flex: 4,
            child: Text(
              '${formatAbsoluteDateTime(record.time)}'
              ' (${relativeTime(record.time, l)})',
            ),
          ),
          Expanded(
            flex: 5,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: GachaItemTapTarget(
                record: record,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GachaItemIcon(record: record, size: 32),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        record.name,
                        style: highlight,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(flex: 2, child: Text(itemTypeKeyLabel(row.itemTypeKey, l))),
          Expanded(
            flex: 2,
            child: accent != null
                ? _Pill(rank: record.rankType, color: accent, l: l)
                : Text(l.rarityStar(record.rankType)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${row.totalIndex}',
              textAlign: TextAlign.end,
              style: mutedNum,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${row.mainPityIndex}',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: _pityColor(row, mainRank, tokens),
                fontFeatures: kTabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 稀有度標籤膠囊，用於 5★ / 4★ 的彩色底色顯示。
class _Pill extends StatelessWidget {
  /// 建立 [_Pill]。
  const _Pill({required this.rank, required this.color, required this.l});

  /// 稀有度 rank。
  final int rank;

  /// 膠囊主色。
  final Color color;

  /// 國際化字串。
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          l.rarityStar(rank),
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
