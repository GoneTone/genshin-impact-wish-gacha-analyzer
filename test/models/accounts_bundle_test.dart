import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';

GachaRecord _r(String id, {String uid = '1'}) => GachaRecord(
  id: id,
  uid: uid,
  gachaType: '301',
  name: '夜蘭',
  itemType: '角色',
  rankType: 5,
  time: DateTime.utc(2025, 4, 1, 14, 23),
  lang: 'zh-tw',
);

void main() {
  test(
    'toJson / fromJson roundtrip preserves order, alias, last_active_uid',
    () {
      final bundle = AccountsBundle(
        exportedAt: DateTime.utc(2026, 5, 12, 8, 30),
        appVersion: '1.2.3',
        lastActiveUid: 'A',
        accounts: [
          ExportedAccount(
            alias: '主號',
            data: BannerStorage(
              uid: 'A',
              lastUpdated: DateTime.utc(2026, 5, 12, 7, 55),
              banners: {
                '301': [_r('1', uid: 'A')],
              },
            ),
          ),
          ExportedAccount(
            data: BannerStorage(
              uid: 'B',
              lastUpdated: DateTime.utc(2026, 5, 11, 20, 11),
              banners: const {'301': []},
            ),
          ),
        ],
      );

      final json = bundle.toJson();
      final back = AccountsBundle.fromJson(json);

      expect(back.schemaVersion, 1);
      expect(back.lastActiveUid, 'A');
      expect(back.accounts.map((a) => a.data.uid).toList(), ['A', 'B']);
      expect(back.accounts[0].alias, '主號');
      expect(back.accounts[1].alias, isNull);
      expect(back.accounts[0].data.banners['301']!.first.name, '夜蘭');
    },
  );

  test('schema_version > 1 throws with "update the app" hint', () {
    final json = {
      'schema_version': 999,
      'exported_at': '2026-05-12T00:00:00.000Z',
      'app_version': '1.0.0',
      'last_active_uid': null,
      'accounts': <Map<String, dynamic>>[],
    };
    expect(
      () => AccountsBundle.fromJson(json),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('update the app'),
        ),
      ),
    );
  });

  test('missing schema_version throws', () {
    expect(
      () => AccountsBundle.fromJson({'accounts': []}),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('schema_version'),
        ),
      ),
    );
  });

  test('accounts must be an array', () {
    expect(
      () => AccountsBundle.fromJson({'schema_version': 1, 'accounts': 'nope'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('duplicate UID throws', () {
    final accountJson = BannerStorage(
      uid: 'X',
      lastUpdated: DateTime.utc(2026),
      banners: const {'301': []},
    ).toJson();
    expect(
      () => AccountsBundle.fromJson({
        'schema_version': 1,
        'accounts': [accountJson, accountJson],
      }),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Duplicate UID'),
        ),
      ),
    );
  });

  test('alias empty string is read back as null', () {
    final bundle = AccountsBundle.fromJson({
      'schema_version': 1,
      'accounts': [
        {
          ...BannerStorage(
            uid: 'A',
            lastUpdated: DateTime.utc(2026),
            banners: const {'301': []},
          ).toJson(),
          'alias': '   ',
        },
      ],
    });
    expect(bundle.accounts.single.alias, isNull);
  });
}
