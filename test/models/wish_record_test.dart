import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

void main() {
  group('WishItemKind', () {
    test('zh-tw 角色 → character', () {
      expect(WishItemKind.fromItemType('角色'),
          WishItemKind.character);
    });

    test('zh-tw 武器 → weapon', () {
      expect(WishItemKind.fromItemType('武器'),
          WishItemKind.weapon);
    });

    test('en Character → character', () {
      expect(WishItemKind.fromItemType('Character'),
          WishItemKind.character);
    });

    test('未知字串 → unknown', () {
      expect(WishItemKind.fromItemType('???'),
          WishItemKind.unknown);
    });
  });

  group('WishRecord.fromApiJson', () {
    test('解析典型 zh-tw API 回傳', () {
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
      final record = WishRecord.fromApiJson(json);
      expect(record.id, '1758632760000221425');
      expect(record.uid, '801057625');
      expect(record.gachaType, '200');
      expect(record.name, '討龍英傑譚');
      expect(record.itemType, '武器');
      expect(record.kind, WishItemKind.weapon);
      expect(record.rankType, 3);
      expect(record.lang, 'zh-tw');
      expect(record.time, DateTime(2025, 9, 23, 21, 27, 37));
    });
  });

  group('WishRecord JSON 持久化序列化', () {
    test('toStorageJson / fromStorageJson roundtrip', () {
      final original = WishRecord(
        id: '1758632760000221425',
        uid: '801057625',
        gachaType: '200',
        name: '討龍英傑譚',
        itemType: '武器',
        kind: WishItemKind.weapon,
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

      final restored = WishRecord.fromStorageJson(json);
      expect(restored.id, original.id);
      expect(restored.kind, original.kind);
      expect(restored.time, original.time);
    });
  });

  group('BannerStorage roundtrip', () {
    test('serialize/deserialize 保留 5 個 banner key', () {
      final record = WishRecord(
        id: '1',
        uid: '801057625',
        gachaType: '301',
        name: '雷電將軍',
        itemType: '角色',
        kind: WishItemKind.character,
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
