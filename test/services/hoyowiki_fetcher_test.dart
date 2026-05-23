import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart'
    show ApiErrorException;
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';

http.Response _searchOk(List<Map<String, dynamic>> list) => http.Response(
  jsonEncode({
    'retcode': 0,
    'message': 'OK',
    'data': {'list': list},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _searchItem({
  required String name,
  required String id,
  required int subMenuId,
}) => {
  'name': name,
  'entry_page_id': id,
  'menu': {
    'sub_menus': [
      {'id': subMenuId, 'name': 'whatever'},
    ],
  },
};

http.Response _entryOk({required String iconUrl, required String headerUrl}) =>
    http.Response(
      jsonEncode({
        'retcode': 0,
        'message': 'OK',
        'data': {
          'page': {'icon_url': iconUrl, 'header_img_url': headerUrl},
        },
      }),
      200,
    );

void main() {
  group('HoyoWikiFetcher.searchEntryId', () {
    test('命中（sub_menu id=2）回 entry_page_id', () async {
      final mock = MockClient(
        (req) async => _searchOk([
          _searchItem(name: 'Hu Tao', id: '5125428', subMenuId: 2),
        ]),
      );
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final id = await fetcher.searchEntryId(
        name: 'Hu Tao',
        lang: 'en-us',
        client: mock,
      );
      expect(id, '5125428');
    });

    test('命中（sub_menu id=4）回 entry_page_id', () async {
      final mock = MockClient(
        (req) async =>
            _searchOk([_searchItem(name: 'Sword', id: '9001', subMenuId: 4)]),
      );
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final id = await fetcher.searchEntryId(
        name: 'Sword',
        lang: 'en-us',
        client: mock,
      );
      expect(id, '9001');
    });

    test('name 不完全 match → null', () async {
      final mock = MockClient(
        (req) async => _searchOk([
          _searchItem(name: 'Hu Tao (foo)', id: '5125428', subMenuId: 2),
        ]),
      );
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final id = await fetcher.searchEntryId(
        name: 'Hu Tao',
        lang: 'en-us',
        client: mock,
      );
      expect(id, isNull);
    });

    test('sub_menu id 非 2/4 → null', () async {
      final mock = MockClient(
        (req) async => _searchOk([
          _searchItem(name: 'Hu Tao', id: '5125428', subMenuId: 1),
        ]),
      );
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final id = await fetcher.searchEntryId(
        name: 'Hu Tao',
        lang: 'en-us',
        client: mock,
      );
      expect(id, isNull);
    });

    test('空 list → null', () async {
      final mock = MockClient((req) async => _searchOk(const []));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      expect(
        await fetcher.searchEntryId(name: 'X', lang: 'en-us', client: mock),
        isNull,
      );
    });

    test('多筆中找到第一筆 match', () async {
      final mock = MockClient(
        (req) async => _searchOk([
          _searchItem(name: 'Other', id: '111', subMenuId: 2),
          _searchItem(name: 'Hu Tao', id: '222', subMenuId: 2),
          _searchItem(name: 'Hu Tao', id: '333', subMenuId: 2),
        ]),
      );
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final id = await fetcher.searchEntryId(
        name: 'Hu Tao',
        lang: 'en-us',
        client: mock,
      );
      expect(id, '222');
    });

    test('retcode != 0 → throw ApiErrorException', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({'retcode': -1, 'message': 'fail', 'data': null}),
          200,
        ),
      );
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      await expectLater(
        () => fetcher.searchEntryId(name: 'X', lang: 'en-us', client: mock),
        throwsA(isA<ApiErrorException>()),
      );
    });

    test('Headers 正確帶入', () async {
      late http.BaseRequest captured;
      final mock = MockClient((req) async {
        captured = req;
        return _searchOk(const []);
      });
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      await fetcher.searchEntryId(name: 'Hu Tao', lang: 'zh-tw', client: mock);
      expect(captured.headers['Referer'], 'https://wiki.hoyolab.com/');
      expect(captured.headers['X-Rpc-Language'], 'zh-tw');
      expect(captured.headers['X-Rpc-Wiki_app'], 'genshin');
    });

    test('keyword 正確 URL-encode', () async {
      late Uri capturedUrl;
      final mock = MockClient((req) async {
        capturedUrl = req.url;
        return _searchOk(const []);
      });
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      await fetcher.searchEntryId(name: '胡桃', lang: 'zh-tw', client: mock);
      expect(capturedUrl.queryParameters['keyword'], '胡桃');
    });
  });

  group('HoyoWikiFetcher.fetchEntryPage', () {
    test('兩個 URL 都有 → 都回', () async {
      final mock = MockClient(
        (_) async => _entryOk(
          iconUrl: 'https://x/icon.png',
          headerUrl: 'https://x/header.png',
        ),
      );
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final entry = await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(entry.iconUrl, 'https://x/icon.png');
      expect(entry.headerImgUrl, 'https://x/header.png');
    });

    test('icon_url 為空字串 → 照回空', () async {
      final mock = MockClient(
        (_) async => _entryOk(iconUrl: '', headerUrl: 'https://x/header.png'),
      );
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final entry = await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(entry.iconUrl, '');
      expect(entry.headerImgUrl, 'https://x/header.png');
    });

    test('header_img_url 為空字串 → 照回空', () async {
      final mock = MockClient(
        (_) async => _entryOk(iconUrl: 'https://x/icon.png', headerUrl: ''),
      );
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final entry = await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(entry.iconUrl, 'https://x/icon.png');
      expect(entry.headerImgUrl, '');
    });

    test('兩個 URL 都空字串 → 都回空', () async {
      final mock = MockClient(
        (_) async => _entryOk(iconUrl: '', headerUrl: ''),
      );
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final entry = await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(entry.iconUrl, '');
      expect(entry.headerImgUrl, '');
    });

    test('retcode != 0 → throw ApiErrorException', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({'retcode': -1, 'message': 'nope', 'data': null}),
          200,
        ),
      );
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      await expectLater(
        () => fetcher.fetchEntryPage(id: '5125428', client: mock),
        throwsA(isA<ApiErrorException>()),
      );
    });

    test('URL 帶 entry_page_id query param', () async {
      late Uri capturedUrl;
      final mock = MockClient((req) async {
        capturedUrl = req.url;
        return _entryOk(iconUrl: '', headerUrl: '');
      });
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(capturedUrl.queryParameters['entry_page_id'], '5125428');
      expect(capturedUrl.host, 'sg-act-public-api-static.hoyolab.com');
    });
  });
}
