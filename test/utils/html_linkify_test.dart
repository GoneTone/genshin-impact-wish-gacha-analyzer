import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/html_linkify.dart';

/// 計算 [out] 內 `<a ` 出現次數，用來驗證沒有產生多餘／巢狀連結。
int _anchorCount(String out) => '<a '.allMatches(out).length;

void main() {
  group('linkifyHtml', () {
    test('純文字 https 網址 → 包成 <a href>', () {
      final out = linkifyHtml('visit https://example.com now');
      expect(
        out,
        contains('<a href="https://example.com">https://example.com</a>'),
      );
      expect(_anchorCount(out), 1);
    });

    test('http 也會被連結化', () {
      final out = linkifyHtml('go http://foo.com');
      expect(out, contains('<a href="http://foo.com">http://foo.com</a>'));
    });

    test('ftp / www / 裸網域不被連結化', () {
      expect(_anchorCount(linkifyHtml('x ftp://foo.com y')), 0);
      expect(_anchorCount(linkifyHtml('visit www.foo.com')), 0);
      expect(_anchorCount(linkifyHtml('go to foo.com now')), 0);
    });

    test('尾端半形句點不吃進連結', () {
      final out = linkifyHtml('see https://foo.com.');
      expect(out, contains('<a href="https://foo.com">https://foo.com</a>'));
      expect(out, contains('</a>.'));
    });

    test('尾端全形句號不吃進連結', () {
      final out = linkifyHtml('詳見 https://foo.com。');
      expect(out, contains('<a href="https://foo.com">https://foo.com</a>'));
      expect(out, contains('</a>。'));
    });

    test('既有 <a href> 不被改、不雙重包覆', () {
      final out = linkifyHtml('<a href="https://x.com">link</a>');
      expect(out, contains('<a href="https://x.com">link</a>'));
      expect(_anchorCount(out), 1);
    });

    test('既有 <a> 內文是網址也不產生巢狀 <a>', () {
      final out = linkifyHtml('<a href="x">https://foo.com</a>');
      expect(_anchorCount(out), 1);
    });

    test('屬性值內的網址不被當文字連結化', () {
      final out = linkifyHtml('<img src="https://img.com/a.png">');
      expect(out, isNot(contains('<a')));
    });

    test('同段多個網址各自連結化', () {
      final out = linkifyHtml('a https://1.com b https://2.com');
      expect(_anchorCount(out), 2);
    });

    test('無網址純文字語意不變', () {
      expect(linkifyHtml('hello world'), 'hello world');
    });

    test('空字串回空字串', () {
      expect(linkifyHtml(''), '');
    });
  });
}
