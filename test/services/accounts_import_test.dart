import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_import.dart';

Map<String, dynamic> _account(String uid, List<String> codes) => {
  'uid': uid,
  'last_updated': '2026-05-12T07:55:00.000Z',
  'banners': {for (final c in codes) c: <dynamic>[]},
};

Map<String, dynamic> _bundle({
  String? app,
  int schema = 1,
  required List<Map<String, dynamic>> accounts,
}) => {
  'schema_version': schema,
  'app': ?app,
  'exported_at': '2026-05-12T08:30:00.000Z',
  'app_version': '1.0.0',
  'last_active_uid': null,
  'accounts': accounts,
};

void main() {
  test('parses a minimal valid bundle', () {
    const text = '''
{
  "schema_version": 1,
  "exported_at": "2026-05-12T08:30:00.000Z",
  "app_version": "1.0.0",
  "last_active_uid": null,
  "accounts": []
}
''';
    final bundle = importAccounts(text);
    expect(bundle.schemaVersion, 1);
    expect(bundle.accounts, isEmpty);
  });

  test('not JSON → FormatException("Invalid JSON")', () {
    expect(
      () => importAccounts('definitely not json'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Invalid JSON'),
        ),
      ),
    );
  });

  test('top-level array → FormatException', () {
    expect(
      () => importAccounts('[]'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('object'),
        ),
      ),
    );
  });

  test('schema_version > 1 → UnsupportedSchemaVersionException', () {
    const text = '''
{
  "schema_version": 999,
  "exported_at": "2026-05-12T08:30:00.000Z",
  "app_version": "1.0.0",
  "last_active_uid": null,
  "accounts": []
}
''';
    expect(
      () => importAccounts(text),
      throwsA(
        isA<UnsupportedSchemaVersionException>().having(
          (e) => e.version,
          'version',
          999,
        ),
      ),
    );
  });

  test('explicit app mismatch → ForeignBundleException', () {
    final text = jsonEncode(
      _bundle(
        app: 'wuthering_waves_convene_gacha_analyzer',
        accounts: [
          _account('A', ['301']),
        ],
      ),
    );
    expect(() => importAccounts(text), throwsA(isA<ForeignBundleException>()));
  });

  test('explicit app match → no filtering, unknown codes kept', () {
    final text = jsonEncode(
      _bundle(
        app: accountsBundleAppId,
        accounts: [
          _account('A', ['301', '600']),
        ],
      ),
    );
    final bundle = importAccounts(text);
    expect(bundle.accounts.single.data.banners.keys.toSet(), {'301', '600'});
  });

  test('legacy pure Genshin codes → all banners kept', () {
    final text = jsonEncode(
      _bundle(
        accounts: [
          _account('A', ['301', '302']),
        ],
      ),
    );
    final bundle = importAccounts(text);
    expect(bundle.accounts.single.data.banners.keys.toSet(), {'301', '302'});
  });

  test('legacy pure Wuthering Waves codes → ForeignBundleException', () {
    final text = jsonEncode(
      _bundle(
        accounts: [
          _account('A', ['1', '2', '7']),
        ],
      ),
    );
    expect(() => importAccounts(text), throwsA(isA<ForeignBundleException>()));
  });

  test('legacy mixed codes → unknown banners filtered, known kept', () {
    final text = jsonEncode(
      _bundle(
        accounts: [
          _account('A', ['301', '1']),
        ],
      ),
    );
    final bundle = importAccounts(text);
    expect(bundle.accounts.single.data.banners.keys.toSet(), {'301'});
  });

  test('legacy mixed → account left with only foreign codes is dropped', () {
    final text = jsonEncode(
      _bundle(
        accounts: [
          _account('A', ['301']),
          _account('B', ['1', '2']),
        ],
      ),
    );
    final bundle = importAccounts(text);
    expect(bundle.accounts.map((a) => a.data.uid).toList(), ['A']);
  });

  test('legacy empty accounts → not foreign, empty bundle', () {
    final text = jsonEncode(_bundle(accounts: []));
    final bundle = importAccounts(text);
    expect(bundle.accounts, isEmpty);
  });

  test('pure foreign with schema_version 999 → ForeignBundleException '
      '(precedes version check)', () {
    final text = jsonEncode(
      _bundle(
        schema: 999,
        accounts: [
          _account('A', ['1']),
        ],
      ),
    );
    expect(() => importAccounts(text), throwsA(isA<ForeignBundleException>()));
  });
}
