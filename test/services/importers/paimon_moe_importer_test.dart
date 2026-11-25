import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/importers/paimon_moe_importer.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/platform_import.dart';

import '../../helpers/xlsx_fixture.dart';

void main() {
  const importer = PaimonMoeImporter();

  /// 解析 [banners] 組成的 paimon.moe 檔，回傳唯一帳號的卡池表。
  Future<Map<String, List<GachaRecord>>> parseBanners(
    Map<String, List<List<Object?>>> banners,
  ) async {
    final bundle = await importer.parse(buildPaimonXlsx(banners));
    return bundle.accounts.single.data.banners;
  }

  test('importer metadata', () {
    expect(importer.id, 'paimon_moe');
    expect(importer.fileExtensions, ['xlsx']);
    expect(importer.requiresTargetUid, isTrue);
    expect(kPlatformImporters, contains(isA<PaimonMoeImporter>()));
  });

  test('maps sheets and Wish 2 to gacha types', () async {
    final bundle = await importer.parse(
      buildPaimonXlsx({
        'Character Event': [
          paimonRow('Weapon', 'Cool Steel', '2025-01-01 10:00:00', 3),
          paimonRow(
            'Character',
            'Bennett',
            '2025-01-01 10:00:01',
            4,
            part: 'Wish 2',
          ),
        ],
        'Weapon Event': [
          paimonRow('Weapon', 'Slingshot', '2025-01-02 10:00:00', 3),
        ],
        'Standard': [
          paimonRow('Weapon', 'Skyrider Sword', '2025-01-03 10:00:00', 3),
        ],
        "Beginners' Wish": [
          paimonRow('Character', 'Noelle', '2025-01-04 10:00:00', 4),
        ],
        'Chronicled Wish': [
          paimonRow(
            'Weapon',
            'Thrilling Tales of Dragon Slayers',
            '2025-01-05 10:00:00',
            3,
          ),
        ],
      }),
    );
    expect(bundle.accounts, hasLength(1));
    final storage = bundle.accounts.single.data;
    expect(storage.uid, '');
    final banners = storage.banners;
    final types = [
      for (final key in ['301', '302', '200', '100', '500'])
        ...banners[key]!.reversed.map((r) => r.gachaType),
    ];
    expect(types, ['301', '400', '302', '200', '100', '500']);
    expect(banners['301']!.length, 2);
    expect(banners.containsKey('400'), isFalse);

    final bennett = banners['301']!.first;
    expect(bennett.name, 'Bennett');
    expect(bennett.itemType, 'Character');
    expect(bennett.rankType, 4);
    expect(bennett.lang, 'en-us');
    expect(bennett.uid, '');
    expect(bennett.time, DateTime(2025, 1, 1, 10, 0, 1));
    expect(bennett.time.isUtc, isFalse);
  });

  test(
    'same-second rows get sequential substitute ids in sheet order',
    () async {
      final banners = await parseBanners({
        'Character Event': [
          paimonRow('Weapon', 'Cool Steel', '2025-12-01 04:06:48', 3),
          paimonRow('Character', 'Bennett', '2025-12-01 04:06:48', 4),
          paimonRow(
            'Weapon',
            'Slingshot',
            '2025-12-01 04:06:48',
            3,
            part: 'Wish 2',
          ),
        ],
      });
      final byName = {for (final r in banners['301']!) r.name: r.id};
      expect(byName['Cool Steel'], '0202512010406480000');
      expect(byName['Bennett'], '0202512010406480100');
      expect(byName['Slingshot'], '0202512010406480200');
    },
  );

  test('records sorted newest first', () async {
    final banners = await parseBanners({
      'Weapon Event': [
        paimonRow('Weapon', 'A', '2025-01-01 10:00:00', 3),
        paimonRow('Weapon', 'B', '2025-01-01 10:00:00', 3),
        paimonRow('Weapon', 'C', '2025-01-02 09:00:00', 3),
      ],
    });
    expect(banners['302']!.map((r) => r.name), ['C', 'B', 'A']);
  });

  test('time as excel date cell', () async {
    final banners = await parseBanners({
      'Standard': [
        paimonRow('Weapon', 'Date Cell', DateTime(2025, 12, 1, 4, 6, 48), 3),
        paimonRow('Weapon', 'Text Cell', '2025-12-01 04:06:48', 3),
      ],
    });
    final records = banners['200']!;
    expect(records.map((r) => r.time).toSet(), {
      DateTime(2025, 12, 1, 4, 6, 48),
    });
    expect(records.every((r) => !r.time.isUtc), isTrue);
    expect(records.map((r) => r.toStorageJson()['time']).toSet(), {
      '2025-12-01 04:06:48',
    });
  });

  test('midnight excel date cell keeps the whole timestamp', () async {
    final banners = await parseBanners({
      'Standard': [paimonRow('Weapon', 'Midnight', DateTime(2025, 12, 1), 3)],
    });
    final record = banners['200']!.single;
    expect(record.time, DateTime(2025, 12, 1));
    expect(record.toStorageJson()['time'], '2025-12-01 00:00:00');
  });

  test('columns located by header name not position', () async {
    final bytes = buildXlsx({
      'Standard': [
        ['Part', '⭐', 'Banner', 'Time', 'Name', 'Type'],
        [
          '',
          5,
          'Wanderlust Invocation',
          '2025-03-04 05:06:07',
          'Diluc',
          'Character',
        ],
      ],
      'Information': [
        [paimonMarker],
      ],
    });
    final record = (await importer.parse(
      bytes,
    )).accounts.single.data.banners['200']!.single;
    expect(record.name, 'Diluc');
    expect(record.itemType, 'Character');
    expect(record.rankType, 5);
    expect(record.time, DateTime(2025, 3, 4, 5, 6, 7));
  });

  test('Banner List sheet ignored', () async {
    final banners = await parseBanners({
      'Standard': [paimonRow('Weapon', 'Cool Steel', '2025-01-01 10:00:00', 3)],
      'Banner List': [
        ['Something', 'Else'],
      ],
    });
    expect(banners.keys, ['200']);
  });

  test('blank rows are skipped', () async {
    final banners = await parseBanners({
      'Standard': [
        paimonRow('Weapon', 'Cool Steel', '2025-01-01 10:00:00', 3),
        [null, null, null],
        paimonRow('Weapon', 'Slingshot', '2025-01-01 10:00:01', 3),
      ],
    });
    expect(banners['200'], hasLength(2));
  });

  test('missing Information marker throws ForeignBundleException', () async {
    final wrongMarker = buildPaimonXlsx({
      'Standard': [paimonRow('Weapon', 'Cool Steel', '2025-01-01 10:00:00', 3)],
    }, marker: 'Something Else');
    await expectLater(
      importer.parse(wrongMarker),
      throwsA(isA<ForeignBundleException>()),
    );
    final noInformation = buildXlsx({
      'Standard': [paimonHeader],
    });
    await expectLater(
      importer.parse(noInformation),
      throwsA(isA<ForeignBundleException>()),
    );
  });

  test('bytes that are not xlsx throw FormatException', () async {
    await expectLater(
      importer.parse(Uint8List.fromList('not a zip'.codeUnits)),
      throwsFormatException,
    );
  });

  test('missing required column throws FormatException', () async {
    final bytes = buildXlsx({
      'Standard': [
        ['Type', 'Name', '⭐'],
        ['Weapon', 'Cool Steel', 3],
      ],
      'Information': [
        [paimonMarker],
      ],
    });
    await expectLater(importer.parse(bytes), throwsFormatException);
  });

  test('rank outside 1..5 throws FormatException', () async {
    final bytes = buildPaimonXlsx({
      'Standard': [paimonRow('Weapon', 'Cool Steel', '2025-01-01 10:00:00', 6)],
    });
    await expectLater(importer.parse(bytes), throwsFormatException);
  });

  test('unparsable time throws FormatException', () async {
    for (final time in ['2025/01/01 10:00:00', '2025-13-01 10:00:00', '']) {
      final bytes = buildPaimonXlsx({
        'Standard': [paimonRow('Weapon', 'Cool Steel', time, 3)],
      });
      await expectLater(
        importer.parse(bytes),
        throwsFormatException,
        reason: time,
      );
    }
  });

  test('unknown banner sheet throws FormatException', () async {
    final bytes = buildPaimonXlsx({
      'Mystery Wish': [
        paimonRow('Weapon', 'Cool Steel', '2025-01-01 10:00:00', 3),
      ],
    });
    await expectLater(importer.parse(bytes), throwsFormatException);
  });

  test('more than 100 rows in one second throws FormatException', () async {
    final bytes = buildPaimonXlsx({
      'Standard': [
        for (var i = 0; i < 101; i++)
          paimonRow('Weapon', 'Cool Steel', '2025-01-01 10:00:00', 3),
      ],
    });
    await expectLater(importer.parse(bytes), throwsFormatException);
  });

  test('assignTargetUid sets uid on storage and every record', () async {
    final bundle = await importer.parse(
      buildPaimonXlsx({
        'Character Event': [
          paimonRow('Weapon', 'Cool Steel', '2025-01-01 10:00:00', 3),
        ],
        'Standard': [
          paimonRow('Weapon', 'Slingshot', '2025-01-01 10:00:00', 3),
        ],
      }),
    );
    final assigned = assignTargetUid(bundle, '812345678');
    final storage = assigned.accounts.single.data;
    expect(storage.uid, '812345678');
    expect(assigned.lastActiveUid, '812345678');
    final records = storage.banners.values.expand((rs) => rs).toList();
    expect(records, hasLength(2));
    expect(records.every((r) => r.uid == '812345678'), isTrue);
    expect(
      records.map((r) => r.id),
      bundle.accounts.single.data.banners.values
          .expand((rs) => rs)
          .map((r) => r.id),
    );
    expect(assigned.schemaVersion, 2);
  });

  test('isValidUid', () {
    expect(isValidUid('812345678'), isTrue);
    expect(isValidUid('1812345678'), isTrue);
    expect(isValidUid('8123456'), isFalse);
    expect(isValidUid('81234567890'), isFalse);
    expect(isValidUid('81234567a'), isFalse);
    expect(isValidUid(''), isFalse);
  });

  test('parse result is an AccountsBundle with no last active uid', () async {
    final AccountsBundle bundle = await importer.parse(
      buildPaimonXlsx({
        'Standard': [
          paimonRow('Weapon', 'Cool Steel', '2025-01-01 10:00:00', 3),
        ],
      }),
    );
    expect(bundle.lastActiveUid, isNull);
  });
}
