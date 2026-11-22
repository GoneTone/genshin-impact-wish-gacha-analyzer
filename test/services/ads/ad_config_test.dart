import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/ads/ad_config.dart';

void main() {
  group('resolveNativeUnitId', () {
    test('release 且有注入時使用注入值', () {
      expect(resolveNativeUnitId(release: true, injected: 'x'), 'x');
    });

    test('release 但未注入時退回測試 ID', () {
      expect(
        resolveNativeUnitId(release: true, injected: ''),
        kTestAdmobNativeUnitId,
      );
    });

    test('非 release 一律使用測試 ID', () {
      expect(
        resolveNativeUnitId(release: false, injected: 'x'),
        kTestAdmobNativeUnitId,
      );
    });
  });
}
