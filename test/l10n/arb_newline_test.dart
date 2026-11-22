import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 掃描所有 ARB 字串值，找出把換行寫成字面反斜線加 n 的項目（畫面會直接顯示「\n」）。
void main() {
  test('ARB 字串值不含字面的反斜線加 n', () {
    final literal = String.fromCharCodes([0x5C, 0x6E]);
    final offenders = <String>[];
    for (final file in Directory('lib/l10n').listSync().whereType<File>()) {
      if (!file.path.endsWith('.arb')) continue;
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final e in data.entries) {
        final v = e.value;
        if (!e.key.startsWith('@') && v is String && v.contains(literal)) {
          offenders.add('${file.uri.pathSegments.last}: ${e.key}');
        }
      }
    }
    expect(offenders, isEmpty, reason: r'字面 \n 應改成真正換行');
  });
}
