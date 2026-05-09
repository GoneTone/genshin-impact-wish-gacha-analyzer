import 'dart:convert';

import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

String exportJson(BannerStorage data) =>
    const JsonEncoder.withIndent('  ').convert(data.toJson());

String exportCsv(BannerStorage data) {
  final buf = StringBuffer();
  buf.writeln('time,uid,gacha_type,name,item_type,rank_type,lang');
  // 串成扁平 list、依時間 desc。
  final all = <WishRecord>[];
  for (final list in data.banners.values) {
    all.addAll(list);
  }
  all.sort((a, b) => b.time.compareTo(a.time));
  for (final r in all) {
    buf.writeln([
      _quote(_iso(r.time)),
      _quote(r.uid),
      _quote(r.gachaType),
      _quote(r.name),
      _quote(r.itemType),
      r.rankType.toString(),
      _quote(r.lang),
    ].join(','));
  }
  return buf.toString();
}

String _iso(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// 必要時用 RFC4180 規則 escape：含 ,/"/\n 就用 quote 包，內部 " 變成 ""。
String _quote(String v) {
  if (v.contains(',') || v.contains('"') || v.contains('\n')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}
