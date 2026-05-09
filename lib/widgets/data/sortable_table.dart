import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/pager.dart';

class SortableTable extends StatefulWidget {
  const SortableTable({super.key, required this.records});

  /// 已 filter / sort 完的 records；元件本身不做篩選排序。
  final List<WishRecord> records;

  @override
  State<SortableTable> createState() => _SortableTableState();
}

class _SortableTableState extends State<SortableTable> {
  static const _pageSize = 20;
  int _page = 0;

  @override
  void didUpdateWidget(SortableTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records.length != widget.records.length) {
      _page = 0;
    }
  }

  int get _totalPages =>
      (widget.records.length / _pageSize).ceil().clamp(1, 99999);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    if (widget.records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Center(
          child: Text(
            l.emptyNoFiltered,
            style: TextStyle(color: tokens.textMuted),
          ),
        ),
      );
    }

    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.records.length);
    final slice = widget.records.sublist(start, end);

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
              _Header(theme: theme, tokens: tokens, l: l),
              for (var i = 0; i < slice.length; i++)
                _Row(
                  record: slice[i],
                  isStripe: i.isOdd,
                  theme: theme,
                  tokens: tokens,
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

class _Header extends StatelessWidget {
  const _Header({required this.theme, required this.tokens, required this.l});
  final ThemeData theme;
  final GachaTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final style = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: tokens.textSecondary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.m, horizontal: AppSpacing.l),
      color: tokens.surfaceCardHigh,
      child: DefaultTextStyle.merge(
        style: style ?? const TextStyle(),
        child: Row(
          children: [
            Expanded(flex: 4, child: Text(l.tableTime)),
            Expanded(flex: 5, child: Text(l.tableName)),
            Expanded(flex: 2, child: Text(l.tableKind)),
            Expanded(flex: 2, child: Text(l.tableRarity)),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.record,
    required this.isStripe,
    required this.theme,
    required this.tokens,
  });
  final WishRecord record;
  final bool isStripe;
  final ThemeData theme;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final accent = switch (record.rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => null,
    };
    final highlight = accent == null
        ? null
        : TextStyle(color: accent, fontWeight: FontWeight.bold);
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.m, horizontal: AppSpacing.l),
      color: isStripe ? tokens.surfaceCardHigh : null,
      child: Row(
        children: [
          if (accent != null)
            Container(width: 2, height: 28, color: accent)
          else
            const SizedBox(width: 2),
          const SizedBox(width: AppSpacing.s),
          Expanded(flex: 4, child: Text(_formatTime(record.time))),
          Expanded(flex: 5, child: Text(record.name, style: highlight)),
          Expanded(flex: 2, child: Text(record.itemType)),
          Expanded(
            flex: 2,
            child: accent != null
                ? _Pill(rank: record.rankType, color: accent)
                : Text('${record.rankType}★'),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.rank, required this.color});
  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          '$rank★',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
