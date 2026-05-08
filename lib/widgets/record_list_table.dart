// lib/widgets/record_list_table.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

class RecordListTable extends StatefulWidget {
  const RecordListTable({super.key, required this.records});
  final List<WishRecord> records;

  @override
  State<RecordListTable> createState() => _RecordListTableState();
}

class _RecordListTableState extends State<RecordListTable> {
  static const _pageSize = 20;
  int _page = 0; // 0-based

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
    if (widget.records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('此卡池無紀錄')),
      );
    }
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.records.length);
    final slice = widget.records.sublist(start, end);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _HeaderRow(theme: theme),
              for (var i = 0; i < slice.length; i++)
                _DataRow(
                  record: slice[i],
                  isStripe: i.isOdd,
                  theme: theme,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Pager(
          page: _page,
          totalPages: _totalPages,
          onChanged: (p) => setState(() => _page = p),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final style = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: theme.colorScheme.surfaceContainerHigh,
      child: DefaultTextStyle.merge(
        style: style ?? const TextStyle(),
        child: const Row(
          children: [
            Expanded(flex: 4, child: Text('時間')),
            Expanded(flex: 5, child: Text('名稱')),
            Expanded(flex: 2, child: Text('類型')),
            Expanded(flex: 2, child: Text('稀有度')),
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
  });
  final WishRecord record;
  final bool isStripe;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final color = switch (record.rankType) {
      5 => GachaColors.fiveStar,
      4 => GachaColors.fourStar,
      _ => null,
    };
    final highlight = color == null
        ? null
        : TextStyle(color: color, fontWeight: FontWeight.bold);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: isStripe ? theme.colorScheme.surfaceContainerLow : null,
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(_formatTime(record.time))),
          Expanded(flex: 5, child: Text(record.name, style: highlight)),
          Expanded(flex: 2, child: Text(record.itemType)),
          Expanded(flex: 2, child: Text('${record.rankType}★', style: highlight)),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.totalPages,
    required this.onChanged,
  });
  final int page;
  final int totalPages;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: page > 0 ? () => onChanged(page - 1) : null,
          child: const Text('上一頁'),
        ),
        const SizedBox(width: 16),
        Text('${page + 1} / $totalPages'),
        const SizedBox(width: 16),
        TextButton(
          onPressed: page + 1 < totalPages ? () => onChanged(page + 1) : null,
          child: const Text('下一頁'),
        ),
      ],
    );
  }
}
