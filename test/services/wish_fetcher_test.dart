import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_fetcher.dart';

const _baseUrl =
    'https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog'
    '?authkey=AAAA&lang=zh-tw&region=os_asia&gacha_type=301&page=1&size=20&end_id=0';

Map<String, dynamic> _record({required String id, required String type}) => {
  'uid': '801057625',
  'gacha_type': type,
  'item_id': '',
  'count': '1',
  'time': '2025-09-23 21:27:37',
  'name': 'x',
  'lang': 'zh-tw',
  'item_type': '武器',
  'rank_type': '3',
  'id': id,
};

http.Response _ok(List<Map<String, dynamic>> list) => http.Response(
  jsonEncode({
    'retcode': 0,
    'message': 'OK',
    'data': {'list': list, 'page': '1', 'size': '20', 'total': '0'},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _err(int retcode) => http.Response(
  jsonEncode({'retcode': retcode, 'message': 'fail', 'data': null}),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('WishFetcher.fetchPage', () {
    test('retcode=0 解析 list', () async {
      final mock = MockClient(
        (req) async => _ok([_record(id: '1', type: '301')]),
      );
      final fetcher = WishFetcher(rateLimit: Duration.zero);
      final page = await fetcher.fetchPage(
        GachaUrl.parse(
          _baseUrl,
        ).build(gachaType: '301', endId: '0', endpoint: GachaEndpoint.wish),
        mock,
      );
      expect(page.records, hasLength(1));
      expect(page.records.first.id, '1');
    });

    test('retcode=-101 throw AuthExpiredException', () async {
      final mock = MockClient((req) async => _err(-101));
      final fetcher = WishFetcher(rateLimit: Duration.zero);
      expect(
        () => fetcher.fetchPage(
          GachaUrl.parse(
            _baseUrl,
          ).build(gachaType: '301', endId: '0', endpoint: GachaEndpoint.wish),
          mock,
        ),
        throwsA(isA<AuthExpiredException>()),
      );
    });

    test('retcode=-110 退避後 throw RateLimitedException', () async {
      var hits = 0;
      final mock = MockClient((req) async {
        hits++;
        return _err(-110);
      });
      final fetcher = WishFetcher(
        rateLimit: Duration.zero,
        retryBackoff: Duration.zero,
      );
      await expectLater(
        () => fetcher.fetchPage(
          GachaUrl.parse(
            _baseUrl,
          ).build(gachaType: '301', endId: '0', endpoint: GachaEndpoint.wish),
          mock,
        ),
        throwsA(isA<RateLimitedException>()),
      );
      expect(hits, greaterThan(1));
    });
  });
}
