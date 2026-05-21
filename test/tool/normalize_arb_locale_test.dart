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

  test('跳過缺 @@locale 的檔與非 arb 檔；重複執行為 0 變更', () {
    final dir = Directory.systemTemp.createTempSync('arb_normalize_skip_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    File('${dir.path}/app_xx.arb').writeAsStringSync('{\n  "foo": "bar"\n}');
    File('${dir.path}/README.md').writeAsStringSync('not an arb file');
    File(
      '${dir.path}/app_es.arb',
    ).writeAsStringSync('{\n  "@@locale": "es-ES"\n}');

    final first = normalizeArbLocales(dir);
    expect(first, 1, reason: '只有 app_es.arb 需正規化');

    // 缺 @@locale 的檔不動、非 arb 檔不動
    expect(
      File('${dir.path}/app_xx.arb').readAsStringSync(),
      '{\n  "foo": "bar"\n}',
    );
    expect(File('${dir.path}/README.md').readAsStringSync(), 'not an arb file');

    // 第二次執行：已正規化，0 變更
    final second = normalizeArbLocales(dir);
    expect(second, 0, reason: '已正規化的目錄重跑應為 0 變更');
  });
}
