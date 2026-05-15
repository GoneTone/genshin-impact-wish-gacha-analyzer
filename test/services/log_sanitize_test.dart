import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

void main() {
  group('sanitizeUrl', () {
    test('redacts authkey', () {
      final out = sanitizeUrl(
        'https://hk4e-api.example.com/event?authkey=ABCDEF&end_id=0',
      );
      expect(out, contains('authkey=***'));
      expect(out, contains('end_id=0'));
      expect(out, isNot(contains('ABCDEF')));
    });

    test('redacts all sensitive keys simultaneously', () {
      final out = sanitizeUrl(
        'https://x.example.com/y?authkey=A&authkey_ver=1&sign_type=2&game_biz=hk4e_global&gacha_type=301',
      );
      expect(out, contains('authkey=***'));
      expect(out, contains('authkey_ver=***'));
      expect(out, contains('sign_type=***'));
      expect(out, contains('game_biz=***'));
      expect(out, contains('gacha_type=301'));
    });

    test('keeps non-sensitive query params untouched', () {
      final out = sanitizeUrl(
        'https://x.example.com/y?gacha_type=301&end_id=0&size=20',
      );
      expect(out, contains('gacha_type=301'));
      expect(out, contains('end_id=0'));
      expect(out, contains('size=20'));
    });

    test('returns marker on malformed url', () {
      expect(sanitizeUrl('not a url ##'), equals('<malformed url>'));
    });

    test('handles url with no query string', () {
      final out = sanitizeUrl('https://x.example.com/y');
      expect(out, equals('https://x.example.com/y'));
    });
  });

  group('sanitizeUid', () {
    test('masks middle of long uid', () {
      expect(sanitizeUid('186123456'), equals('186****456'));
    });

    test('masks very long uid', () {
      expect(sanitizeUid('1234567890'), equals('123****890'));
    });

    test('masks at exact length-6 boundary', () {
      expect(sanitizeUid('123456'), equals('123****456'));
    });

    test('returns full mask for short uid', () {
      expect(sanitizeUid('12345'), equals('***'));
    });

    test('returns full mask for empty', () {
      expect(sanitizeUid(''), equals('***'));
    });
  });
}
