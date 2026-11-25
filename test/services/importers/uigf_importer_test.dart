import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/importers/paimon_moe_importer.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/importers/uigf_importer.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/platform_import.dart';

/// 測試用 [ItemResolver]：查表回傳並記錄每次呼叫，查無丟 [ItemResolveException]。
class _FakeResolver implements ItemResolver {
  /// 建立 [_FakeResolver]。
  _FakeResolver({this.names = const {}, this.ranks = const {}});

  /// `item_id` → 名稱與語言。
  final Map<String, ({String name, String lang})> names;

  /// `'$lang|$name'` → 星級。
  final Map<String, int> ranks;

  /// [nameFor] 收到的 `item_id`（依呼叫順序）。
  final nameCalls = <String>[];

  /// [rankFor] 收到的 `'$lang|$name'`（依呼叫順序）。
  final rankCalls = <String>[];

  /// 記錄呼叫並從 [names] 查名稱與語言。
  @override
  Future<({String name, String lang})> nameFor(String itemId) async {
    nameCalls.add(itemId);
    return names[itemId] ?? (throw ItemResolveException('not found', itemId));
  }

  /// 記錄呼叫並從 [ranks] 查星級。
  @override
  Future<int> rankFor(String name, String lang) async {
    rankCalls.add('$lang|$name');
    return ranks['$lang|$name'] ??
        (throw ItemResolveException('not found', name));
  }
}

