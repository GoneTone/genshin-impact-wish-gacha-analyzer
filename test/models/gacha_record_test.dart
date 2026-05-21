import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';

void main() {
  group('GachaRecord.fromApiJson', () {
    test('解析典型卡池 zh-tw API 回傳', () {
      final json = {
        'uid': '801057625',
        'gacha_type': '200',
        'item_id': '',
        'count': '1',
        'time': '2025-09-23 21:27:37',
        'name': '討龍英傑譚',
        'lang': 'zh-tw',
        'item_type': '武器',
        'rank_type': '3',
        'id': '1758632760000221425',
      };
      final record = GachaRecord.fromApiJson(json, gachaType: '200');
      expect(record.id, '1758632760000221425');
      expect(record.uid, '801057625');
      expect(record.gachaType, '200');
      expect(record.name, '討龍英傑譚');
      expect(record.itemType, '武器');
      expect(record.rankType, 3);
      expect(record.lang, 'zh-tw');
      expect(record.time, DateTime(2025, 9, 23, 21, 27, 37));
    });

    test('解析頌願 API 回傳：item_name → name，op_gacha_type 忽略改用查詢值', () {
      // 真實 getBeyondGachaLog 回傳 schema：item_name / op_gacha_type / 無 lang
      final json = {
        'id': '1761240000000038925',
        'region': 'os_asia',
        'uid': '801057625',
        'schedule_id': '20',
        'item_type': '裝扮套裝',
        'item_id': '265044',
        'item_name': '女性裝扮·「燭影狂歡夜」',
        'rank_type': '5',
        'is_up': '0',
        'time': '2025-10-24 01:51:25',
        'op_gacha_type': '20021',
      };
      final record = GachaRecord.fromApiJson(json, gachaType: '2000');
      expect(record.id, '1761240000000038925');
      expect(record.uid, '801057625');
      // 用查詢的 banner 級 gacha_type，不取 op_gacha_type
      expect(record.gachaType, '2000');
      expect(record.name, '女性裝扮·「燭影狂歡夜」');
      expect(record.itemType, '裝扮套裝');
      expect(record.rankType, 5);
      // 頌願沒有 lang 欄位，預期空字串
      expect(record.lang, '');
      expect(record.time, DateTime(2025, 10, 24, 1, 51, 25));
    });
  });

  group('GachaRecord JSON 持久化序列化', () {
    test('toStorageJson / fromStorageJson roundtrip', () {
      final original = GachaRecord(
        id: '1758632760000221425',
        uid: '801057625',
        gachaType: '200',
        name: '討龍英傑譚',
        itemType: '武器',
        rankType: 3,
        time: DateTime(2025, 9, 23, 21, 27, 37),
        lang: 'zh-tw',
      );
      final json = original.toStorageJson();
      // storage 用 snake_case 對齊 API
      expect(json['gacha_type'], '200');
      expect(json['item_type'], '武器');
      expect(json['rank_type'], 3);
      expect(json['time'], '2025-09-23 21:27:37');

      final restored = GachaRecord.fromStorageJson(json);
      expect(restored.id, original.id);
      expect(restored.itemType, original.itemType);
      expect(restored.time, original.time);
    });
  });

  group('BannerStorage roundtrip', () {
    test('serialize/deserialize 保留 5 個 banner key', () {
      final record = GachaRecord(
        id: '1',
        uid: '801057625',
        gachaType: '301',
        name: '雷電將軍',
        itemType: '角色',
        rankType: 5,
        time: DateTime(2025, 9, 23, 21, 27, 37),
        lang: 'zh-tw',
      );
      final original = BannerStorage(
        uid: '801057625',
        lastUpdated: DateTime.utc(2026, 5, 9, 3, 30),
        banners: {
          '301': [record],
          '302': [],
          '500': [],
          '200': [],
          '100': [],
        },
      );

      final json = original.toJson();
      expect(json['uid'], '801057625');
      expect(json['last_updated'], '2026-05-09T03:30:00.000Z');
      expect((json['banners'] as Map)['301'], hasLength(1));

      final restored = BannerStorage.fromJson(json);
      expect(restored.uid, original.uid);
      expect(restored.lastUpdated, original.lastUpdated);
      expect(restored.banners['301']!.first.id, '1');
      expect(restored.banners['302'], isEmpty);
    });
  });
}
