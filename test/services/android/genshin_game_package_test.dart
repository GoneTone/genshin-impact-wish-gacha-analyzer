import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/genshin_game_package.dart';

void main() {
  test('only global genshin impact package names are accepted', () {
    for (final ok in [
      genshinGlobalPackage,
      genshinPackagePrefix,
      '$genshinPackagePrefix.samsung',
      '$genshinPackagePrefix.store_2',
    ]) {
      expect(isGenshinPackage(ok), isTrue, reason: ok);
    }
    for (final bad in [
      'com.miHoYo.Yuanshen',
      'com.miHoYo.GenshinImpactX',
      "$genshinPackagePrefix.x'; rm -rf /",
      '$genshinPackagePrefix.x y',
      '$genshinPackagePrefix.x;y',
      '$genshinPackagePrefix.',
      '$genshinPackagePrefix.a/b',
      '',
    ]) {
      expect(isGenshinPackage(bad), isFalse, reason: bad);
    }
  });

  test('known versions come first, others sorted, duplicates dropped', () {
    expect(
      sortGenshinPackages([
        '$genshinPackagePrefix.zz',
        'com.example.other',
        '$genshinPackagePrefix.aa',
        genshinGlobalPackage,
        '$genshinPackagePrefix.aa',
      ]),
      [
        genshinGlobalPackage,
        '$genshinPackagePrefix.aa',
        '$genshinPackagePrefix.zz',
      ],
    );
  });
}
