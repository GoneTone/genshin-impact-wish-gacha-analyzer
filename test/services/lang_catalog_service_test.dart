import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';

class _CountingFetcher extends LangCatalogFetcher {
  int calls = 0;
  @override
  Future<LangCatalog> fetchCatalog({
    required String lang,
    required http.Client client,
  }) async {
    calls++;
    return LangCatalog.fromEntries(lang, {'1': (name: 'N$calls', kind: 2)});
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('langsvc'));
  tearDown(() => tmp.deleteSync(recursive: true));

  LangCatalogService make(_CountingFetcher f) => LangCatalogService(
    storage: LangCatalogStorage(tmp),
    fetcher: f,
    clientFactory: () => MockClient((_) async => http.Response('', 200)),
  );

  test('fetches once, then reuses memo and disk', () async {
    final f = _CountingFetcher();
    final svc = make(f);
    await svc.ensure('en-us');
    await svc.ensure('en-us');
    expect(f.calls, 1);
    final svc2 = make(f);
    await svc2.ensure('en-us');
    expect(f.calls, 1);
  });

  test('forceRefresh bypasses memo and disk', () async {
    final f = _CountingFetcher();
    final svc = make(f);
    await svc.ensure('en-us');
    final refreshed = await svc.ensure('en-us', forceRefresh: true);
    expect(f.calls, 2);
    expect(refreshed.byId['1']!.name, 'N2');
  });
}
