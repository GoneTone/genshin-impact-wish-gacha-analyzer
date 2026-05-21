import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/normalize_arb_locale.dart';

void main() {
  test('normalizeArbLocales 把 @@locale 改成檔名衍生 locale、已正確者不動', () {
    final dir = Directory.systemTemp.createTempSync('arb_normalize_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    File(
      '${dir.path}/app_es.arb',
    ).writeAsStringSync('{\n  "@@locale": "es-ES",\n  "x": "y"\n}');
    File(
      '${dir.path}/app_zh_Hans.arb',
    ).writeAsStringSync('{\n  "@@locale": "zh-CN"\n}');
    File(
      '${dir.path}/app_en.arb',
    ).writeAsStringSync('{\n  "@@locale": "en"\n}');

    final changed = normalizeArbLocales(dir);

    expect(changed, 2);
    expect(
      File('${dir.path}/app_es.arb').readAsStringSync(),
      contains('"@@locale": "es"'),
    );
    expect(
      File('${dir.path}/app_es.arb').readAsStringSync(),
      contains('"x": "y"'),
    );
    expect(
      File('${dir.path}/app_zh_Hans.arb').readAsStringSync(),
      contains('"@@locale": "zh_Hans"'),
    );
    expect(
      File('${dir.path}/app_en.arb').readAsStringSync(),
      contains('"@@locale": "en"'),
    );
  });
}
