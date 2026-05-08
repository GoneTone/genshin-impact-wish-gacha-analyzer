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
  int _page = 0;  // 0-based

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('時間')),
              DataColumn(label: Text('名稱')),
              DataColumn(label: Text('類型')),
              DataColumn(label: Text('稀有度')),
            ],
            rows: slice.map((r) {
              final color = switch (r.rankType) {
                5 => GachaColors.fiveStar,
                4 => GachaColors.fourStar,
                _ => null,
              };
              final style = color == null
                  ? null
                  : TextStyle(color: color, fontWeight: FontWeight.bold);
              return DataRow(cells: [
                DataCell(Text(_formatTime(r.time))),
                DataCell(Text(r.name, style: style)),
                DataCell(Text(r.itemType)),
                DataCell(Text('${r.rankType}★', style: style)),
              ]);
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        _Pager(
          page: _page,
          totalPages: _totalPages,
          onChanged: (p) => setState(() => _page = p),
        ),
      ],
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
