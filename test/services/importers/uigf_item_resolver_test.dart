import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/importers/uigf_item_resolver.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/platform_import.dart';

/// 讀取 `test/fixtures/` 底下的 fixture 文字。
String _fixture(String path) => File('test/fixtures/$path').readAsStringSync();

/// 以 UTF-8（明確 charset）包成 200 回應，CJK 內容才不會被當 latin1 解。
http.Response _ok(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// 只有一筆角色命中（`entry_page_id` 1、sub_menu 2）的 search 回應。
String _searchHit(String name) => jsonEncode({
  'retcode': 0,
  'message': 'OK',
  'data': {
    'list': [
      {
        'entry_page_id': '1',
        'name': name,
        'menu': {
          'sub_menus': [
            {'id': '2'},
          ],
        },
      },
    ],
  },
});

/// `filter_values` 為 [filterValues] 的 entry_page 回應。
String _entry(Map<String, Object?> filterValues) => jsonEncode({
  'retcode': 0,
  'message': 'OK',
  'data': {
    'page': {'icon_url': '', 'filter_values': filterValues, 'modules': []},
  },
});

/// 依路徑分派的假 HTTP：`/dict/genshin/{code}.json` 回 [dicts]，HoYoWiki search
/// 與 entry_page 交給 [search]／[entry]；所有請求記在 [requests]。
class _FakeServer {
  /// 建立 [_FakeServer]。
  _FakeServer({this.dicts = const {}, this.search, this.entry, this.onDict});

  /// UIGF 字典代碼 → 回應內容。
  final Map<String, String> dicts;

  /// HoYoWiki search 的回應產生器（依請求）。
  final http.Response Function(http.Request req)? search;

  /// HoYoWiki entry_page 的回應產生器（依請求）。
  final http.Response Function(http.Request req)? entry;

  /// 覆寫字典請求的回應（用於失敗情境）。
  final Future<http.Response> Function(http.Request req)? onDict;

  /// 收到的所有請求（依順序）。
  final requests = <http.Request>[];

  /// 對應的 [MockClient]。
  late final client = MockClient((req) async {
    requests.add(req);
    final path = req.url.path;
    if (path.startsWith('/dict/genshin/')) {
      if (onDict != null) return onDict!(req);
      final code = path.substring('/dict/genshin/'.length).split('.').first;
      final body = dicts[code];
      return body == null ? http.Response('', 404) : _ok(body);
    }
    if (path.endsWith('/wapi/search')) return search!(req);
    if (path.endsWith('/wapi/entry_page')) return entry!(req);
    return http.Response('', 404);
  });

  /// 字典請求（依順序）的 UIGF 代碼。
  List<String> get dictCodes => [
    for (final r in requests)
      if (r.url.path.startsWith('/dict/genshin/'))
        r.url.pathSegments.last.split('.').first,
  ];

  /// 某路徑結尾的請求數。
  int count(String suffix) =>
      requests.where((r) => r.url.path.endsWith(suffix)).length;
}

/// 以 [server] 與 [targetLang] 建立待測的 [UigfItemResolver]。
UigfItemResolver _resolver(_FakeServer server, {String targetLang = 'zh-tw'}) =>
    UigfItemResolver(
      client: server.client,
      hoyowiki: HoYoWikiFetcher(),
      targetLang: targetLang,
    );

/// 斷言 [future] 以 [ItemResolveException] 失敗，且 `item` 為 [item]。
Future<void> _expectResolveError(Future<Object?> future, String item) =>
    expectLater(
      future,
      throwsA(isA<ItemResolveException>().having((e) => e.item, 'item', item)),
    );

void main() {
  group('nameFor', () {
    test('以資料語言的 UIGF 字典反轉查名（zh-tw → cht）', () async {
      final server = _FakeServer(
        dicts: {'cht': _fixture('uigf/dict_cht.json')},
      );
      final r = _resolver(server);

      expect(await r.nameFor('10000023'), (name: '香菱', lang: 'zh-tw'));
      expect(await r.nameFor('11502'), (name: '天空之刃', lang: 'zh-tw'));
      expect(
        server.requests.single.url.toString(),
        'https://api.uigf.org/dict/genshin/cht.json',
      );
    });

    test('每個 App 資料語言對應到正確的 UIGF 字典代碼', () async {
      const expected = {
        'zh-tw': 'cht',
        'zh-cn': 'chs',
        'en-us': 'en',
        'ja-jp': 'jp',
        'ko-kr': 'kr',
        'es-es': 'es',
        'fr-fr': 'fr',
        'ru-ru': 'ru',
        'th-th': 'th',
        'vi-vn': 'vi',
        'de-de': 'de',
        'id-id': 'id',
        'pt-pt': 'pt',
      };
      for (final MapEntry(key: lang, value: code) in expected.entries) {
        final server = _FakeServer(
          dicts: {code: _fixture('uigf/dict_en.json')},
        );
        final got = await _resolver(server, targetLang: lang).nameFor('11502');
        expect(server.dictCodes, [code], reason: lang);
        expect(got, (name: 'Skyward Blade', lang: lang), reason: lang);
      }
    });

    for (final lang in ['tr-tr', 'it-it']) {
      test('$lang 沒有 UIGF 字典：改用 en 字典並回傳 en-us', () async {
        final server = _FakeServer(
          dicts: {'en': _fixture('uigf/dict_en.json')},
        );
        final got = await _resolver(server, targetLang: lang).nameFor('11301');
        expect(got, (name: 'Cool Steel', lang: 'en-us'));
        expect(server.dictCodes, ['en']);
      });
    }

    test('不支援的資料語言丟 ItemResolveException 且不發請求', () async {
      final server = _FakeServer();
      await _expectResolveError(
        _resolver(server, targetLang: 'xx-yy').nameFor('11502'),
        '11502',
      );
      expect(server.requests, isEmpty);
    });

    test('同一個實例同語言字典只請求一次', () async {
      final server = _FakeServer(
        dicts: {'cht': _fixture('uigf/dict_cht.json')},
      );
      final r = _resolver(server);
      await Future.wait([r.nameFor('10000023'), r.nameFor('11502')]);
      await r.nameFor('11301');
      expect(server.dictCodes, ['cht']);
    });

    test('字典查無 item_id 丟 ItemResolveException', () async {
      final server = _FakeServer(
        dicts: {'cht': _fixture('uigf/dict_cht.json')},
      );
      await _expectResolveError(_resolver(server).nameFor('99999'), '99999');
    });

    final failures = <String, Future<http.Response> Function(http.Request)>{
      '非 200': (_) async => http.Response('Forbidden', 403),
      '不是 JSON': (_) async => _ok('<html>oops</html>'),
      '不是物件': (_) async => _ok('[1, 2]'),
      'id 不是整數': (_) async => _ok('{"香菱": "10000023"}'),
      '連線失敗': (_) async => throw http.ClientException('offline'),
      '逾時': (_) async => throw TimeoutException('slow'),
    };
    for (final MapEntry(key: label, value: onDict) in failures.entries) {
      test('字典$label丟 ItemResolveException', () async {
        final server = _FakeServer(onDict: onDict);
        await _expectResolveError(
          _resolver(server).nameFor('10000023'),
          '10000023',
        );
      });
    }
  });

  group('rankFor', () {
    /// 以錄下的真實 search／entry_page fixture 回應 [name]（[slug] 為檔名）。
    _FakeServer recorded(String slug, String lang) => _FakeServer(
      search: (req) {
        expect(req.headers['X-Rpc-Language'], lang);
        return _ok(_fixture('hoyowiki/search_${slug}_$lang.json'));
      },
      entry: (req) {
        expect(req.headers['X-Rpc-Language'], lang);
        return _ok(_fixture('hoyowiki/entry_${slug}_$lang.json'));
      },
    );

    for (final (slug, name, lang, rank) in [
      ('xiangling', '香菱', 'zh-tw', 4),
      ('xiangling', 'Xiangling', 'en-us', 4),
      ('skyward_blade', '天空之刃', 'zh-tw', 5),
      ('skyward_blade', 'Skyward Blade', 'en-us', 5),
    ]) {
      test('真實 fixture：$name（$lang）→ $rank 星', () async {
        final server = recorded(slug, lang);
        expect(await _resolver(server).rankFor(name, lang), rank);
        expect(server.count('/wapi/search'), 1);
        expect(server.count('/wapi/entry_page'), 1);
      });
    }

    test('同名同語言只查一次', () async {
      final server = recorded('xiangling', 'zh-tw');
      final r = _resolver(server);
      await Future.wait([r.rankFor('香菱', 'zh-tw'), r.rankFor('香菱', 'zh-tw')]);
      await r.rankFor('香菱', 'zh-tw');
      expect(server.count('/wapi/search'), 1);
      expect(server.count('/wapi/entry_page'), 1);
    });

    final observed = (jsonDecode(_fixture('hoyowiki/rarity_tags.json')) as List)
        .cast<Map<String, dynamic>>();
    for (final o in observed) {
      test('各語言實測星級標籤：${o['lang']} ${o['tag']} → ${o['rank']}', () async {
        final server = _FakeServer(
          search: (_) => _ok(_searchHit(o['name'] as String)),
          entry: (_) => _ok(
            _entry({
              'other': {
                'values': ['Pyro'],
              },
              o['group'] as String: {
                'values': [o['tag']],
              },
            }),
          ),
        );
        expect(
          await _resolver(
            server,
          ).rankFor(o['name'] as String, o['lang'] as String),
          o['rank'],
        );
      });
    }

    for (final (label, tags) in [
      ('沒有星級標籤', ['Pyro', 'Sword']),
      ('沒看過的格式', ['4 stars']),
      ('超出範圍', ['6★']),
      ('互相矛盾', ['4★', '五星']),
    ]) {
      test('$label丟 ItemResolveException', () async {
        final server = _FakeServer(
          search: (_) => _ok(_searchHit('X')),
          entry: (_) => _ok(
            _entry({
              'g': {'values': tags},
            }),
          ),
        );
        await _expectResolveError(_resolver(server).rankFor('X', 'en-us'), 'X');
      });
    }

    test('HoYoWiki 查無同名條目丟 ItemResolveException', () async {
      final server = _FakeServer(
        search: (_) => _ok(_fixture('hoyowiki/search_xiangling_en-us.json')),
      );
      await _expectResolveError(
        _resolver(server).rankFor('Nobody', 'en-us'),
        'Nobody',
      );
      expect(server.count('/wapi/entry_page'), 0);
    });

    final failures = <String, http.Response Function(http.Request)>{
      'retcode 非 0': (_) => _ok('{"retcode": -1, "message": "bad"}'),
      '不是 JSON': (_) => _ok('<html>oops</html>'),
      '連線失敗': (_) => throw http.ClientException('offline'),
    };
    for (final MapEntry(key: label, value: search) in failures.entries) {
      test('HoYoWiki $label丟 ItemResolveException', () async {
        final server = _FakeServer(search: search);
        await _expectResolveError(
          _resolver(server).rankFor('香菱', 'zh-tw'),
          '香菱',
        );
      });
    }
  });
}
