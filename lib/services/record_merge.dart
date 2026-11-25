import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// 卡池記錄合併的 logger。
final _log = Logger('wish.merge');

/// 官方 `id` 格式：19 碼數字、首位非 0。
final _officialIdPattern = RegExp(r'^[1-9]\d{18}$');

/// 替代 `id` 內的時間格式（14 碼）；固定 en_US，避免依介面語系換成非 ASCII 數字。
final _substituteTimeFormat = DateFormat('yyyyMMddHHmmss', 'en_US');

/// [id] 是否為官方 API 的記錄 `id`。
bool isOfficialId(String id) => _officialIdPattern.hasMatch(id);

/// [id] 是否為第三方匯入產生的替代 `id`（首位為 0）。
bool isSubstituteId(String id) => id.startsWith('0');

/// 產生替代 `id`：`"0"`＋`yyyyMMddHHmmss`＋兩碼同秒序號＋`"00"`，共 19 碼。
///
/// [seq] 超出 0～99 時丟 [ArgumentError]。
String substituteId(DateTime time, int seq) {
  if (seq < 0 || seq > 99) {
    throw ArgumentError.value(seq, 'seq', 'must be within 0..99');
  }
  return '0${_substituteTimeFormat.format(time)}'
      '${seq.toString().padLeft(2, '0')}00';
}

/// 為 `id` 不是官方格式的記錄產生替代 `id`，官方 `id` 原樣保留。
///
/// 序號是同一卡池 key（[bannerKeyFor]）、同一秒的記錄在 [recordsInSourceOrder]
/// 中的出現順序，所以同一份來源不論匯入幾次都得到相同的 `id`。
List<GachaRecord> assignSubstituteIds(List<GachaRecord> recordsInSourceOrder) {
  final nextSeq = <(String, DateTime), int>{};
  return [
    for (final r in recordsInSourceOrder)
      if (isOfficialId(r.id))
        r
      else
        r.copyWith(
          id: substituteId(
            r.time,
            nextSeq.update(
              (bannerKeyFor(r.gachaType), r.time),
              (n) => n + 1,
              ifAbsent: () => 0,
            ),
          ),
        ),
  ];
}

/// [time] 的牆鐘秒鍵（`yyyyMMddHHmmss` 數值）。
///
/// 與替代 `id` 用同一組欄位，且不受 `isUtc` 影響：同一個牆鐘秒不論是 UTC 或本地
/// `DateTime`，都視為同一秒。
int wallClockSecond(DateTime time) =>
    ((((time.year * 100 + time.month) * 100 + time.day) * 100 + time.hour) *
                100 +
            time.minute) *
        100 +
    time.second;

/// 卡池內的排序：`time` 由新到舊（依牆鐘秒），同一秒依 `id` 由大到小。
int compareRecordsNewestFirst(GachaRecord a, GachaRecord b) {
  final byTime = wallClockSecond(b.time).compareTo(wallClockSecond(a.time));
  return byTime != 0 ? byTime : b.id.compareTo(a.id);
}

