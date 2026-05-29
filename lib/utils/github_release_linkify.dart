import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';

/// 把 [s] 內的 regex 特殊字元跳脫，使其可安全嵌入 [RegExp] pattern 作為字面值。
String _escapeRegExp(String s) =>
    s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}');

/// 本專案 repo 網址前綴（已 regex 跳脫），供各連結 pattern 共用。
final String _repo = _escapeRegExp(AppRepo.githubUrl);

/// 比對本 repo PR 連結，捕捉群組 1 為 PR 編號。
final RegExp _prRe = RegExp('(?<![(<])$_repo/pull/(\\d+)');

/// 比對本 repo Issue 連結，捕捉群組 1 為 Issue 編號。
final RegExp _issueRe = RegExp('(?<![(<])$_repo/issues/(\\d+)');

/// 比對本 repo compare 連結，捕捉群組 1 為比較區間（例 `v1.0.0...v1.1.0`）。
final RegExp _compareRe = RegExp('(?<![(<])$_repo/compare/([^\\s)]+)');

/// 比對本 repo commit 連結，捕捉群組 1 為 7～40 碼 SHA。
final RegExp _commitRe = RegExp('(?<![(<])$_repo/commit/([0-9a-fA-F]{7,40})');

/// 比對 `@提及`：群組 1 為使用者名（GitHub 命名規則），群組 2 為可選的
/// `[bot]` 後綴。前置 negative lookbehind 擋掉 email／路徑樣式。
final RegExp _mentionRe = RegExp(
  r'(?<![A-Za-z0-9._%+@/-])@([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)(\[bot\])?',
);

/// 把 release notes Markdown [body] 內本專案的 GitHub 連結與 `@提及`，改寫成
/// 與 GitHub 網頁一致的精簡顯示樣式：PR/Issue → `#N`、compare → 比較區間、
/// commit → 前 7 碼短 SHA、`@user` → 使用者連結（`[bot]` → app 連結）。
///
/// 純字串轉換、無副作用，供呈現層在丟給 Markdown 渲染器前呼叫；不更動來源
/// 資料。已是 `[文字](url)` 或 `<url>` 形式的網址不會被重複包裝。
String linkifyGithubReferences(String body) {
  var out = body;
  out = out.replaceAllMapped(_prRe, (m) => '[#${m[1]}](${m[0]})');
  out = out.replaceAllMapped(_issueRe, (m) => '[#${m[1]}](${m[0]})');
  out = out.replaceAllMapped(_compareRe, (m) => '[${m[1]}](${m[0]})');
  out = out.replaceAllMapped(
    _commitRe,
    (m) => '[${m[1]!.substring(0, 7)}](${m[0]})',
  );
  out = out.replaceAllMapped(_mentionRe, (m) {
    final name = m[1]!;
    return m[2] != null
        ? '[@$name[bot]](https://github.com/apps/$name)'
        : '[@$name](https://github.com/$name)';
  });
  return out;
}
