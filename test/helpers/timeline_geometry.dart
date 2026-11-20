import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 依樹順序收集 [root] 底下所有文字、節點圓（22×22 halo）與帶左框線的容器（月份分隔線、
/// 卡片外框）的 `Rect`，用來鎖住時間軸的版面；落在 [exclude] 內的文字不列入。
List<(String, Rect)> timelineGeometry(
  WidgetTester tester,
  Finder root, {
  Finder? exclude,
}) {
  Rect rectOf(Element e) =>
      tester.getRect(find.byElementPredicate((x) => x == e));
  final excluded = exclude == null
      ? const <Element>{}
      : tester
            .elementList(
              find.descendant(of: exclude, matching: find.byType(RichText)),
            )
            .toSet();
  bool hasLeftBorder(Widget w) {
    if (w is! Container || w.decoration is! BoxDecoration) return false;
    final decoration = w.decoration! as BoxDecoration;
    final border = decoration.border;
    return decoration.shape == BoxShape.rectangle &&
        border is Border &&
        border.left != BorderSide.none;
  }

  return [
    for (final e in tester.elementList(
      find.descendant(of: root, matching: find.byType(RichText)),
    ))
      if (!excluded.contains(e))
        ((e.widget as RichText).text.toPlainText(), rectOf(e)),
    for (final e in tester.elementList(
      find.descendant(
        of: root,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints ==
                  const BoxConstraints.tightFor(width: 22, height: 22),
        ),
      ),
    ))
      ('node', rectOf(e)),
    for (final e in tester.elementList(
      find.descendant(
        of: root,
        matching: find.byWidgetPredicate(hasLeftBorder),
      ),
    ))
      ('border', rectOf(e)),
  ];
}
