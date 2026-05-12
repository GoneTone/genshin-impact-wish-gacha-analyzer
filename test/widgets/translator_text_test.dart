import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/translator_text.dart';

void main() {
  group('parseTranslatorMarkup', () {
    test('純文字 → 單一 TextSegment', () {
      final segs = parseTranslatorMarkup('Alice, Bob');
      expect(segs, hasLength(1));
      expect(segs.first, isA<TextSegment>());
      expect((segs.first as TextSegment).text, 'Alice, Bob');
    });

    test('日文 ARB 實例：jj、<a>世界へいわ</a>', () {
      const raw =
          'jj、<a href="https://home.gamer.com.tw/homeindex.php?owner=XMoiswnX">世界へいわ</a>';
      final segs = parseTranslatorMarkup(raw);
      expect(segs, hasLength(2));
      expect((segs[0] as TextSegment).text, 'jj、');
      final link = segs[1] as LinkSegment;
      expect(link.text, '世界へいわ');
      expect(
        link.uri,
        Uri.parse('https://home.gamer.com.tw/homeindex.php?owner=XMoiswnX'),
      );
    });

    test('連結在開頭 → [Link, Text]', () {
      final segs = parseTranslatorMarkup('<a href="https://x.test">A</a> end');
      expect(segs, hasLength(2));
      expect(segs[0], isA<LinkSegment>());
      expect((segs[0] as LinkSegment).text, 'A');
      expect((segs[1] as TextSegment).text, ' end');
    });

    test('連續多個連結 → [Link, Text, Link]', () {
      final segs = parseTranslatorMarkup(
        '<a href="https://a.test">A</a>、<a href="https://b.test">B</a>',
      );
      expect(segs, hasLength(3));
      expect(segs[0], isA<LinkSegment>());
      expect((segs[1] as TextSegment).text, '、');
      expect(segs[2], isA<LinkSegment>());
    });

    test('標籤未閉合 → 整段純文字', () {
      const raw = '<a href="https://x.test">未閉合';
      final segs = parseTranslatorMarkup(raw);
      expect(segs, hasLength(1));
      expect((segs.first as TextSegment).text, raw);
    });

    test('巢狀標籤 → 整段純文字（不 match）', () {
      const raw = '<a href="https://x.test"><b>x</b></a>';
      final segs = parseTranslatorMarkup(raw);
      expect(segs, hasLength(1));
      expect((segs.first as TextSegment).text, raw);
    });

    test('javascript: scheme → 降為顯示文字', () {
      final segs = parseTranslatorMarkup('<a href="javascript:alert(1)">x</a>');
      expect(segs, hasLength(1));
      expect((segs.first as TextSegment).text, 'x');
    });

    test('無效 Uri → 降為顯示文字', () {
      final segs = parseTranslatorMarkup('<a href=":::">x</a>');
      expect(segs, hasLength(1));
      expect((segs.first as TextSegment).text, 'x');
    });

    test('空字串 → 空 list', () {
      expect(parseTranslatorMarkup(''), isEmpty);
    });
  });

  group('TranslatorText widget', () {
    testWidgets('含連結時：連結 span 有 underline 與 recognizer，純文字 span 沒有', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TranslatorText(
              raw: 'jj、<a href="https://example.test">世界へいわ</a>',
            ),
          ),
        ),
      );

      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byType(TranslatorText),
          matching: find.byType(RichText),
        ),
      );
      final root = richText.text as TextSpan;
      final spans = root.children!.cast<TextSpan>();

      final linkSpan = spans.firstWhere((s) => s.text == '世界へいわ');
      expect(linkSpan.style?.decoration, TextDecoration.underline);
      expect(linkSpan.recognizer, isNotNull);

      final textSpan = spans.firstWhere((s) => s.text == 'jj、');
      expect(textSpan.recognizer, isNull);
    });

    testWidgets('純文字輸入：所有 span 都沒有 recognizer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TranslatorText(raw: 'Alice, Bob')),
        ),
      );

      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byType(TranslatorText),
          matching: find.byType(RichText),
        ),
      );
      final root = richText.text as TextSpan;
      for (final span in root.children!.cast<TextSpan>()) {
        expect(span.recognizer, isNull);
      }
    });
  });
}
