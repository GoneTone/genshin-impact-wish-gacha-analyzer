import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart'
    show ApiErrorException;
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_fetcher.dart';

void main() {
  String pageBody(List<Map<String, String>> items) => jsonEncode({
    'retcode': 0,
    'message': 'OK',
    'data': {'list': items, 'total': items.length},
  });

  test('paginates menu 2 and 4, accumulates id->name with kind', () async {
    final calls = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      calls.add(body);
      final menu = body['menu_id'];
      final page = body['page_num'];
      if (menu == '2' && page == 1) {
        return http.Response(
          pageBody([
            {'entry_page_id': '10', 'name': 'A'},
            {'entry_page_id': '11', 'name': 'B'},
          ]),
          200,
        );
      }
      if (menu == '2' && page == 2) {
        return http.Response(
          pageBody([
            {'entry_page_id': '12', 'name': 'C'},
          ]),
          200,
        );
      }
      if (menu == '4') {
        return http.Response(
          pageBody([
            {'entry_page_id': '20', 'name': 'Sword'},
          ]),
          200,
        );
      }
      return http.Response(pageBody(const []), 200);
    });

    final fetcher = LangCatalogFetcher(pageSize: 2);
    final cat = await fetcher.fetchCatalog(lang: 'en-us', client: client);

    expect(cat.byId['10'], (name: 'A', kind: 2));
    expect(cat.byId['12'], (name: 'C', kind: 2));
    expect(cat.byId['20'], (name: 'Sword', kind: 4));
    expect(cat.byId.length, 4);
    expect(calls.any((b) => b['menu_id'] == '2'), isTrue);
    expect(calls.any((b) => b['menu_id'] == '4'), isTrue);
  });

  test('throws ApiErrorException on retcode != 0', () async {
    final client = MockClient(
      (req) async => http.Response(
        jsonEncode({'retcode': -1, 'message': 'bad', 'data': null}),
        200,
      ),
    );
    final fetcher = LangCatalogFetcher();
    await expectLater(
      fetcher.fetchCatalog(lang: 'en-us', client: client),
      throwsA(isA<ApiErrorException>()),
    );
  });
}
