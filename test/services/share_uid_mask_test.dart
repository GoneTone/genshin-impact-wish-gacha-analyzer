import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_uid_mask.dart';

void main() {
  group('maskUidForShare', () {
    test('顯示前 3 碼，其餘以 x 遮罩、長度保留', () {
      expect(maskUidForShare('123456789'), '123xxxxxx');
    });

    test('長度恰為 3 全可見', () {
      expect(maskUidForShare('123'), '123');
    });

    test('長度小於 3 全遮罩為固定 xxx', () {
      expect(maskUidForShare('12'), 'xxx');
      expect(maskUidForShare(''), 'xxx');
    });

    test('比 sanitizeUid 嚴格：不洩漏末碼', () {
      final masked = maskUidForShare('800123456');
      expect(masked.endsWith('456'), isFalse);
      expect(masked, '800xxxxxx');
    });
  });
}
