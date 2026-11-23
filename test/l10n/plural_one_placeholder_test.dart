import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// gen-l10n 把 `=1{}` 編成 CLDR 的 `one`，而 pt、pt_BR、fr 的 `one` 包含 0，
/// 所以這些語言的 `=1{}`／`one{}` 分支一定要用佔位符，寫死「1」或「um」時 0 會顯示成 1。
void main() {
  /// 回傳 [text] 裡所有 `=1{...}`／`one{...}` 分支的內容（依大括號配對）。
  List<String> oneBranches(String text) {
    final bodies = <String>[];
    for (final match in RegExp(r'(?:=1|\bone)\s*\{').allMatches(text)) {
      var depth = 1;
      var i = match.end;
      while (i < text.length && depth > 0) {
        if (text[i] == '{') depth++;
        if (text[i] == '}') depth--;
        i++;
      }
      bodies.add(text.substring(match.end, i - 1));
    }
    return bodies;
  }

  for (final locale in ['pt', 'pt_BR', 'fr']) {
    test('$locale 的 =1／one 分支都有佔位符', () {
      final arb =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;
      final offenders = [
        for (final MapEntry(:key, :value) in arb.entries)
          if (!key.startsWith('@') &&
              value is String &&
              value.contains('plural') &&
              oneBranches(value).any((body) => !body.contains('{')))
            key,
      ];
      expect(offenders, isEmpty);
    });
  }
}
