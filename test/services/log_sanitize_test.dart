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

  group('sanitizeLogMessage', () {
    test('redacts authkey inside a rust mitm log line', () {
      const msg =
          'hit gacha endpoint: GET https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog?authkey_ver=1&sign_type=2&authkey=X%2bYD8cYuvO2c&game_biz=hk4e_global&gacha_type=301&region=os_asia&page=1';
      final out = sanitizeLogMessage(msg);
      expect(out, startsWith('hit gacha endpoint: GET https://'));
      expect(out, contains('authkey=***'));
      expect(out, contains('authkey_ver=***'));
      expect(out, contains('sign_type=***'));
      expect(out, contains('game_biz=***'));
      expect(out, contains('gacha_type=301'));
      expect(out, contains('region=os_asia'));
      expect(out, isNot(contains('X%2bYD8cYuvO2c')));
      expect(out, isNot(contains('XYD8cYuvO2c')));
    });

    test('returns message without url unchanged', () {
      expect(sanitizeLogMessage('capture started'), equals('capture started'));
      expect(
        sanitizeLogMessage('MITM session done, hasUrl=false'),
        equals('MITM session done, hasUrl=false'),
      );
    });

    test('sanitizes only the url segment, keeps trailing fields', () {
      final out = sanitizeLogMessage(
        'fetched url=https://x.example.com/y?authkey=SECRET&size=5 status=200',
      );
      expect(out, contains('authkey=***'));
      expect(out, contains('size=5'));
      expect(out, contains('status=200'));
      expect(out, isNot(contains('SECRET')));
    });

    test('leaves a contentless scheme token untouched (no match, no leak)', () {
      expect(
        sanitizeLogMessage('bad link https://'),
        equals('bad link https://'),
      );
    });

    test('sanitizes multiple urls in one message', () {
      final out = sanitizeLogMessage(
        'a https://h1.example.com/p?authkey=AAA b https://h2.example.com/q?authkey=BBB',
      );
      expect(out, isNot(contains('AAA')));
      expect(out, isNot(contains('BBB')));
      expect('authkey=***'.allMatches(out).length, equals(2));
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

  group('sanitizeFsPath', () {
    test('redacts Windows home directory username (backslash)', () {
      expect(
        sanitizeFsPath(r'C:\Users\Alice\Downloads\foo.json'),
        equals(r'C:\Users\***\Downloads\foo.json'),
      );
    });

    test('Windows home redaction is case-insensitive on drive letter', () {
      expect(
        sanitizeFsPath(r'd:\Users\Bob\file.log'),
        equals(r'd:\Users\***\file.log'),
      );
    });

    test('redacts macOS home directory username', () {
      expect(
        sanitizeFsPath('/Users/Alice/Downloads/foo.json'),
        equals('/Users/***/Downloads/foo.json'),
      );
    });

    test('redacts Linux home directory username', () {
      expect(
        sanitizeFsPath('/home/alice/Downloads/foo.json'),
        equals('/home/***/Downloads/foo.json'),
      );
    });

    test('passes through non-home Windows path unchanged', () {
      expect(
        sanitizeFsPath(r'C:\Tools\foo.json'),
        equals(r'C:\Tools\foo.json'),
      );
    });

    test('passes through non-home Unix path unchanged', () {
      expect(sanitizeFsPath('/tmp/foo.log'), equals('/tmp/foo.log'));
      expect(sanitizeFsPath('/var/log/x.log'), equals('/var/log/x.log'));
    });

    test('passes through empty string unchanged', () {
      expect(sanitizeFsPath(''), equals(''));
    });
  });
}
