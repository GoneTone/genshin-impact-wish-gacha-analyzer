import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_export.dart';

WishRecord _r(String id) => WishRecord(
  id: id,
  uid: '123',
  gachaType: '301',
  name: '夜蘭',
  itemType: '角色',
  kind: WishItemKind.character,
  rankType: 5,
  time: DateTime.utc(2025, 4, 1, 14, 23),
  lang: 'zh-tw',
);

void main() {
  late BannerStorage data;
  setUp(() {
    data = BannerStorage(
      uid: '123',
      lastUpdated: DateTime.utc(2025, 4, 1),
      banners: {
        '301': [_r('A')],
        '302': const [],
      },
    );
  });

  test('exportJson 與 BannerStorage.toJson 等價', () {
    final out = exportJson(data);
    expect(jsonDecode(out), data.toJson());
  });

  test('exportCsv 含 header 與一筆紀錄', () {
    final out = exportCsv(data);
    final lines = out.split('\n').where((l) => l.isNotEmpty).toList();
    expect(lines.length, 2);
    expect(lines[0], 'time,uid,gacha_type,name,item_type,rank_type,lang');
    expect(lines[1].contains('夜蘭'), isTrue);
    expect(lines[1].contains('123'), isTrue);
    expect(lines[1].contains('301'), isTrue);
  });

  test('exportCsv 處理含 comma 與 quote 的名字', () {
    final r = WishRecord(
      id: 'x',
      uid: '1',
      gachaType: '301',
      name: 'O,K"name',
      itemType: '角色',
      kind: WishItemKind.character,
      rankType: 4,
      time: DateTime.utc(2025, 1, 1),
      lang: 'zh-tw',
    );
    final s = BannerStorage(
      uid: '1',
      lastUpdated: DateTime.utc(2025, 1, 1),
      banners: {
        '301': [r],
      },
    );
    final out = exportCsv(s);
    expect(out.contains('"O,K""name"'), isTrue);
  });
}
