import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// gen-l10n 把 `=1{}` 編成 CLDR 的 `one`，而 pt、pt_BR、fr 的 `one` 包含 0，
/// 所以這些語言的 `=1{}`／`one{}` 分支一定要用該 plural 自己的佔位符，
/// 寫死「1」或「um」時 0 會顯示成 1。
void main() {
  /// 回傳 [text] 裡每個 plural 的變數名，以及它最外層 `=1{...}`／`one{...}` 分支的內容。
  List<(String, String)> oneBranches(String text) {
    final result = <(String, String)>[];
    final selector = RegExp(r'(?:=1|one)\s*\{');
    for (final plural in RegExp(r'\{(\w+),\s*plural,').allMatches(text)) {
      var depth = 1;
      var i = plural.end;
      while (i < text.length && depth > 0) {
        final branch = depth == 1 ? selector.matchAsPrefix(text, i) : null;
        if (branch != null) {
          var inner = 1;
          var j = branch.end;
          while (j < text.length && inner > 0) {
            if (text[j] == '{') inner++;
            if (text[j] == '}') inner--;
            j++;
          }
          result.add((plural.group(1)!, text.substring(branch.end, j - 1)));
          i = j;
          continue;
        }
        if (text[i] == '{') depth++;
        if (text[i] == '}') depth--;
        i++;
      }
    }
    return result;
  }

  for (final locale in ['pt', 'pt_BR', 'fr']) {
    test('$locale 的 =1／one 分支都用自己的佔位符', () {
      final arb =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;
      final offenders = [
        for (final MapEntry(:key, :value) in arb.entries)
          if (!key.startsWith('@') &&
              value is String &&
              oneBranches(
                value,
              ).any((branch) => !branch.$2.contains('{${branch.$1}}')))
            key,
      ];
      expect(offenders, isEmpty);
    });
  }
}
