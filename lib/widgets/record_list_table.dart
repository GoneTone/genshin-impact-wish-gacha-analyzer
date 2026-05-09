// lib/widgets/record_list_table.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class RecordListTable extends StatefulWidget {
  const RecordListTable({super.key, required this.records});
  final List<WishRecord> records;

  @override
  State<RecordListTable> createState() => _RecordListTableState();
}

class _RecordListTableState extends State<RecordListTable> {
  static const _pageSize = 20;
  int _page = 0;

  @override
  void didUpdateWidget(RecordListTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records) {
      _page = 0;
    }
  }

  int get _totalPages =>
      (widget.records.length / _pageSize).ceil().clamp(1, 9999);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (widget.records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Center(child: Text(l.emptyNoRecords)),
      );
    }
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.records.length);
    final slice = widget.records.sublist(start, end);
    final theme = Theme.of(context);
    final tokens = theme.gacha;

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
              _HeaderRow(theme: theme, tokens: tokens, l: l),
              for (var i = 0; i < slice.length; i++)
                _DataRow(
                  record: slice[i],
                  isStripe: i.isOdd,
                  theme: theme,
                  tokens: tokens,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        _Pager(
          page: _page,
          totalPages: _totalPages,
          onChanged: (p) => setState(() => _page = p),
          l: l,
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.theme, required this.tokens, required this.l});
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
      padding:
          const EdgeInsets.symmetric(vertical: AppSpacing.m, horizontal: AppSpacing.l),
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

class _DataRow extends StatelessWidget {
  const _DataRow({
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
      padding:
          const EdgeInsets.symmetric(vertical: AppSpacing.m, horizontal: AppSpacing.l),
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
                ? _RarityPill(rank: record.rankType, color: accent)
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

class _RarityPill extends StatelessWidget {
  const _RarityPill({required this.rank, required this.color});
  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: 2),
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

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.totalPages,
    required this.onChanged,
    required this.l,
  });
  final int page;
  final int totalPages;
  final void Function(int) onChanged;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: page > 0 ? () => onChanged(page - 1) : null,
          child: Text(l.actionPrevPage),
        ),
        const SizedBox(width: AppSpacing.l),
        Text('${page + 1} / $totalPages'),
        const SizedBox(width: AppSpacing.l),
        TextButton(
          onPressed: page + 1 < totalPages ? () => onChanged(page + 1) : null,
          child: Text(l.actionNextPage),
        ),
      ],
    );
  }
}
