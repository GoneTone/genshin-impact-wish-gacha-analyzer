import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('langcat'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'LangCatalog.fromEntries derives idByName and drops ambiguous names',
    () {
      final c = LangCatalog.fromEntries('en-us', {
        '1': (name: 'Hu Tao', kind: 2),
        '2': (name: 'Staff', kind: 4),
        '3': (name: 'Staff', kind: 4),
      });
      expect(c.idByName['Hu Tao'], '1');
      expect(c.idByName.containsKey('Staff'), isFalse);
      expect(c.byId['1']!.kind, 2);
    },
  );

  test('save then load round-trips', () async {
    final storage = LangCatalogStorage(tmp);
    final c = LangCatalog.fromEntries('zh-tw', {
      '5125428': (name: '胡桃', kind: 2),
    });
    await storage.save(c, fetchedAt: DateTime.utc(2026, 6, 16));
    final loaded = await storage.load('zh-tw');
    expect(loaded, isNotNull);
    expect(loaded!.byId['5125428']!.name, '胡桃');
    expect(loaded.byId['5125428']!.kind, 2);
    expect(loaded.idByName['胡桃'], '5125428');
  });

  test('load returns null when file missing', () async {
    final storage = LangCatalogStorage(tmp);
    expect(await storage.load('ja-jp'), isNull);
  });

  test('load returns null on corrupt file (logged, not thrown)', () async {
    final dir = Directory('${tmp.path}/sub')..createSync();
    File('${dir.path}/en-us.json').writeAsStringSync('{not json');
    final storage = LangCatalogStorage(dir);
    expect(await storage.load('en-us'), isNull);
  });
}
