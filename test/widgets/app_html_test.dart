import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_html.dart';

void main() {
  testWidgets('純文字網址被渲染成連結文字', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppHtml(data: 'visit https://example.com now')),
      ),
    );
    // AppHtml 內部組一個 flutter_html 的 Html；連結文字應出現在 rich text 中。
    expect(find.byType(Html), findsOneWidget);
    expect(
      find.textContaining('https://example.com', findRichText: true),
      findsWidgets,
    );
  });
}
