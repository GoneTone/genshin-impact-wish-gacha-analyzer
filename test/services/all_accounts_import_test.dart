import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/all_accounts_import.dart';

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
    final bundle = importAllAccounts(text);
    expect(bundle.schemaVersion, 1);
    expect(bundle.accounts, isEmpty);
  });

  test('not JSON → FormatException("Invalid JSON")', () {
    expect(
      () => importAllAccounts('definitely not json'),
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
      () => importAllAccounts('[]'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('object'),
        ),
      ),
    );
  });
}
