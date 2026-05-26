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

http.Response _entryOk({required String iconUrl}) => http.Response(
  jsonEncode({
    'retcode': 0,
    'message': 'OK',
    'data': {
      'page': {'icon_url': iconUrl},
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
    test('icon_url 有值 → 照回', () async {
      final mock = MockClient(
        (_) async => _entryOk(iconUrl: 'https://x/icon.png'),
      );
      final fetcher = HoYoWikiFetcher();
      final entry = await fetcher.fetchEntryPage(
        id: '5125428',
        lang: 'en-us',
        client: mock,
      );
      expect(entry.iconUrl, 'https://x/icon.png');
    });

    test('icon_url 為空字串 → 照回空', () async {
      final mock = MockClient((_) async => _entryOk(iconUrl: ''));
      final fetcher = HoYoWikiFetcher();
      final entry = await fetcher.fetchEntryPage(
        id: '5125428',
        lang: 'en-us',
        client: mock,
      );
      expect(entry.iconUrl, '');
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
        () =>
            fetcher.fetchEntryPage(id: '5125428', lang: 'en-us', client: mock),
        throwsA(isA<ApiErrorException>()),
      );
    });

    test('URL 帶 entry_page_id query param', () async {
      late Uri capturedUrl;
      final mock = MockClient((req) async {
        capturedUrl = req.url;
        return _entryOk(iconUrl: '');
      });
      final fetcher = HoYoWikiFetcher();
      await fetcher.fetchEntryPage(id: '5125428', lang: 'en-us', client: mock);
      expect(capturedUrl.queryParameters['entry_page_id'], '5125428');
      expect(capturedUrl.host, 'sg-act-public-api-static.hoyolab.com');
    });
  });

  group('HoYoWikiFetcher.fetchEntryPage gallery', () {
    http.Response entryWithGallery({
      required String iconUrl,
      required String galleryDataJson,
    }) {
      final body = jsonEncode({
        'retcode': 0,
        'message': 'OK',
        'data': {
          'page': {
            'icon_url': iconUrl,
            'modules': [
              {
                'components': [
                  {'component_id': 'something_else', 'data': '{}'},
                  {
                    'component_id': 'gallery_character',
                    'data': galleryDataJson,
                  },
                ],
              },
            ],
          },
        },
      });
      return http.Response.bytes(
        utf8.encode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    test('帶 X-Rpc-Language header', () async {
      String? capturedLang;
      final mock = MockClient((req) async {
        capturedLang = req.headers['X-Rpc-Language'];
        return entryWithGallery(
          iconUrl: 'https://x/icon.png',
          galleryDataJson: '{"pic":"https://x/card.png","list":[]}',
        );
      });
      await HoYoWikiFetcher().fetchEntryPage(
        id: '12345',
        lang: 'zh-tw',
        client: mock,
      );
      expect(capturedLang, 'zh-tw');
    });

    test('正常解析 gallery_character', () async {
      final mock = MockClient(
        (req) async => entryWithGallery(
          iconUrl: 'https://x/icon.png',
          galleryDataJson: jsonEncode({
            'pic': 'https://x/card.png',
            'list': [
              {
                'id': 'gallery_character8511',
                'key': '原畫',
                'img': 'https://x/orig.png',
                'imgDesc': '<p>衣裝「魔女獵裝」</p>',
              },
              {
                'id': 'gallery_character99418',
                'key': '閒置動作１',
                'img': 'https://x/idle.gif',
                'imgDesc': '',
              },
            ],
          }),
        ),
      );
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345',
        lang: 'zh-tw',
        client: mock,
      );
      expect(res.iconUrl, 'https://x/icon.png');
      expect(res.gallery, isNotNull);
      expect(res.gallery!.picUrl, 'https://x/card.png');
      expect(res.gallery!.list, hasLength(2));
      expect(res.gallery!.list[0].key, '原畫');
      expect(res.gallery!.list[1].imgUrl, 'https://x/idle.gif');
      expect(res.gallery!.list[1].imgDescHtml, '');
    });

    test('無 gallery_character module → gallery 為 null', () async {
      final mock = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'retcode': 0,
            'message': 'OK',
            'data': {
              'page': {'icon_url': 'https://x/icon.png', 'modules': []},
            },
          }),
          200,
        ),
      );
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345',
        lang: 'zh-tw',
        client: mock,
      );
      expect(res.gallery, isNull);
    });

    test('data 非合法 JSON → gallery 為 null（不 throw）', () async {
      final mock = MockClient(
        (req) async => entryWithGallery(
          iconUrl: 'https://x/icon.png',
          galleryDataJson: '{not json',
        ),
      );
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345',
        lang: 'zh-tw',
        client: mock,
      );
      expect(res.gallery, isNull);
    });

    test('list[i] 缺 img 整筆 skip，其餘照存', () async {
      final mock = MockClient(
        (req) async => entryWithGallery(
          iconUrl: 'https://x/icon.png',
          galleryDataJson: jsonEncode({
            'pic': 'https://x/card.png',
            'list': [
              {'id': 'a', 'key': 'A', 'img': 'https://x/a.png', 'imgDesc': ''},
              {'id': 'b', 'key': 'B', 'img': '', 'imgDesc': ''},
              {'id': 'c', 'key': 'C', 'img': 'https://x/c.png', 'imgDesc': ''},
            ],
          }),
        ),
      );
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345',
        lang: 'zh-tw',
        client: mock,
      );
      expect(res.gallery!.list.map((it) => it.id).toList(), ['a', 'c']);
    });

    test('pic 與 list 皆空 → gallery 為 null', () async {
      final mock = MockClient(
        (req) async => entryWithGallery(
          iconUrl: 'https://x/icon.png',
          galleryDataJson: jsonEncode({'pic': '', 'list': []}),
        ),
      );
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345',
        lang: 'zh-tw',
        client: mock,
      );
      expect(res.gallery, isNull);
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

  group('HoYoWikiFetcher._parseTags', () {
    test('多 group 攤平、保留出現順序', () {
      final input = {
        'character_property': {
          'values': ['生命之契'],
        },
        'character_rarity': {
          'values': ['4星'],
        },
        'character_region': {
          'values': ['蒙德'],
        },
      };
      expect(HoYoWikiFetcher.parseTagsDebug(input), ['生命之契', '4星', '蒙德']);
    });

    test('跨 group 重複 value 去重、保留首次出現位置', () {
      final input = {
        'g1': {
          'values': ['A', 'B'],
        },
        'g2': {
          'values': ['B', 'C'],
        },
        'g3': {
          'values': ['A'],
        },
      };
      expect(HoYoWikiFetcher.parseTagsDebug(input), ['A', 'B', 'C']);
    });

    test('filter_values 為 null → 空 list', () {
      expect(HoYoWikiFetcher.parseTagsDebug(null), const <String>[]);
    });

    test('filter_values 非 map → 空 list', () {
      expect(HoYoWikiFetcher.parseTagsDebug('not a map'), const <String>[]);
      expect(HoYoWikiFetcher.parseTagsDebug(123), const <String>[]);
      expect(HoYoWikiFetcher.parseTagsDebug([]), const <String>[]);
    });

    test('group 缺 values key → 該 group skip', () {
      final input = {
        'g1': {
          'values': ['A'],
        },
        'g2': {'something_else': 'x'},
        'g3': {
          'values': ['B'],
        },
      };
      expect(HoYoWikiFetcher.parseTagsDebug(input), ['A', 'B']);
    });

    test('group 的 values 非 list → 該 group skip', () {
      final input = {
        'g1': {
          'values': ['A'],
        },
        'g2': {'values': 'not a list'},
        'g3': {
          'values': ['B'],
        },
      };
      expect(HoYoWikiFetcher.parseTagsDebug(input), ['A', 'B']);
    });

    test('value 非 string → skip', () {
      final input = {
        'g1': {
          'values': ['A', 123, null, 'B'],
        },
      };
      expect(HoYoWikiFetcher.parseTagsDebug(input), ['A', 'B']);
    });

    test('value trim 後為空字串 → skip', () {
      final input = {
        'g1': {
          'values': ['A', '   ', '\t\n', 'B'],
        },
      };
      expect(HoYoWikiFetcher.parseTagsDebug(input), ['A', 'B']);
    });

    test('回傳 List.unmodifiable（不可變）', () {
      final out = HoYoWikiFetcher.parseTagsDebug({
        'g1': {
          'values': ['A'],
        },
      });
      expect(() => out.add('x'), throwsUnsupportedError);
    });
  });
}
