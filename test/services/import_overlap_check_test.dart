import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/import_overlap_check.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/record_merge.dart';

/// 一筆記錄：[official] 為 true 時用官方 id，否則用替代 id。
GachaRecord _rec(int n, DateTime time, {bool official = true}) => GachaRecord(
  id: official ? '${1733000000000000000 + n}' : substituteId(time, n % 100),
  uid: '100000001',
  gachaType: '301',
  name: 'x',
  itemType: 'Weapon',
  rankType: 3,
  time: time,
  lang: 'en-us',
);

/// 把 [records] 包成單一卡池的存檔。
BannerStorage _storage(List<GachaRecord> records) => BannerStorage(
  uid: '100000001',
  lastUpdated: DateTime.utc(2026),
  banners: {'301': records},
);

/// 第 [i] 組的時間（每組相隔一分鐘）。
DateTime _t(int i) => DateTime(2026, 1, 1, 10, i);

/// [count] 組、每組一筆的記錄，時間為 [startMinute] 起。
List<GachaRecord> _groups(int count, {int startMinute = 0, int idBase = 0}) => [
  for (var i = 0; i < count; i++) _rec(idBase + i, _t(startMinute + i)),
];

void main() {
  test('wrong account: no matches over 12 groups warns', () {
    final shifted = [
      for (var i = 0; i < 12; i++)
        _rec(2000 + i, _t(i).add(const Duration(seconds: 30))),
    ];
    final w = checkImportOverlap(
      local: _storage(_groups(13)),
      incoming: _storage(shifted),
    )!;
    expect((w.groups, w.matched), (12, 0));
  });

  test('matching account returns null', () {
    expect(
      checkImportOverlap(
        local: _storage(_groups(20)),
        incoming: _storage(_groups(20, idBase: 500)),
      ),
      isNull,
    );
  });

  test('fewer than 10 groups returns null', () {
    final shifted = [
      for (var i = 0; i < 9; i++)
        _rec(2000 + i, _t(i).add(const Duration(seconds: 30))),
    ];
    expect(
      checkImportOverlap(
        local: _storage(_groups(20)),
        incoming: _storage(shifted),
      ),
      isNull,
    );
  });

  test('boundary M=1,N=10 warns; M=2,N=19 does not', () {
    List<GachaRecord> mix(int n, int match) => [
      for (var i = 0; i < n; i++)
        _rec(
          3000 + i,
          i < match ? _t(i) : _t(i).add(const Duration(seconds: 30)),
        ),
    ];
    // 本機 30 組比傳入多，重疊期間就是整段傳入資料的時間範圍
    final local = _storage(_groups(30));
    final a = checkImportOverlap(local: local, incoming: _storage(mix(10, 1)));
    expect((a!.groups, a.matched), (10, 1));
    expect(
      checkImportOverlap(local: local, incoming: _storage(mix(19, 2))),
      isNull,
    );
  });

  test('different count in same second is not a match', () {
    final incoming = [
      for (var i = 0; i < 12; i++) ...[
        _rec(4000 + i * 2, _t(i)),
        _rec(4001 + i * 2, _t(i)),
      ],
    ];
    final r = checkImportOverlap(
      local: _storage(_groups(12)),
      incoming: _storage(incoming),
    );
    expect(r?.matched, 0);
  });

  test('substitute incoming matching local official groups returns null', () {
    final incoming = [
      for (var i = 0; i < 12; i++) _rec(i, _t(i), official: false),
    ];
    expect(
      checkImportOverlap(
        local: _storage(_groups(12)),
        incoming: _storage(incoming),
      ),
      isNull,
    );
  });

  test('substitute incoming from another account warns', () {
    final incoming = [
      for (var i = 0; i < 12; i++)
        _rec(i, _t(i).add(const Duration(seconds: 30)), official: false),
    ];
    final w = checkImportOverlap(
      local: _storage(_groups(13)),
      incoming: _storage(incoming),
    )!;
    expect((w.groups, w.matched), (12, 0));
  });

  test('no local official records returns null', () {
    final local = _storage([
      for (var i = 0; i < 12; i++) _rec(i, _t(i), official: false),
    ]);
    expect(
      checkImportOverlap(local: local, incoming: _storage(_groups(12))),
      isNull,
    );
  });

  test('disjoint time ranges return null', () {
    expect(
      checkImportOverlap(
        local: _storage(_groups(12)),
        incoming: _storage(_groups(12, startMinute: 100)),
      ),
      isNull,
    );
  });
}
