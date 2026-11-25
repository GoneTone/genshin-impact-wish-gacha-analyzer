import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/platform_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/record_merge.dart';

/// Logger 實例（第三方平台匯入）。
final _log = Logger('wish.import.platform');

/// `Information` 分頁 A1 的識別字串，用來判斷是不是 paimon.moe 匯出檔。
const _marker = 'Paimon.moe Wish History Export';

/// 卡池分頁名 → `gacha_type`（Character Event 的 `Part`＝`Wish 2` 另改成 400）。
const _sheetGachaTypes = {
  'Character Event': '301',
  'Weapon Event': '302',
  'Standard': '200',
  "Beginners' Wish": '100',
  'Chronicled Wish': '500',
};

/// 不含祈願記錄、直接略過的分頁。
const _ignoredSheets = {'Banner List', 'Information'};

/// `Time` 文字儲存格格式 `yyyy-MM-dd HH:mm:ss`。
final _timePattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$',
);

/// paimon.moe（paimon.moe）Wish History 的 Excel 匯出檔匯入器。
///
/// 檔案沒有 UID 也沒有官方 `id`：產出一個 UID 為空字串的帳號（由呼叫端以
/// [assignTargetUid] 套上），每筆記錄依分頁順序產生替代 `id`（[assignSubstituteIds]）。
class PaimonMoeImporter implements PlatformImporter {
  /// 建立 [PaimonMoeImporter]。
  const PaimonMoeImporter();

  /// 平台穩定識別鍵。
  @override
  String get id => 'paimon_moe';

  /// 平台顯示名。
  @override
  String displayName(AppLocalizations l) => 'paimon.moe';

  /// 平台清單列副標。
  @override
  String? subtitle(AppLocalizations l) => null;

  /// 平台清單列前置 icon。
  @override
  IconData get icon => Icons.table_chart_outlined;

  /// 可接受副檔名（paimon.moe 匯出為 .xlsx）。
  @override
  List<String> get fileExtensions => const ['xlsx'];

  /// 匯出檔沒有 UID，需要使用者指定帳號。
  @override
  bool get requiresTargetUid => true;

  /// 解析 paimon.moe 的 xlsx 匯出為 [AccountsBundle]；[resolver] 不使用（記錄
  /// 本身帶英文名稱與星級）。
  @override
  Future<AccountsBundle> parse(
    Uint8List bytes, {
    ItemResolver? resolver,
  }) async {
    final Map<String, Sheet> sheets;
    try {
      sheets = Excel.decodeBytes(bytes).tables;
    } catch (e, st) {
      _log.warning('paimon_moe import: not a readable xlsx file', e, st);
      throw const FormatException('Not a readable xlsx file');
    }

    final info = sheets['Information']?.rows;
    final marker = info == null || info.isEmpty || info.first.isEmpty
        ? null
        : _text(info.first.first?.value);
    if (marker != _marker) {
      _log.warning(
        'paimon_moe import: Information marker missing (foreign file) '
        'sheets=${sheets.keys.toList()}',
      );
      throw const ForeignBundleException();
    }

    final records = <GachaRecord>[];
    for (final MapEntry(key: name, value: sheet) in sheets.entries) {
      if (_ignoredSheets.contains(name)) continue;
      final gachaType = _sheetGachaTypes[name];
      if (gachaType == null) {
        _log.warning('paimon_moe import: unknown sheet sheet="$name"');
        throw FormatException('Unknown sheet: $name');
      }
      records.addAll(_parseSheet(name, gachaType, sheet.rows));
    }

    final List<GachaRecord> withIds;
    try {
      withIds = assignSubstituteIds(records);
    } on ArgumentError catch (e, st) {
      _log.warning(
        'paimon_moe import: more than 100 rows in one second',
        e,
        st,
      );
      throw const FormatException('More than 100 records in one second');
    }

    final banners = <String, List<GachaRecord>>{};
    for (final r in withIds) {
      (banners[bannerKeyFor(r.gachaType)] ??= []).add(r);
    }
    for (final list in banners.values) {
      list.sort(compareRecordsNewestFirst);
    }

    final counts = {for (final e in banners.entries) e.key: e.value.length};
    final times = [for (final r in withIds) r.time]..sort();
    final range = times.isEmpty ? 'none' : '${times.first}..${times.last}';
    _log.info(
      'paimon_moe import parsed: rows=${withIds.length} banners=$counts '
      'range=$range',
    );

    final now = DateTime.now().toUtc();
    return AccountsBundle(
      exportedAt: now,
      appVersion: '',
      lastActiveUid: null,
      accounts: [
        ExportedAccount(
          data: BannerStorage(uid: '', lastUpdated: now, banners: banners),
        ),
      ],
    );
  }

