import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/record_merge.dart';

/// 匯入重疊檢查的 logger。
final _log = Logger('wish.import.platform');

/// 至少要有幾組重疊期間內的傳入組數才會提醒。
const _minGroups = 10;

/// 匯入資料與本機官方記錄在重疊期間幾乎對不上的警告（可能選錯帳號）。
class OverlapMismatch {
  /// 建立 [OverlapMismatch]。
  const OverlapMismatch({
    required this.uid,
    required this.from,
    required this.to,
    required this.groups,
    required this.matched,
  });

  /// 本機帳號 UID。
  final String uid;

  /// 重疊期間起點。
  final DateTime from;

  /// 重疊期間終點。
  final DateTime to;

  /// 重疊期間內的傳入組數（N）。
  final int groups;

  /// 能對到本機官方「卡池＋秒」且筆數相同的組數（M）。
  final int matched;
}

/// 以（卡池 key，牆鐘秒）為鍵統計 [records] 的筆數。
Map<(String, int), int> _groupCounts(Iterable<GachaRecord> records) {
  final counts = <(String, int), int>{};
  for (final r in records) {
    counts.update(
      (bannerKeyFor(r.gachaType), wallClockSecond(r.time)),
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }
  return counts;
}

/// 檢查 [incoming] 與 [local] 的官方記錄在重疊期間是否幾乎對不上（設計文件〈九〉）。
///
/// 重疊期間為兩邊時間範圍的交集；N 為期間內的傳入組數，M 為其中能對到本機官方
/// 同「卡池＋秒」且筆數相同者。`N >= 10 && M * 10 <= N` 才回傳 [OverlapMismatch]。
OverlapMismatch? checkImportOverlap({
  required BannerStorage local,
  required BannerStorage incoming,
}) {
  final localOfficial = local.allRecords
      .where((r) => isOfficialId(r.id))
      .toList(growable: false);
  final incomingAll = incoming.allRecords;
  if (localOfficial.isEmpty || incomingAll.isEmpty) return null;

  DateTime minOf(List<GachaRecord> rs) => rs
      .map((r) => r.time)
      .reduce((a, b) => wallClockSecond(a) <= wallClockSecond(b) ? a : b);
  DateTime maxOf(List<GachaRecord> rs) => rs
      .map((r) => r.time)
      .reduce((a, b) => wallClockSecond(a) >= wallClockSecond(b) ? a : b);

  final localMin = minOf(localOfficial);
  final incomingMin = minOf(incomingAll);
  final localMax = maxOf(localOfficial);
  final incomingMax = maxOf(incomingAll);
  final from = wallClockSecond(localMin) >= wallClockSecond(incomingMin)
      ? localMin
      : incomingMin;
  final to = wallClockSecond(localMax) <= wallClockSecond(incomingMax)
      ? localMax
      : incomingMax;
  final fromKey = wallClockSecond(from);
  final toKey = wallClockSecond(to);
  if (fromKey > toKey) return null;

  final localGroups = _groupCounts(localOfficial);
  var groups = 0;
  var matched = 0;
  for (final MapEntry(:key, :value) in _groupCounts(incomingAll).entries) {
    if (key.$2 < fromKey || key.$2 > toKey) continue;
    groups++;
    if (localGroups[key] == value) matched++;
  }

  final warn = groups >= _minGroups && matched * 10 <= groups;
  _log.info(
    'import overlap check uid=${sanitizeUid(local.uid)} '
    'groups=$groups matched=$matched warn=$warn',
  );
  return warn
      ? OverlapMismatch(
          uid: local.uid,
          from: from,
          to: to,
          groups: groups,
          matched: matched,
        )
      : null;
}
