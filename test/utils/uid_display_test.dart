import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_uid_mask.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/uid_display.dart';

void main() {
  group('displayUid', () {
    test('returns original uid when mask=false', () {
      expect(displayUid('123456789', mask: false), '123456789');
    });

    test('returns masked uid when mask=true', () {
      expect(displayUid('123456789', mask: true), '123xxxxxx');
    });

    test('mask=true delegates to maskUidForShare', () {
      const uid = '987654321';
      expect(displayUid(uid, mask: true), maskUidForShare(uid));
    });

    test('handles empty string', () {
      expect(displayUid('', mask: true), 'xxx');
      expect(displayUid('', mask: false), '');
    });

    test('handles short uid (< 3 chars)', () {
      expect(displayUid('12', mask: true), 'xxx');
      expect(displayUid('12', mask: false), '12');
    });

    test('handles uid of exactly 3 chars', () {
      expect(displayUid('123', mask: true), '123');
      expect(displayUid('123', mask: false), '123');
    });
  });
}