/// 合併同一卡池 key 的本機 [local] 與傳入 [incoming] 記錄，依
/// [compareRecordsNewestFirst] 排序後回傳。
///
/// 以「同一秒」（牆鐘秒，見 [wallClockSecond]）為單位比對（設計文件〈五〉）：
/// 1. 這一秒有官方記錄 → 兩邊官方記錄依 `id` 聯集（同 `id` 保留本機，必要時回填
///    `lang`、把 `301` 修正為 `400`），這一秒的替代記錄全部捨棄。
/// 2. 兩邊都只有替代記錄 → 取筆數較多的一組，同筆數用與來源順序無關的規則挑一組。
/// 3. 只有一邊有這一秒 → 直接採用。
List<GachaRecord> mergeBannerRecords(
  List<GachaRecord> local,
  List<GachaRecord> incoming,
) {
  final officialById = <String, GachaRecord>{};
  final localSubs = <int, List<GachaRecord>>{};
  final incomingSubs = <int, List<GachaRecord>>{};
  for (final r in local) {
    if (isSubstituteId(r.id)) {
      (localSubs[wallClockSecond(r.time)] ??= []).add(r);
    } else {
      officialById[r.id] = r;
    }
  }
  for (final r in incoming) {
    if (isSubstituteId(r.id)) {
      (incomingSubs[wallClockSecond(r.time)] ??= []).add(r);
      continue;
    }
    final existing = officialById[r.id];
    if (existing == null) {
      officialById[r.id] = r;
      continue;
    }
    final backfillLang = existing.lang.isEmpty && r.lang.isNotEmpty;
    // 舊版把 API 回傳的 400 誤存成 301，這裡以傳入的 400 修正。
    final fix400 = existing.gachaType == '301' && r.gachaType == '400';
    if (backfillLang || fix400) {
      officialById[r.id] = existing.copyWith(
        lang: backfillLang ? r.lang : null,
        gachaType: fix400 ? '400' : null,
      );
    }
  }

  final officialCountByTime = <int, int>{};
  for (final r in officialById.values) {
    officialCountByTime.update(
      wallClockSecond(r.time),
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }

  final merged = [...officialById.values];
  var replacedSeconds = 0;
  var pickedSeconds = 0;
  for (final time in {...localSubs.keys, ...incomingSubs.keys}) {
    final l = localSubs[time] ?? const <GachaRecord>[];
    final i = incomingSubs[time] ?? const <GachaRecord>[];
    final officialCount = officialCountByTime[time];
    if (officialCount != null) {
      replacedSeconds++;
      for (final group in [l, i]) {
        if (group.isNotEmpty && group.length != officialCount) {
          _log.warning(
            'official and substitute counts differ '
            'banner=${bannerKeyFor(group.first.gachaType)} time=$time '
            'official=$officialCount substitute=${group.length} '
            'uid=${sanitizeUid(group.first.uid)}',
          );
        }
      }
    } else if (l.isEmpty || i.isEmpty) {
      merged.addAll(l.isEmpty ? i : l);
    } else {
      // 雲端同步收斂後兩邊多半完全相同，只算真的有差異的秒，避免每次同步都記一大串。
      if (l.length != i.length || _contentKey(l) != _contentKey(i)) {
        pickedSeconds++;
      }
      merged.addAll(_pickSubstituteGroup(l, i));
    }
  }
  merged.sort(compareRecordsNewestFirst);

  if (replacedSeconds > 0 || pickedSeconds > 0) {
    final sample = merged.first;
    _log.info(
      'merged substitutes banner=${bannerKeyFor(sample.gachaType)} '
      'uid=${sanitizeUid(sample.uid)} '
      'officialReplacedSeconds=$replacedSeconds '
      'bothSubstitutePickedSeconds=$pickedSeconds',
    );
  }
  return merged;
}

/// 同一秒兩邊都只有替代記錄時挑一組：筆數多者勝；同筆數依 [_tieBreakKey]、
/// 再依完整內容取字串較小者，結果與傳入順序無關。
List<GachaRecord> _pickSubstituteGroup(
  List<GachaRecord> a,
  List<GachaRecord> b,
) {
  if (a.length != b.length) return a.length > b.length ? a : b;
  var cmp = _tieBreakKey(a).compareTo(_tieBreakKey(b));
  // 例如 301 與 400 兩組其餘欄位相同時，鍵相同仍要分出勝負，否則會依順序取本機。
  if (cmp == 0) cmp = _contentKey(a).compareTo(_contentKey(b));
  return cmp <= 0 ? a : b;
}

/// 同筆數替代組的比較鍵：依 `id` 排序後串起 `lang`、`name`、`itemType`、`rankType`。
String _tieBreakKey(List<GachaRecord> group) => _sortedById(group)
    .map(
      (r) => '${r.lang}\u0000${r.name}\u0000${r.itemType}\u0000${r.rankType}',
    )
    .join('\u0001');

/// [_tieBreakKey] 相同時的最後比較鍵：依 `id` 排序後的完整存檔 JSON。
String _contentKey(List<GachaRecord> group) =>
    jsonEncode(_sortedById(group).map((r) => r.toStorageJson()).toList());

/// 回傳依 `id` 由小到大排序的 [group] 副本。
List<GachaRecord> _sortedById(List<GachaRecord> group) =>
    [...group]..sort((x, y) => x.id.compareTo(y.id));
