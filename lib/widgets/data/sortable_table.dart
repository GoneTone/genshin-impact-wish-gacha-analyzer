import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_row.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/pager.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';

/// 可排序的祈願記錄表格，含分頁功能。
class SortableTable extends StatefulWidget {
  /// 建立 [SortableTable]。
  const SortableTable({
    super.key,
    required this.rows,
    required this.sort,
    required this.mainRank,
    required this.onSortColumnTapped,
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

  @override
  State<SortableTable> createState() => _SortableTableState();
}

/// [SortableTable] 的 State：管理排序狀態與條紋背景。
class _SortableTableState extends State<SortableTable> {
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

  @override
  Widget build(BuildContext context) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Pager(
          page: _page,
          totalPages: _totalPages,
          onChanged: (p) => setState(() => _page = p),
        ),
      ],
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
      onTap: () => onTap(column),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: children,
        ),
      ),
    );
    return Expanded(
      flex: flex,
      child: tooltip == null
          ? Tooltip(message: tip, child: cell)
          : Tooltip(message: '${tooltip!} · $tip', child: cell),
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

  @override
  Widget build(BuildContext context) {
    final record = row.record;
    final accent = switch (record.rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => null,
    };
    final highlight = accent == null
        ? null
        : TextStyle(color: accent, fontWeight: FontWeight.bold);
    final mutedNum = TextStyle(
      color: tokens.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
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
            child: Row(
              children: [
                GachaItemIcon(record: record, size: 32),
                const SizedBox(width: 6),
                Expanded(
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
          Expanded(flex: 2, child: Text(record.itemType)),
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
              style: mutedNum,
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
