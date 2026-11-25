import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/record_merge.dart';

/// 官方 `id` 的起點（19 碼、首位非 0）。
const _officialBase = 1733000000000000000;

/// 建立一筆官方記錄；[n] 為相對 [_officialBase] 的流水號。
GachaRecord _off(
  int n,
  DateTime time, {
  String name = 'Cool Steel',
  String lang = 'en-us',
  String gachaType = '301',
  int rank = 3,
}) => GachaRecord(
  id: '${_officialBase + n}',
  uid: '100000001',
  gachaType: gachaType,
  name: name,
  itemType: 'Weapon',
  rankType: rank,
  time: time,
  lang: lang,
);

/// 建立一筆替代記錄；[seq] 為同一秒內的序號。
GachaRecord _sub(
  DateTime time,
  int seq, {
  String name = 'Cool Steel',
  String lang = 'en-us',
  String gachaType = '301',
  int rank = 3,
}) => GachaRecord(
  id: substituteId(time, seq),
  uid: '100000001',
  gachaType: gachaType,
  name: name,
  itemType: 'Weapon',
  rankType: rank,
  time: time,
  lang: lang,
);

/// 某一秒的十連官方記錄，流水號從 [firstN] 起連續 10 筆。
List<GachaRecord> _officialTen(int firstN, DateTime time, {String? lang}) => [
  for (var i = 0; i < 10; i++)
    _off(
      firstN + i,
      time,
      name: i == 9 ? 'Fischl' : 'Cool Steel',
      rank: i == 9 ? 4 : 3,
      lang: lang ?? 'en-us',
    ),
];

/// 某一秒的十連替代記錄，共 [count] 筆。
List<GachaRecord> _subTen(
  DateTime time, {
  int count = 10,
  String lang = 'zh-tw',
  String name = '冷刃',
}) => [
  for (var i = 0; i < count; i++)
    _sub(
      time,
      i,
      name: i == 9 ? '菲謝爾' : name,
      rank: i == 9 ? 4 : 3,
      lang: lang,
    ),
];

/// 取出記錄的 `id` 清單。
List<String> _ids(List<GachaRecord> records) =>
    records.map((r) => r.id).toList();

/// 以存檔 JSON 比較完整內容（[GachaRecord] 不定義 `==`）。
List<Map<String, dynamic>> _json(List<GachaRecord> records) =>
    records.map((r) => r.toStorageJson()).toList();

/// 舊版 `_mergeRecordsById` 的行為：依 id 聯集、同 id 保留本機並回填 lang／修正 400，依 id 降序。
List<GachaRecord> _oldMerge(
  List<GachaRecord> local,
  List<GachaRecord> incoming,
) {
  final byId = <String, GachaRecord>{for (final r in local) r.id: r};
  for (final r in incoming) {
    final existing = byId[r.id];
    if (existing == null) {
      byId[r.id] = r;
    } else if ((existing.lang.isEmpty && r.lang.isNotEmpty) ||
        (existing.gachaType == '301' && r.gachaType == '400')) {
      byId[r.id] = existing.copyWith(
        lang: existing.lang.isEmpty && r.lang.isNotEmpty ? r.lang : null,
        gachaType: existing.gachaType == '301' && r.gachaType == '400'
            ? '400'
            : null,
      );
    }
  }
  return byId.values.toList()..sort((a, b) => b.id.compareTo(a.id));
}

