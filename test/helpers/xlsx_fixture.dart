import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';

/// paimon.moe 匯出檔 `Information` 分頁 A1 的識別字串。
const paimonMarker = 'Paimon.moe Wish History Export';

/// paimon.moe 卡池分頁的標題列（與實際匯出檔相同順序）。
const paimonHeader = <Object?>[
  'Type',
  'Name',
  'Time',
  '⭐',
  'Pity',
  '#Roll',
  'Group',
  'Banner',
  'Part',
];

/// 以 [sheets]（分頁名 → 各列儲存格值）產生 xlsx bytes。
///
/// 儲存格值可為 `String`、`int`、`double`、`DateTime`（寫成 Excel 日期時間值）
/// 或 `null`（空儲存格）。
Uint8List buildXlsx(Map<String, List<List<Object?>>> sheets) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet()!;
  for (final MapEntry(key: name, value: rows) in sheets.entries) {
    for (final row in rows) {
      excel.appendRow(name, [for (final v in row) _cell(v)]);
    }
  }
  if (!sheets.containsKey(defaultSheet)) {
    excel.setDefaultSheet(sheets.keys.first);
    excel.delete(defaultSheet);
  }
  return Uint8List.fromList(excel.encode()!);
}

/// 產生 paimon.moe 格式的 xlsx：[banners] 為卡池分頁名 → 資料列（不含標題列，
/// 標題列自動帶 [paimonHeader]），並附上 `Information` 分頁；[exportDate] 不為
/// null 時加上 `Export Date` 列。
Uint8List buildPaimonXlsx(
  Map<String, List<List<Object?>>> banners, {
  String marker = paimonMarker,
  Object? exportDate,
}) => buildXlsx({
  for (final MapEntry(key: name, value: rows) in banners.entries)
    name: [paimonHeader, ...rows],
  'Information': [
    [marker],
    ['Version', 4],
    if (exportDate != null) ['Export Date', exportDate],
  ],
});

/// paimon.moe 卡池分頁的一列資料，欄位順序同 [paimonHeader]。
List<Object?> paimonRow(
  String type,
  String name,
  Object time,
  int rank, {
  String part = '',
}) => [type, name, time, rank, 1, 1, 1, 'Some Banner', part];

/// 把 Dart 值轉成對應的 [CellValue]。
CellValue? _cell(Object? v) => switch (v) {
  null => null,
  String s => TextCellValue(s),
  int i => IntCellValue(i),
  double d => DoubleCellValue(d),
  DateTime t => DateTimeCellValue.fromDateTime(t),
  _ => throw ArgumentError.value(v, 'v', 'unsupported cell value'),
};
