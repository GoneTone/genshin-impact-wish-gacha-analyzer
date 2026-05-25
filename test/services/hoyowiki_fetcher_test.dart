import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  required dynamic id, // String or int
  required dynamic subMenuId, // String or int
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
  group('HoYoWikiFetcher.searchEntryId', () {
    test('命中（sub_menu id=2）回 HoYoWikiSearchHit（id + menuId）', () async {
      final mock = MockClient(
        (req) async => _searchOk([
          _searchItem(name: 'Hu Tao', id: '5125428', subMenuId: 2),
        ]),
      );
      final fetcher = HoYoWikiFetcher();
      final hit = await fetcher.searchEntryId(
        name: 'Hu Tao',
        lang: 'en-us',
        client: mock,
      );
      expect(hit?.id, '5125428');
      expect(hit?.menuId, 2);
    });

    test('命中（sub_menu id=4）回 HoYoWikiSearchHit', () async {
      final mock = MockClient(
        (req) async =>
            _searchOk([_searchItem(name: 'Sword', id: '9001', subMenuId: 4)]),
      );
      final fetcher = HoYoWikiFetcher();
      final hit = await fetcher.searchEntryId(
        name: 'Sword',
        lang: 'en-us',
        client: mock,
      );
      expect(hit?.id, '9001');
      expect(hit?.menuId, 4);
    });

    test('name 不完全 match → null', () async {
      final mock = MockClient(
        (req) async => _searchOk([
          _searchItem(name: 'Hu Tao (foo)', id: '5125428', subMenuId: 2),
        ]),
      );
      final fetcher = HoYoWikiFetcher();
      final hit = await fetcher.searchEntryId(
        name: 'Hu Tao',
        lang: 'en-us',
        client: mock,
      );
      expect(hit, isNull);
    });

    test('sub_menu id 非 2/4 → null', () async {
      final mock = MockClient(
        (req) async => _searchOk([
          _searchItem(name: 'Hu Tao', id: '5125428', subMenuId: 1),
        ]),
      );
      final fetcher = HoYoWikiFetcher();
      final hit = await fetcher.searchEntryId(
        name: 'Hu Tao',
        lang: 'en-us',
        client: mock,
      );
      expect(hit, isNull);
    });

    test('空 list → null', () async {
      final mock = MockClient((req) async => _searchOk(const []));
      final fetcher = HoYoWikiFetcher();
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
      final fetcher = HoYoWikiFetcher();
      final hit = await fetcher.searchEntryId(
        name: 'Hu Tao',
        lang: 'en-us',
        client: mock,
      );
      expect(hit?.id, '222');
    });

    test('retcode != 0 → throw ApiErrorException', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({'retcode': -1, 'message': 'fail', 'data': null}),
          200,
        ),
      );
      final fetcher = HoYoWikiFetcher();
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
      final fetcher = HoYoWikiFetcher();
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
      final fetcher = HoYoWikiFetcher();
      await fetcher.searchEntryId(name: '胡桃', lang: 'zh-tw', client: mock);
      expect(capturedUrl.queryParameters['keyword'], '胡桃');
    });

    test('sub_menu id 為字串 "2" → 也視為命中，menuId == 2', () async {
      final mock = MockClient(
        (req) async => _searchOk([
          _searchItem(name: 'Hu Tao', id: '5125428', subMenuId: '2'),
        ]),
      );
      final fetcher = HoYoWikiFetcher();
      final hit = await fetcher.searchEntryId(
        name: 'Hu Tao',
        lang: 'en-us',
        client: mock,
      );
      expect(hit?.id, '5125428');
      expect(hit?.menuId, 2);
    });

    test('sub_menu id 為字串 "4" → 也視為命中，menuId == 4', () async {
      final mock = MockClient(
        (req) async =>
            _searchOk([_searchItem(name: 'Sword', id: '9001', subMenuId: '4')]),
      );
      final fetcher = HoYoWikiFetcher();
      final hit = await fetcher.searchEntryId(
        name: 'Sword',
        lang: 'en-us',
        client: mock,
      );
      expect(hit?.id, '9001');
      expect(hit?.menuId, 4);
    });

    test('sub_menu id 為字串 "1" → 不命中', () async {
      final mock = MockClient(
        (req) async =>
            _searchOk([_searchItem(name: 'X', id: '111', subMenuId: '1')]),
      );
      final fetcher = HoYoWikiFetcher();
      final hit = await fetcher.searchEntryId(
        name: 'X',
        lang: 'en-us',
        client: mock,
      );
      expect(hit, isNull);
    });

    test('sub_menu id 為非數字字串 → 不命中', () async {
      final mock = MockClient(
        (req) async =>
            _searchOk([_searchItem(name: 'X', id: '111', subMenuId: 'foo')]),
      );
      final fetcher = HoYoWikiFetcher();
      final hit = await fetcher.searchEntryId(
        name: 'X',
        lang: 'en-us',
        client: mock,
      );
      expect(hit, isNull);
    });

    test('entry_page_id 為 int → 也能解析成字串', () async {
      final mock = MockClient(
        (req) async =>
            _searchOk([_searchItem(name: 'Hu Tao', id: 5125428, subMenuId: 2)]),
      );
      final fetcher = HoYoWikiFetcher();
      final hit = await fetcher.searchEntryId(
        name: 'Hu Tao',
        lang: 'en-us',
        client: mock,
      );
      expect(hit?.id, '5125428');
      expect(hit?.menuId, 2);
    });
  });

  group('HoYoWikiFetcher.fetchEntryPage', () {
    test('兩個 URL 都有 → 都回', () async {
      final mock = MockClient(
        (_) async => _entryOk(
          iconUrl: 'https://x/icon.png',
          headerUrl: 'https://x/header.png',
        ),
      );
      final fetcher = HoYoWikiFetcher();
      final entry = await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(entry.iconUrl, 'https://x/icon.png');
      expect(entry.headerImgUrl, 'https://x/header.png');
    });

    test('icon_url 為空字串 → 照回空', () async {
      final mock = MockClient(
        (_) async => _entryOk(iconUrl: '', headerUrl: 'https://x/header.png'),
      );
      final fetcher = HoYoWikiFetcher();
      final entry = await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(entry.iconUrl, '');
      expect(entry.headerImgUrl, 'https://x/header.png');
    });

    test('header_img_url 為空字串 → 照回空', () async {
      final mock = MockClient(
        (_) async => _entryOk(iconUrl: 'https://x/icon.png', headerUrl: ''),
      );
      final fetcher = HoYoWikiFetcher();
      final entry = await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(entry.iconUrl, 'https://x/icon.png');
      expect(entry.headerImgUrl, '');
    });

    test('兩個 URL 都空字串 → 都回空', () async {
      final mock = MockClient(
        (_) async => _entryOk(iconUrl: '', headerUrl: ''),
      );
      final fetcher = HoYoWikiFetcher();
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
      final fetcher = HoYoWikiFetcher();
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
      final fetcher = HoYoWikiFetcher();
      await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(capturedUrl.queryParameters['entry_page_id'], '5125428');
      expect(capturedUrl.host, 'sg-act-public-api-static.hoyolab.com');
    });
  });

  group('HoYoWikiFetcher.downloadImage', () {
    test('200 OK → 回 bytes', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final mock = MockClient((_) async => http.Response.bytes(bytes, 200));
      final fetcher = HoYoWikiFetcher();
      final out = await fetcher.downloadImage('https://x/icon.png', mock);
      expect(out, bytes);
    });

    test('404 → 回 null', () async {
      final mock = MockClient((_) async => http.Response('', 404));
      final fetcher = HoYoWikiFetcher();
      final out = await fetcher.downloadImage('https://x/icon.png', mock);
      expect(out, isNull);
    });

    test('throw → 回 null', () async {
      final mock = MockClient(
        (_) async => throw const SocketException('connection refused'),
      );
      final fetcher = HoYoWikiFetcher();
      final out = await fetcher.downloadImage('https://x/icon.png', mock);
      expect(out, isNull);
    });
  });
}