void main() {
  final t1 = DateTime(2025, 12, 1, 4, 6, 48);
  final t2 = DateTime(2025, 12, 2, 10, 0, 1);
  final t3 = DateTime(2025, 12, 3, 21, 30, 59);

  test('substituteId format', () {
    expect(
      substituteId(DateTime(2025, 12, 1, 4, 6, 48), 3),
      '0202512010406480300',
    );
    expect(substituteId(DateTime(2025, 12, 1, 4, 6, 48), 3).length, 19);
    expect(() => substituteId(DateTime(2025), 100), throwsArgumentError);
    expect(() => substituteId(DateTime(2025), -1), throwsArgumentError);
  });

  test('isOfficialId / isSubstituteId', () {
    expect(isOfficialId('1733000000000000000'), isTrue);
    expect(isOfficialId('0202512010406480300'), isFalse);
    expect(isOfficialId('173300000000000000'), isFalse);
    expect(isOfficialId(''), isFalse);
    expect(isOfficialId('abc'), isFalse);
    expect(isSubstituteId('0202512010406480300'), isTrue);
    expect(isSubstituteId('1733000000000000000'), isFalse);
  });

  test('official-only merge equals old id-union order', () {
    // 單抽、十連、400 與空 lang 混合，id 隨時間遞增。
    final history = <GachaRecord>[
      _off(0, DateTime(2025, 1, 1, 0, 0, 1)),
      ..._officialTen(1, DateTime(2025, 1, 2, 0, 0, 1)),
      _off(11, DateTime(2025, 1, 3, 0, 0, 1), gachaType: '400'),
      _off(12, DateTime(2025, 1, 3, 0, 0, 2), lang: ''),
      ..._officialTen(13, DateTime(2025, 1, 4, 0, 0, 1)),
      _off(23, DateTime(2025, 1, 5, 0, 0, 1)),
    ];
    final local = [
      for (final r in history.sublist(0, 18))
        r.id.endsWith('11') ? r.copyWith(gachaType: '301') : r,
    ].reversed.toList();
    final incoming = [
      for (final r in history.sublist(10))
        r.id.endsWith('12') ? r.copyWith(lang: 'en-us') : r,
    ].reversed.toList();

    for (final (a, b) in [(local, incoming), (incoming, local)]) {
      final merged = mergeBannerRecords(a, b);
      expect(_json(merged), _json(_oldMerge(a, b)));
      expect(merged.length, history.length);
    }
  });

  test('official at a second replaces substitute group', () {
    final official = _officialTen(0, t1);
    for (final subs in [_subTen(t1), _subTen(t1, count: 9)]) {
      expect(
        _ids(mergeBannerRecords(subs, official)),
        _ids(official.reversed.toList()),
      );
      expect(
        _ids(mergeBannerRecords(official, subs)),
        _ids(official.reversed.toList()),
      );
    }
  });

  test('substitute-only second takes larger group, never sum', () {
    final nine = _subTen(t1, count: 9);
    final ten = _subTen(t1, lang: 'en-us', name: 'Cool Steel');
    for (final merged in [
      mergeBannerRecords(nine, ten),
      mergeBannerRecords(ten, nine),
    ]) {
      expect(merged.length, 10);
      expect(merged.every((r) => r.lang == 'en-us'), isTrue);
    }
  });

  test(
    'equal-size substitute groups pick the same group regardless of order',
    () {
      final a = _subTen(t1);
      final b = _subTen(t1, lang: 'en-us', name: 'Cool Steel');
      expect(_ids(mergeBannerRecords(a, b)), _ids(mergeBannerRecords(b, a)));
      expect(_json(mergeBannerRecords(a, b)), _json(mergeBannerRecords(b, a)));
      expect(mergeBannerRecords(a, b).length, 10);
    },
  );

  test('equal tie-break key still picks one group regardless of order', () {
    final a = [_sub(t1, 0)];
    final b = [_sub(t1, 0, gachaType: '400')];
    expect(_json(mergeBannerRecords(a, b)), _json(mergeBannerRecords(b, a)));
  });

  test('merge is idempotent', () {
    final x = [..._officialTen(0, t2), ..._subTen(t1, count: 9)];
    final y = [..._subTen(t1, lang: 'en-us'), ..._subTen(t2), ..._subTen(t3)];
    final once = mergeBannerRecords(x, y);
    expect(_json(mergeBannerRecords(once, y)), _json(once));
    expect(_json(mergeBannerRecords(once, x)), _json(once));
  });

  test('all orders of three sources give the same result', () {
    final paimon = [
      ..._subTen(t1),
      ..._subTen(t2, count: 9),
      _sub(t3, 0, lang: 'zh-tw'),
    ];
    final uigf = [
      ..._subTen(t1, lang: 'en-us', name: 'Cool Steel'),
      ..._subTen(t2, lang: 'en-us', name: 'Cool Steel'),
    ];
    final official = [..._officialTen(0, t2), _off(10, t3)];
    final sources = [paimon, uigf, official];
    const perms = [
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0],
    ];
    final results = [
      for (final p in perms)
        _json(
          mergeBannerRecords(
            mergeBannerRecords(sources[p[0]], sources[p[1]]),
            sources[p[2]],
          ),
        ),
    ];
    for (final r in results) {
      expect(r, results.first);
    }
    // t1 取等量兩組之一（10），t2 與 t3 全為官方。
    expect(results.first.length, 21);
  });

  test('local official records are never removed', () {
    final local = [_off(5, t2), _off(0, t1)];
    final incoming = [..._subTen(t1), ..._subTen(t2), _off(7, t3)];
    final merged = mergeBannerRecords(local, incoming);
    expect(_ids(merged), [_off(7, t3).id, _off(5, t2).id, _off(0, t1).id]);
    expect(
      _json(merged.where((r) => r.id != _off(7, t3).id).toList()),
      _json(local),
    );
  });

  test('gap filled by substitutes, surrounding official kept', () {
    final local = [_off(10, t3), _off(0, t1)];
    final incoming = [_sub(t3, 0), ..._subTen(t2), _sub(t1, 0)];
    final merged = mergeBannerRecords(local, incoming);
    expect(merged.length, 12);
    expect(merged.first.id, _off(10, t3).id);
    expect(merged.last.id, _off(0, t1).id);
    expect(merged.sublist(1, 11).every((r) => isSubstituteId(r.id)), isTrue);
  });

  test('ten-pull with repeated 3-star stays ten', () {
    final paimon = _subTen(t1);
    final uigf = _subTen(t1);
    expect(mergeBannerRecords(paimon, uigf).length, 10);
    expect(mergeBannerRecords(paimon, _officialTen(0, t1)).length, 10);
  });

  test('same substitute id with different names stays one record', () {
    final merged = mergeBannerRecords(
      [_sub(t1, 0, name: 'A')],
      [_sub(t1, 0, name: 'B')],
    );
    expect(merged.length, 1);
  });

  test('substitute newer than official sorts first', () {
    final merged = mergeBannerRecords([_off(0, t1)], [_sub(t2, 0)]);
    expect(_ids(merged), [substituteId(t2, 0), _off(0, t1).id]);
  });

  test('assignSubstituteIds numbers per banner key and second', () {
    GachaRecord raw(DateTime t, String gachaType, {String id = ''}) =>
        _sub(t, 0, gachaType: gachaType).copyWith(id: id);
    final out = assignSubstituteIds([
      raw(t1, '301'),
      raw(t1, '301'),
      raw(t1, '302'),
      raw(t1, '301'),
      raw(t1, '400'),
      raw(t2, '301'),
      raw(t1, '301', id: _off(0, t1).id),
    ]);
    expect(_ids(out), [
      substituteId(t1, 0),
      substituteId(t1, 1),
      substituteId(t1, 0),
      substituteId(t1, 2),
      substituteId(t1, 3),
      substituteId(t2, 0),
      _off(0, t1).id,
    ]);
    expect(out[4].gachaType, '400');
  });
}
