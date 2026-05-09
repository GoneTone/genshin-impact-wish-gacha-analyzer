import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_import.dart';

void main() {
  test('合法 JSON → BannerStorage', () {
    const input = '''
{
  "uid": "123456789",
  "last_updated": "2025-04-01T00:00:00.000Z",
  "banners": {
    "301": [
      {
        "id": "1",
        "uid": "123456789",
        "gacha_type": "301",
        "name": "夜蘭",
        "item_type": "角色",
        "rank_type": 5,
        "time": "2025-04-01 14:23:00",
        "lang": "zh-tw"
      }
    ]
  }
}
''';
    final data = importJson(input);
    expect(data.uid, '123456789');
    expect(data.banners['301']?.length, 1);
    expect(data.banners['301']?.first.name, '夜蘭');
  });

  test('缺 uid → FormatException', () {
    expect(
      () => importJson('{"banners":{}}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('uid 不是 string → FormatException', () {
    expect(
      () => importJson('{"uid":123,"last_updated":"2025-01-01T00:00:00.000Z","banners":{}}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('非 JSON → FormatException', () {
    expect(
      () => importJson('not json'),
      throwsA(isA<FormatException>()),
    );
  });
}
