import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_export.dart';

BannerStorage _bs(String uid, DateTime updated) => BannerStorage(
  uid: uid,
  lastUpdated: updated,
  banners: const {'301': [], '302': [], '100': [], '200': [], '500': []},
);

void main() {
  test('accounts order follows mergeUidOrder + inlines alias + lastActive', () {
    final byUid = {
      'A': _bs('A', DateTime.utc(2026, 5, 10)),
      'B': _bs('B', DateTime.utc(2026, 5, 12)),
      'C': _bs('C', DateTime.utc(2026, 5, 11)),
    };
    final out = exportAccounts(
      byUid: byUid,
      uidOrder: const [
        'C',
        'A',
      ], // custom order; B not in custom → goes by lastUpdated
      uidAliases: const {'A': '主號', 'C': '小號'},
      lastActiveUid: 'A',
      appVersion: '9.9.9',
      now: DateTime.utc(2026, 5, 12, 8, 30),
    );

    final decoded = jsonDecode(out) as Map<String, dynamic>;
    expect(decoded['schema_version'], 1);
    expect(decoded['app_version'], '9.9.9');
    expect(decoded['last_active_uid'], 'A');
    expect(decoded['exported_at'], '2026-05-12T08:30:00.000Z');

    final accounts = decoded['accounts'] as List<dynamic>;
    expect(accounts.map((a) => a['uid']).toList(), ['C', 'A', 'B']);
    expect(accounts[0]['alias'], '小號');
    expect(accounts[1]['alias'], '主號');
    expect(accounts[2].containsKey('alias'), isFalse);

    // pretty-printed → contains newlines + 2-space indent
    expect(out.contains('\n  '), isTrue);
  });

  test('exports only the byUid subset it was given', () {
    // byUid 只塞兩個，模擬 picker 過濾後的子集
    final byUid = {
      'A': _bs('A', DateTime.utc(2026, 5, 10)),
      'C': _bs('C', DateTime.utc(2026, 5, 11)),
    };
    final out = exportAccounts(
      byUid: byUid,
      uidOrder: const ['A', 'C'],
      uidAliases: const {'A': '主號'},
      lastActiveUid: null,
      appVersion: '9.9.9',
      now: DateTime.utc(2026, 5, 12),
    );
    final decoded = jsonDecode(out) as Map<String, dynamic>;
    final accounts = decoded['accounts'] as List<dynamic>;
    expect(accounts.map((a) => a['uid']).toList(), ['A', 'C']);
    expect(decoded['last_active_uid'], isNull);
  });
}
