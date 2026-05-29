import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_widget/markdown_widget.dart';

import 'package:genshin_impact_wish_gacha_analyzer/utils/github_release_linkify.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/release_notes_content.dart';

/// 蒐集目前畫面上所有 [RichText] 的純文字並串接，用來檢查渲染後的空白。
String _renderedText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final element in find.byType(RichText).evaluate()) {
    buffer.write((element.widget as RichText).text.toPlainText());
  }
  return buffer.toString();
}

void main() {
  testWidgets('連結後不應出現 markdown_widget 注入的多餘空格', (tester) async {
    final data = linkifyGithubReferences(
      'images by @GoneTone in '
      'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/pull/70',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBlock(
            data: data,
            config: releaseNotesMarkdownConfig(ThemeData.light()),
            generator: releaseNotesMarkdownGenerator(),
          ),
        ),
      ),
    );

    final text = _renderedText(tester);
    expect(text, contains('@GoneTone in #70'));
    expect(text, isNot(contains('@GoneTone  in')));
  });
}
