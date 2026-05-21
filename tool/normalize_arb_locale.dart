import 'dart:io';

/// CLI 進入點：正規化 `lib/l10n` 下所有 `app_*.arb` 的 `@@locale`。
void main() {
  final count = normalizeArbLocales(Directory('lib/l10n'));
  stdout.writeln('done, $count file(s) normalized');
}

/// 把 [dir] 下每個 `app_<locale>.arb` 的 `@@locale` 值改成檔名衍生的 `<locale>`
/// （`app_zh_Hans.arb` → `zh_Hans`、`app_es.arb` → `es`），使其符合 Flutter
/// gen-l10n 對「`@@locale` 須與檔名一致」的要求。回傳實際改寫的檔案數。
///
/// 只重寫 `@@locale` 那一段、保留其餘格式，避免整檔重排造成大 diff。本函式
/// 僅用 `dart:io`、無套件相依，故可在 `flutter pub get`（會觸發 gen-l10n）之前執行。
int normalizeArbLocales(Directory dir) {
  final pattern = RegExp(r'("@@locale"\s*:\s*")([^"]*)(")');
  var changed = 0;
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (!name.startsWith('app_') || !name.endsWith('.arb')) continue;
    final locale = name.substring('app_'.length, name.length - '.arb'.length);
    final content = entity.readAsStringSync();
    final match = pattern.firstMatch(content);
    if (match == null) {
      stderr.writeln('WARN: $name has no @@locale key');
      continue;
    }
    if (match.group(2) == locale) continue;
    entity.writeAsStringSync(
      content.replaceFirstMapped(pattern, (m) => '${m[1]}$locale${m[3]}'),
    );
    stdout.writeln('normalized $name: ${match.group(2)} -> $locale');
    changed++;
  }
  return changed;
}