void main() {
  const importer = UigfImporter();

  /// 讀取 `test/fixtures/uigf/` 下的 [name]。
  Uint8List fixture(String name) =>
      File('test/fixtures/uigf/$name').readAsBytesSync();

  /// 把 [json] 編成 UTF-8 bytes。
  Uint8List encode(Object json) =>
      Uint8List.fromList(utf8.encode(jsonEncode(json)));

  /// 組一份 v4 檔，`hk4e` 只有一個 UID 100000001、語言 zh-tw 的帳號；
  /// [exportTimestamp] 為 null 時不寫 `export_timestamp`。
  Uint8List v4(
    List<Map<String, Object?>> list, {
    String version = 'v4.2',
    String? lang = 'zh-tw',
    Object? exportTimestamp = 1748750400,
  }) => encode({
    'info': {
      'export_timestamp': ?exportTimestamp,
      'export_app': 'fixture-exporter',
      'export_app_version': 'v1.0.0',
      'version': version,
    },
    'hk4e': [
      {'uid': '100000001', 'timezone': 8, 'lang': ?lang, 'list': list},
    ],
  });

  /// 一筆 v4 `hk4e` 記錄；傳 null 的欄位不寫進檔案。
  Map<String, Object?> rec({
    String? id = '1735696800000000001',
    String? gachaType = '200',
    String? itemId = '11301',
    String? name = '冷刃',
    String? itemType = '武器',
    String? rank = '3',
    String time = '2025-01-01 10:00:00',
    String? lang,
  }) => {
    'uigf_gacha_type': ?(gachaType == '400' ? '301' : gachaType),
    'gacha_type': ?gachaType,
    'item_id': ?itemId,
    'time': time,
    'name': ?name,
    'item_type': ?itemType,
    'rank_type': ?rank,
    'id': ?id,
    'lang': ?lang,
  };

  /// 唯一帳號的卡池表。
  Map<String, List<GachaRecord>> onlyBanners(AccountsBundle b) =>
      b.accounts.single.data.banners;

  test('importer metadata and registration order', () {
    expect(importer.id, 'uigf');
    expect(importer.fileExtensions, ['json']);
    expect(importer.requiresTargetUid, isFalse);
    expect(kPlatformImporters.first, isA<UigfImporter>());
    expect(kPlatformImporters[1], isA<PaimonMoeImporter>());
  });

  group('lastUpdated uses the export time, not the import moment', () {
    /// `export_timestamp` 1748750400 對應的時間。
    final exported = DateTime.utc(2025, 6, 1, 4);

    test('fixture int timestamp', () async {
      final bundle = await importer.parse(fixture('v3_0.json'));
      expect(bundle.accounts.single.data.lastUpdated, exported);
    });

    test('string timestamp', () async {
      final bundle = await importer.parse(
        v4([rec()], exportTimestamp: '1748750400'),
      );
      expect(bundle.accounts.single.data.lastUpdated, exported);
    });

    test('missing or unparsable timestamp falls back to 1970', () async {
      for (final ts in [null, 'soon']) {
        final bundle = await importer.parse(v4([rec()], exportTimestamp: ts));
        expect(
          bundle.accounts.single.data.lastUpdated,
          DateTime.utc(1970),
          reason: '$ts',
        );
      }
    });
  });

  test('v3.0 single account', () async {
    final bundle = await importer.parse(fixture('v3_0.json'));
    expect(bundle.accounts, hasLength(1));
    final storage = bundle.accounts.single.data;
    expect(storage.uid, '100000001');
    expect(storage.banners.keys.toSet(), {'200', '301'});
    final coolSteel = storage.banners['200']!.single;
    expect(coolSteel.id, '1735696800000000001');
    expect(coolSteel.uid, '100000001');
    expect(coolSteel.gachaType, '200');
    expect(coolSteel.name, '冷刃');
    expect(coolSteel.itemType, '武器');
    expect(coolSteel.rankType, 3);
    expect(coolSteel.lang, 'zh-tw');
    expect(coolSteel.time, DateTime(2025, 1, 1, 10));
    expect(coolSteel.time.isUtc, isFalse);
  });

  test('v4.1 multiple accounts', () async {
    final bundle = await importer.parse(fixture('v4_1.json'));
    final byUid = {for (final a in bundle.accounts) a.data.uid: a.data};
    expect(byUid.keys.toSet(), {'100000001', '100000002'});
    expect(byUid['100000001']!.banners['200']!.single.lang, 'zh-tw');
    final second = byUid['100000002']!;
    expect(second.banners.keys.toSet(), {'302', '500'});
    final bennett = second.banners['500']!.single;
    expect(bennett.uid, '100000002');
    expect(bennett.name, 'Bennett');
    expect(bennett.lang, 'en-us');
  });

  test('v2.2 records carry uid and lang', () async {
    final bundle = await importer.parse(fixture('v2_2.json'));
    final byUid = {for (final a in bundle.accounts) a.data.uid: a.data};
    expect(byUid.keys.toSet(), {'100000001', '100000003'});
    final own = byUid['100000003']!.banners['200']!.single;
    expect(own.name, 'Cool Steel');
    expect(own.lang, 'en-us');
    final fallback = byUid['100000001']!.banners['200']!.single;
    expect(fallback.uid, '100000001');
    expect(fallback.lang, 'zh-cn');
  });

  test('400 kept and stored under key 301', () async {
    final banners = onlyBanners(await importer.parse(fixture('v3_0.json')));
    expect(banners.containsKey('400'), isFalse);
    expect(banners['301']!.map((r) => r.gachaType), ['301', '400', '301']);
  });

  test('ascending file order becomes newest first', () async {
    final banners = onlyBanners(await importer.parse(fixture('v3_0.json')));
    expect(banners['301']!.map((r) => r.id), [
      '1735869600000000001',
      '1735783200000000002',
      '1735783200000000001',
    ]);
  });

  test('invalid or missing id becomes substitute', () async {
    final banners = onlyBanners(
      await importer.parse(
        v4([
          rec(id: null, name: 'A'),
          rec(id: '', name: 'B'),
          rec(id: '123', name: 'C'),
          rec(id: '0202501011000000000', name: 'D'),
          rec(id: '1735696800000000001', name: 'E'),
        ]),
      ),
    );
    final byName = {for (final r in banners['200']!) r.name: r.id};
    expect(byName['E'], '1735696800000000001');
    for (final n in ['A', 'B', 'C', 'D']) {
      expect(byName[n], startsWith('0'), reason: n);
      expect(byName[n], hasLength(19), reason: n);
    }
    expect(byName['A'], '0202501011000000000');
    expect(byName['B'], '0202501011000000100');
    expect(byName['C'], '0202501011000000200');
    expect(byName['D'], '0202501011000000300');
  });

  test('same uid in hk4e and hk4e_ugc becomes one account', () async {
    final bundle = await importer.parse(fixture('v4_2.json'));
    final byUid = {for (final a in bundle.accounts) a.data.uid: a.data};
    expect(bundle.accounts, hasLength(2));
    expect(byUid['100000001']!.banners.keys.toSet(), {'200', '1000', '2000'});
    expect(byUid['100000002']!.banners.keys.toSet(), {'2000'});
  });

  test('hk4e_ugc maps op_gacha_type to 1000/2000', () async {
    final resolver = _FakeResolver();
    final bundle = await importer.parse(
      fixture('v4_2.json'),
      resolver: resolver,
    );
    final byUid = {for (final a in bundle.accounts) a.data.uid: a.data};
    final odes = byUid['100000001']!.banners;
    final standard = odes['1000']!.single;
    expect(standard.gachaType, '1000');
    expect(standard.name, '部件形錄·「典雅半身裙·葉綠」');
    expect(standard.itemType, '裝扮形錄');
    expect(standard.rankType, 2);
    expect(standard.lang, 'zh-tw');
    expect(standard.time, DateTime(2025, 10, 22, 13, 7, 45));
    expect(odes['2000']!.map((r) => r.gachaType), ['2000', '2000', '2000']);
    expect(odes['2000']!.map((r) => r.id), [
      '1761217800000000003',
      '1761217800000000002',
      '1761217800000000001',
    ]);

    // 帳號沒有 lang 的頌願記錄維持空字串，不找 resolver 補。
    final noLang = byUid['100000002']!.banners['2000']!;
    expect(noLang.map((r) => r.lang), ['', '']);
    expect(noLang.map((r) => r.rankType), [4, 3]);
    expect(resolver.nameCalls, isEmpty);
    expect(resolver.rankCalls, isEmpty);
  });

  test(
    'hk4e_ugc missing item_name or rank_type throws FormatException',
    () async {
      /// 一份只有一筆頌願記錄的 v4.2 檔，記錄去掉 [drop] 欄位。
      Uint8List odesWithout(String drop) => encode({
        'info': {'version': 'v4.2'},
        'hk4e_ugc': [
          {
            'uid': '100000001',
            'timezone': 8,
            'lang': 'zh-tw',
            'list': [
              {
                'id': '1761217800000000001',
                'schedule_id': '20',
                'item_type': '裝扮部件',
                'item_id': '260109',
                'item_name': '女性裝扮·「熾烈長袖衫」',
                'rank_type': '3',
                'time': '2025-10-23 19:52:08',
                'op_gacha_type': '20021',
              }..remove(drop),
            ],
          },
        ],
      });
      for (final drop in ['item_name', 'rank_type']) {
        final resolver = _FakeResolver();
        await expectLater(
          importer.parse(odesWithout(drop), resolver: resolver),
          throwsFormatException,
          reason: drop,
        );
        expect(resolver.nameCalls, isEmpty, reason: drop);
        expect(resolver.rankCalls, isEmpty, reason: drop);
      }
    },
  );

  test('duplicate official ids are kept once per banner key only', () async {
    const dupId = '1735696800000000001';
    final bytes = encode({
      'info': {'version': 'v4.2'},
      'hk4e': [
        {
          'uid': '100000001',
          'timezone': 8,
          'lang': 'zh-tw',
          'list': [
            rec(name: 'A'),
            rec(name: 'B'),
            rec(name: 'C', gachaType: '302'),
            rec(name: 'D', gachaType: '301'),
            rec(name: 'E', gachaType: '400'),
          ],
        },
      ],
      'hk4e_ugc': [
        {
          'uid': '100000001',
          'timezone': 8,
          'list': [
            {
              'id': dupId,
              'schedule_id': '20',
              'item_type': '裝扮部件',
              'item_id': '260109',
              'item_name': 'F',
              'rank_type': '3',
              'time': '2025-01-01 10:00:00',
              'op_gacha_type': '20021',
            },
          ],
        },
      ],
    });
    final banners = onlyBanners(await importer.parse(bytes));
    expect(
      {for (final e in banners.entries) e.key: e.value.map((r) => r.name)},
      {
        '200': ['A'],
        '302': ['C'],
        '301': ['D'],
        '2000': ['F'],
      },
    );
  });

  test('UTF-8 BOM is accepted', () async {
    final bytes = Uint8List.fromList([
      0xEF,
      0xBB,
      0xBF,
      ...v4([rec()]),
    ]);
    expect(onlyBanners(await importer.parse(bytes))['200'], hasLength(1));
  });

  test('time in a DST spring-forward gap is accepted as-is', () async {
    // 美東 2025-03-09 02:00～03:00 不存在；本地 round-trip 會在該時區誤判為非法時間。
    const text = '2025-03-09 02:30:00';
    expect(parseImportTime(text), DateTime.parse('2025-03-09T02:30:00'));
    final record = onlyBanners(
      await importer.parse(v4([rec(time: text)])),
    )['200']!.single;
    expect(record.time, DateTime.parse('2025-03-09T02:30:00'));
  });

  test('minor version newer than known still parses', () async {
    final bundle = await importer.parse(v4([rec()], version: 'v4.9'));
    expect(onlyBanners(bundle)['200'], hasLength(1));
  });

  test('major version 5 throws UigfVersionTooNewException', () async {
    await expectLater(
      importer.parse(v4([rec()], version: 'v5.0')),
      throwsA(
        isA<UigfVersionTooNewException>().having(
          (e) => e.version,
          'version',
          'v5.0',
        ),
      ),
    );
  });

  test('major version below 2 throws FormatException', () async {
    await expectLater(
      importer.parse(v4([rec()], version: 'v1.0')),
      throwsFormatException,
    );
  });

  test(
    'unknown gacha type throws UnknownGachaTypeException listing types',
    () async {
      final resolver = _FakeResolver();
      final bytes = encode({
        'info': {'version': 'v4.2'},
        'hk4e': [
          {
            'uid': '100000001',
            'timezone': 8,
            'list': [
              rec(gachaType: '600', name: null),
              rec(gachaType: '200'),
              rec(gachaType: '700'),
              rec(gachaType: '600'),
            ],
          },
        ],
        'hk4e_ugc': [
          {
            'uid': '100000001',
            'timezone': 8,
            'list': [
              {
                'id': '1761217800000000001',
                'schedule_id': '20',
                'item_type': '裝扮部件',
                'item_id': '260109',
                'item_name': '女性裝扮·「熾烈長袖衫」',
                'rank_type': '3',
                'time': '2025-10-23 19:52:08',
                'op_gacha_type': '30011',
              },
            ],
          },
        ],
      });
      await expectLater(
        importer.parse(bytes, resolver: resolver),
        throwsA(
          isA<UnknownGachaTypeException>().having((e) => e.types, 'types', {
            '600',
            '700',
            '30011',
          }),
        ),
      );
      expect(resolver.nameCalls, isEmpty);
    },
  );

  test(
    'missing name asks resolver; resolver null throws FormatException',
    () async {
      final bytes = v4([
        rec(name: null, itemId: '11301'),
        rec(
          id: '1735696800000000002',
          name: null,
          itemId: '11301',
          time: '2025-01-01 10:00:01',
        ),
        rec(id: '1735696800000000003', name: '冷刃', lang: null),
      ], lang: null);
      final resolver = _FakeResolver(
        names: {'11301': (name: 'Cool Steel', lang: 'en-us')},
      );
      final banners = onlyBanners(
        await importer.parse(bytes, resolver: resolver),
      );
      expect(
        banners['200']!.map((r) => (r.name, r.lang)),
        List.filled(3, ('Cool Steel', 'en-us')),
      );
      expect(resolver.nameCalls, ['11301']);
      expect(resolver.rankCalls, isEmpty);

      await expectLater(importer.parse(bytes), throwsFormatException);
    },
  );

  test('missing name without item_id throws FormatException', () async {
    await expectLater(
      importer.parse(
        v4([rec(name: null, itemId: null)]),
        resolver: _FakeResolver(),
      ),
      throwsFormatException,
    );
  });

  test('resolver failure propagates ItemResolveException', () async {
    await expectLater(
      importer.parse(v4([rec(name: null)]), resolver: _FakeResolver()),
      throwsA(isA<ItemResolveException>()),
    );
  });

  test('missing rank asks resolver', () async {
    final bytes = v4([
      rec(rank: null),
      rec(id: '1735696800000000002', rank: null, time: '2025-01-01 10:00:01'),
      rec(
        id: '1735696800000000003',
        rank: null,
        name: null,
        itemId: '1032',
        itemType: '角色',
      ),
    ]);
    final resolver = _FakeResolver(
      names: {'1032': (name: 'Bennett', lang: 'en-us')},
      ranks: {'zh-tw|冷刃': 3, 'en-us|Bennett': 4},
    );
    final banners = onlyBanners(
      await importer.parse(bytes, resolver: resolver),
    );
    expect(banners['200']!.map((r) => (r.name, r.rankType)), [
      ('冷刃', 3),
      ('Bennett', 4),
      ('冷刃', 3),
    ]);
    expect(resolver.rankCalls, ['zh-tw|冷刃', 'en-us|Bennett']);

    await expectLater(
      importer.parse(v4([rec(rank: null)])),
      throwsFormatException,
    );
  });

  test('missing item_type is stored as empty string', () async {
    final banners = onlyBanners(
      await importer.parse(v4([rec(itemType: null)])),
    );
    expect(banners['200']!.single.itemType, '');
  });

  test('non-UIGF json throws ForeignBundleException', () async {
    final foreign = [
      encode({'app': accountsBundleAppId, 'accounts': <Object>[]}),
      encode([1, 2, 3]),
      encode({'info': <String, Object>{}, 'list': <Object>[]}),
      encode({
        'info': {'uigf_version': 'v3.0'},
      }),
      encode({
        'info': {'version': 'v4.1'},
        'hkrpg': <Object>[],
      }),
      encode({
        'info': {'version': 'latest'},
        'hk4e': <Object>[],
      }),
    ];
    for (final (i, bytes) in foreign.indexed) {
      await expectLater(
        importer.parse(bytes),
        throwsA(isA<ForeignBundleException>()),
        reason: 'case $i',
      );
    }
  });

  test('invalid json throws FormatException', () async {
    await expectLater(
      importer.parse(Uint8List.fromList(utf8.encode('{not json'))),
      throwsFormatException,
    );
  });

  test('bad field values throw FormatException', () async {
    final bad = [
      v4([rec(time: '2025-13-01 10:00:00')]),
      v4([rec(time: '2025-01-01T10:00:00')]),
      v4([rec(rank: '6')]),
      v4([rec(rank: 'x')]),
      v4([rec(gachaType: null)]),
      encode({
        'info': {'version': 'v4.2'},
        'hk4e': [
          {
            'uid': '../evil',
            'timezone': 8,
            'list': [rec()],
          },
        ],
      }),
      encode({
        'info': {'uigf_version': 'v3.0', 'lang': 'zh-tw'},
        'list': [rec()],
      }),
    ];
    for (final (i, bytes) in bad.indexed) {
      await expectLater(
        importer.parse(bytes),
        throwsFormatException,
        reason: 'case $i',
      );
    }
  });

  test(
    'more than 100 substitute records in one second throws FormatException',
    () async {
      await expectLater(
        importer.parse(v4([for (var i = 0; i < 101; i++) rec(id: null)])),
        throwsFormatException,
      );
    },
  );

  test('substitute sequences are per account', () async {
    final bytes = encode({
      'info': {'version': 'v4.2'},
      'hk4e': [
        for (final uid in ['100000001', '100000002'])
          {
            'uid': uid,
            'timezone': 8,
            'lang': 'zh-tw',
            'list': [rec(id: null)],
          },
      ],
    });
    final bundle = await importer.parse(bytes);
    expect(bundle.accounts.map((a) => a.data.banners['200']!.single.id), [
      '0202501011000000000',
      '0202501011000000000',
    ]);
  });
}