  /// 解析一個卡池分頁：第一列是標題列（以名稱定位欄位），其後每列一筆記錄，
  /// 全空白的列略過；回傳的記錄維持分頁順序，`id` 留空待 [assignSubstituteIds]。
  List<GachaRecord> _parseSheet(
    String sheet,
    String gachaType,
    List<List<Data?>> rows,
  ) {
    if (rows.isEmpty) return const [];
    final columns = <String, int>{
      for (final (i, cell) in rows.first.indexed)
        if (_text(cell?.value) case final name? when name.isNotEmpty) name: i,
    };
    final required = [
      'Type',
      'Name',
      'Time',
      '⭐',
      if (gachaType == '301') 'Part',
    ];
    final missing = required.where((c) => !columns.containsKey(c)).toList();
    if (missing.isNotEmpty) {
      _log.warning(
        'paimon_moe import: missing columns sheet="$sheet" columns=$missing',
      );
      throw FormatException('Sheet $sheet is missing columns: $missing');
    }

    /// 取 [row] 中標題為 [column] 的儲存格值。
    CellValue? cell(List<Data?> row, String column) {
      final i = columns[column]!;
      return i < row.length ? row[i]?.value : null;
    }

    final records = <GachaRecord>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((c) => (_text(c?.value) ?? '').isEmpty)) continue;

      /// 第 [i] 列（Excel 列號 i＋1）格式錯誤時記 log 並丟 [FormatException]。
      Never reject(String reason) {
        _log.warning(
          'paimon_moe import: rejected sheet="$sheet" row=${i + 1} $reason',
        );
        throw FormatException('Sheet $sheet row ${i + 1}: $reason');
      }

      final type = _text(cell(row, 'Type')) ?? '';
      final name = _text(cell(row, 'Name')) ?? '';
      if (type.isEmpty || name.isEmpty) reject('empty Type or Name');
      final rank = _rank(cell(row, '⭐'));
      if (rank == null) reject('rank not within 1..5');
      final time = _time(cell(row, 'Time'));
      if (time == null) reject('unparsable Time');
      final wish2 = gachaType == '301' && _text(cell(row, 'Part')) == 'Wish 2';

      records.add(
        GachaRecord(
          id: '',
          uid: '',
          gachaType: wish2 ? '400' : gachaType,
          name: name,
          itemType: type,
          rankType: rank,
          time: time,
          lang: 'en-us',
        ),
      );
    }
    return records;
  }

  /// 文字或數值儲存格轉成去頭尾空白的字串；空儲存格回 null。
  static String? _text(CellValue? v) => switch (v) {
    null => null,
    TextCellValue() => v.value.toString().trim(),
    IntCellValue() => '${v.value}',
    _ => v.toString().trim(),
  };

  /// 解析 `⭐` 儲存格為 1～5；不是整數或超出範圍回 null。
  static int? _rank(CellValue? v) {
    final rank = switch (v) {
      IntCellValue() => v.value,
      DoubleCellValue() when v.value == v.value.roundToDouble() =>
        v.value.toInt(),
      TextCellValue() => int.tryParse(v.value.toString().trim()),
      _ => null,
    };
    return rank != null && rank >= 1 && rank <= 5 ? rank : null;
  }

  /// 解析 `Time` 儲存格（文字 `yyyy-MM-dd HH:mm:ss` 或 Excel 日期時間值）為本地
  /// [DateTime]，不做時區換算；格式不符或日期不存在回 null。
  static DateTime? _time(CellValue? v) {
    switch (v) {
      case DateTimeCellValue():
        return DateTime(v.year, v.month, v.day, v.hour, v.minute, v.second);
      case TextCellValue():
        final m = _timePattern.firstMatch(v.value.toString().trim());
        if (m == null) return null;
        final [y, mo, d, h, mi, s] = [
          for (var g = 1; g <= 6; g++) int.parse(m.group(g)!),
        ];
        final t = DateTime(y, mo, d, h, mi, s);
        // DateTime 會把 13 月、25 時之類的值進位成合法日期，要擋下來。
        final valid =
            t.year == y &&
            t.month == mo &&
            t.day == d &&
            t.hour == h &&
            t.minute == mi &&
            t.second == s;
        return valid ? t : null;
      default:
        return null;
    }
  }
}
