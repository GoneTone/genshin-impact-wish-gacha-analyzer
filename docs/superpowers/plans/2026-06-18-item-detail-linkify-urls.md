# 物品詳情純文字網址自動連結化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓物品詳情 dialog 內的純文字 `http(s)` 網址自動變成可點擊連結（既有 `<a href>` 一併可點），點擊以系統瀏覽器開啟。

**Architecture:** 新增純函式 `linkifyHtml`（用 `html` DOM parser 只走訪 text node，把裸網址包成 `<a>`，跳過既有 `<a>` 子樹）；新增共用 `AppHtml` 元件（注入統一 `onLinkTap` 與靜態 primary 連結色）；抽出共用 `openExternalUrlString` helper；物品詳情 dialog 兩處 `Html` 改用 `AppHtml`。

**Tech Stack:** Flutter、`flutter_html: ^3.0.0`、`html: ^0.15.5`（DOM parser，原為 flutter_html 傳遞依賴，提升為顯式依賴）、`url_launcher`、`logging`。

## Global Constraints

- 回答／文件／註解／dartdoc／UI 文字用**繁體中文（台灣）全形標點**；commit message 與 PR 標題用英文半形、conventional commits 格式。
- 所有宣告（含 private `_xxx`）寫一行 `///` dartdoc（Flutter override 簽名自明者免）。
- 新功能在關鍵節點埋 `Logger('xxx').info/warning/severe(...)`，敏感資料先脫敏。
- Dialog 一律用 `AppDialog`（本計畫不新建 dialog，不涉及）。
- 偵測範圍**只**比對 `http://` 與 `https://` 開頭網址；不處理 `www.` 與裸網域。
- 行內連結採靜態 primary 色（`linkBaseColor`）+ 底線，**不做** hover 重新著色。
- 禁止重複造輪子：複用既有 `openExternalUrl`、`linkBaseColor`。
- 指令一律優先透過 `fvm` 執行。
- 提交前依序通過：`fvm dart format lib/ test/` → `fvm flutter analyze`（須 `No issues found!`）→ `fvm flutter test`（須 `All tests passed!`）。不要 `--no-verify`，不要主動 `git push`。

---

### Task 1: `linkifyHtml` 純函式 + `html` 依賴

把純文字 `http(s)` 裸網址改寫成 `<a href>`，是整個功能的核心邏輯，完整單元測試。

**Files:**
- Modify: `pubspec.yaml`（dependencies 區，在 `flutter_html: ^3.0.0` 之後加一行）
- Create: `lib/utils/html_linkify.dart`
- Test: `test/utils/html_linkify_test.dart`

**Interfaces:**
- Consumes: `package:html/dom.dart`（`Node`、`Element`、`Text`、`DocumentFragment.outerHtml`、`Element.tag`、`NodeList.insertAll/removeAt`）、`package:html/parser.dart`（`parseFragment`）。
- Produces: `String linkifyHtml(String html)` — 供 Task 3 的 `AppHtml` 使用。

- [ ] **Step 1: 加入 `html` 顯式依賴**

編輯 `pubspec.yaml`，在 `flutter_html: ^3.0.0` 那行之後新增：

```yaml
  flutter_html: ^3.0.0
  html: ^0.15.5
```

執行：`fvm flutter pub get`
預期：`Got dependencies!`（`html` 已是傳遞依賴，版本不變、不應有衝突）。

- [ ] **Step 2: 寫失敗測試**

建立 `test/utils/html_linkify_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/html_linkify.dart';

/// 計算 [out] 內 `<a ` 出現次數，用來驗證沒有產生多餘／巢狀連結。
int _anchorCount(String out) => '<a '.allMatches(out).length;

void main() {
  group('linkifyHtml', () {
    test('純文字 https 網址 → 包成 <a href>', () {
      final out = linkifyHtml('visit https://example.com now');
      expect(
        out,
        contains('<a href="https://example.com">https://example.com</a>'),
      );
      expect(_anchorCount(out), 1);
    });

    test('http 也會被連結化', () {
      final out = linkifyHtml('go http://foo.com');
      expect(out, contains('<a href="http://foo.com">http://foo.com</a>'));
    });

    test('ftp / www / 裸網域不被連結化', () {
      expect(_anchorCount(linkifyHtml('x ftp://foo.com y')), 0);
      expect(_anchorCount(linkifyHtml('visit www.foo.com')), 0);
      expect(_anchorCount(linkifyHtml('go to foo.com now')), 0);
    });

    test('尾端半形句點不吃進連結', () {
      final out = linkifyHtml('see https://foo.com.');
      expect(out, contains('<a href="https://foo.com">https://foo.com</a>'));
      expect(out, contains('</a>.'));
    });

    test('尾端全形句號不吃進連結', () {
      final out = linkifyHtml('詳見 https://foo.com。');
      expect(out, contains('<a href="https://foo.com">https://foo.com</a>'));
      expect(out, contains('</a>。'));
    });

    test('既有 <a href> 不被改、不雙重包覆', () {
      final out = linkifyHtml('<a href="https://x.com">link</a>');
      expect(out, contains('<a href="https://x.com">link</a>'));
      expect(_anchorCount(out), 1);
    });

    test('既有 <a> 內文是網址也不產生巢狀 <a>', () {
      final out = linkifyHtml('<a href="x">https://foo.com</a>');
      expect(_anchorCount(out), 1);
    });

    test('屬性值內的網址不被當文字連結化', () {
      final out = linkifyHtml('<img src="https://img.com/a.png">');
      expect(out, isNot(contains('<a')));
    });

    test('同段多個網址各自連結化', () {
      final out = linkifyHtml('a https://1.com b https://2.com');
      expect(_anchorCount(out), 2);
    });

    test('無網址純文字語意不變', () {
      expect(linkifyHtml('hello world'), 'hello world');
    });

    test('空字串回空字串', () {
      expect(linkifyHtml(''), '');
    });
  });
}
```

- [ ] **Step 3: 跑測試確認失敗**

執行：`fvm flutter test test/utils/html_linkify_test.dart`
預期：FAIL，`Error: ... 'linkifyHtml' isn't defined`（或 import 解析失敗）。

- [ ] **Step 4: 實作 `linkifyHtml`**

建立 `lib/utils/html_linkify.dart`：

```dart
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:logging/logging.dart';

/// [linkifyHtml] 的 logger。
final Logger _log = Logger('ui.linkify');

/// 比對 `http://` 或 `https://` 開頭的裸網址（延伸到空白或 `<` 為止）。
final RegExp _urlRe = RegExp(r'https?://[^\s<]+');

/// 連結尾端要剝除的標點（半形 + 全形），避免把句末標點吃進網址。
const String _trailingPunct = '.,;:!?)]}。，！？；：）」』】';

/// 把 [html] 內的純文字 `http(s)` 裸網址包成 `<a href>`，回傳改寫後的 HTML。
///
/// 用 DOM parser 只走訪 text node：既有 `<a>` 子樹整棵略過（不產生巢狀 `<a>`），
/// 屬性值（如 `href="…"`）因非 text node 也不會被誤改。解析或序列化意外失敗時
/// 回傳原字串（裸網址維持純文字、描述區不致渲染中斷）並記 warning。純函式、無副作用。
String linkifyHtml(String html) {
  if (html.isEmpty) return html;
  try {
    final fragment = html_parser.parseFragment(html);
    _linkifyNode(fragment);
    return fragment.outerHtml;
  } catch (e, st) {
    _log.warning(
      'linkifyHtml failed (len=${html.length}); returning original',
      e,
      st,
    );
    return html;
  }
}

/// 遞迴改寫 [node] 子節點：text node 內裸網址換成 `<a>`，`<a>` 子樹略過，其餘遞迴。
void _linkifyNode(Node node) {
  for (final child in List<Node>.from(node.nodes)) {
    if (child is Text) {
      final replacements = _linkifyText(child.data ?? '');
      if (replacements == null) continue;
      final idx = node.nodes.indexOf(child);
      node.nodes.removeAt(idx);
      node.nodes.insertAll(idx, replacements);
    } else if (child is Element) {
      if (child.localName == 'a') continue;
      _linkifyNode(child);
    }
  }
}

/// 把 [text] 拆成「文字／`<a>` 連結」節點序列；若無可連結網址回 null（呼叫端略過替換）。
List<Node>? _linkifyText(String text) {
  if (!_urlRe.hasMatch(text)) return null;
  final nodes = <Node>[];
  var last = 0;
  for (final m in _urlRe.allMatches(text)) {
    var url = m.group(0)!;
    var end = m.end;
    while (url.isNotEmpty && _trailingPunct.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
      end--;
    }
    if (url.isEmpty) continue;
    if (m.start > last) nodes.add(Text(text.substring(last, m.start)));
    nodes.add(
      Element.tag('a')
        ..attributes['href'] = url
        ..append(Text(url)),
    );
    last = end;
  }
  if (nodes.isEmpty) return null;
  if (last < text.length) nodes.add(Text(text.substring(last)));
  return nodes;
}
```

- [ ] **Step 5: 跑測試確認通過**

執行：`fvm flutter test test/utils/html_linkify_test.dart`
預期：PASS，全部 11 個測試綠燈。

- [ ] **Step 6: 品質檢查 + commit**

```bash
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
git add pubspec.yaml pubspec.lock lib/utils/html_linkify.dart test/utils/html_linkify_test.dart
git commit -m "feat(item-detail): add linkifyHtml to wrap bare http(s) URLs in anchors"
```

預期：`analyze` 輸出 `No issues found!`；`test` 輸出 `All tests passed!`。

---

### Task 2: 抽出 `openExternalUrlString` 共用 helper

把「字串 → Uri → 開啟」的解析防呆抽成共用函式，供 `AppLink` 與後續 `AppHtml` 的 `onLinkTap` 共用，消除重複樣板。

**Files:**
- Modify: `lib/widgets/app_link.dart`
- Test: `test/widgets/app_link_test.dart`

**Interfaces:**
- Consumes: 既有 `Future<void> openExternalUrl(Uri uri)`（同檔）。
- Produces: `Future<void> openExternalUrlString(String? url)` — 供 Task 3 的 `AppHtml.onLinkTap` 使用。

- [ ] **Step 1: 寫失敗測試**

建立 `test/widgets/app_link_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

void main() {
  group('openExternalUrlString', () {
    test('null URL 不丟例外、靜默返回', () async {
      // onLinkTap 可能傳入 null；此分支不應觸碰 url_launcher 平台。
      await expectLater(openExternalUrlString(null), completes);
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

執行：`fvm flutter test test/widgets/app_link_test.dart`
預期：FAIL，`'openExternalUrlString' isn't defined`。

- [ ] **Step 3: 新增 helper 並重構 `_handleTap`**

在 `lib/widgets/app_link.dart` 的 `openExternalUrl` 之上新增：

```dart
/// 解析 [url] 並以系統瀏覽器開啟；[url] 為 null 或無法解析時記 warning 並靜默返回。
///
/// 供 [AppLink] 與 flutter_html 的 `onLinkTap`（其回傳可能為 null）共用，統一
/// 「字串 → Uri → 開啟」的解析與防呆。
Future<void> openExternalUrlString(String? url) async {
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri == null) {
    Logger('ui.link').warning('openExternalUrlString: invalid url "$url"');
    return;
  }
  await openExternalUrl(uri);
}
```

把 `_AppLinkState._handleTap` 改為複用該 helper：

```dart
  /// 解析並開啟 [widget.url]；URL 無效時記錄 warning。
  Future<void> _handleTap() => openExternalUrlString(widget.url);
```

- [ ] **Step 4: 跑測試確認通過**

執行：`fvm flutter test test/widgets/app_link_test.dart`
預期：PASS。

- [ ] **Step 5: 品質檢查 + commit**

```bash
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
git add lib/widgets/app_link.dart test/widgets/app_link_test.dart
git commit -m "refactor(link): extract openExternalUrlString helper shared by AppLink and onLinkTap"
```

預期：`No issues found!` 與 `All tests passed!`。

---

### Task 3: `AppHtml` 共用元件

把 `linkifyHtml` 與 `openExternalUrlString` 串成可重用的 HTML 渲染元件，統一連結色與點擊行為。

**Files:**
- Create: `lib/widgets/app_html.dart`
- Test: `test/widgets/app_html_test.dart`

**Interfaces:**
- Consumes: `String linkifyHtml(String html)`（Task 1）、`Future<void> openExternalUrlString(String? url)`（Task 2）、`Color linkBaseColor(ThemeData theme)`（既有 `app_link.dart`）、`flutter_html` 的 `Html`／`Style`／`OnTap`。
- Produces: `class AppHtml`（`const AppHtml({Key? key, required String data, Map<String, Style> style})`）— 供 Task 4 取代 dialog 內的 `Html`。

- [ ] **Step 1: 寫失敗測試**

建立 `test/widgets/app_html_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_html.dart';

void main() {
  testWidgets('純文字網址被渲染成連結文字', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppHtml(data: 'visit https://example.com now'),
        ),
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
```

- [ ] **Step 2: 跑測試確認失敗**

執行：`fvm flutter test test/widgets/app_html_test.dart`
預期：FAIL，`'AppHtml' isn't defined` / `app_html.dart` 不存在。

- [ ] **Step 3: 實作 `AppHtml`**

建立 `lib/widgets/app_html.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'package:genshin_impact_wish_gacha_analyzer/utils/html_linkify.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

/// 渲染 HTML 的共用元件：自動把純文字 `http(s)` 網址轉成可點連結（含內容既有的
/// `<a href>`），點擊以系統瀏覽器開啟。
///
/// 連結採全應用統一的靜態 primary 連結色（[linkBaseColor]）+ 底線，對齊既有行內
/// 連結風格；不做 per-link hover。呼叫端可透過 [style] 覆蓋 `body`／`p` 等標籤樣式
/// （疊在預設 `a` 樣式之後）。
class AppHtml extends StatelessWidget {
  /// 建立 [AppHtml]。[data] 為 HTML 字串；[style] 為額外的 flutter_html 標籤樣式。
  const AppHtml({super.key, required this.data, this.style = const {}});

  /// 要渲染的 HTML 內容。
  final String data;

  /// 額外的標籤樣式覆寫（疊在預設 `a` 樣式之後）。
  final Map<String, Style> style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Html(
      data: linkifyHtml(data),
      onLinkTap: (url, _, __) => unawaited(openExternalUrlString(url)),
      style: {
        'a': Style(
          color: linkBaseColor(theme),
          textDecoration: TextDecoration.underline,
        ),
        ...style,
      },
    );
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

執行：`fvm flutter test test/widgets/app_html_test.dart`
預期：PASS。

- [ ] **Step 5: 品質檢查 + commit**

```bash
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
git add lib/widgets/app_html.dart test/widgets/app_html_test.dart
git commit -m "feat(widgets): add AppHtml wrapper with linkified URLs and unified link tap"
```

預期：`No issues found!` 與 `All tests passed!`。

---

### Task 4: 物品詳情 dialog 兩處 `Html` 改用 `AppHtml`

把標題區 `desc` 與圖片區 `descHtml` 兩處渲染換成 `AppHtml`，讓詳情內容的純文字網址可點。

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`（import 區；標題區 `desc` 的 `Html`（約 615 行）；圖片區 `descHtml` 的 `Html`（約 698 行））

**Interfaces:**
- Consumes: `class AppHtml`（Task 3）。
- Produces: 無新對外介面（行為變更）。

- [ ] **Step 1: 新增 import**

在 `lib/widgets/dialogs/gacha_item_detail_dialog.dart` 既有 import 區，於 `app_link.dart` import 之後加入（維持既有匯入排列）：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_html.dart';
```

- [ ] **Step 2: 標題區 `desc` 改用 `AppHtml`**

把標題區（約 615-630 行）原本的：

```dart
                      child: Html(
                        data: desc,
                        style: {
                          'body': Style(
                            fontSize: FontSize(
                              theme.textTheme.bodyMedium?.fontSize ?? 14,
                            ),
                            lineHeight: LineHeight.number(1.2),
                            color: tokens.textSecondary,
                            margin: Margins.zero,
                            padding: HtmlPaddings.zero,
                          ),
                          'p': Style(margin: Margins.zero),
                        },
                      ),
```

改為（只把 `Html` 換成 `AppHtml`，`style` map 原樣保留）：

```dart
                      child: AppHtml(
                        data: desc,
                        style: {
                          'body': Style(
                            fontSize: FontSize(
                              theme.textTheme.bodyMedium?.fontSize ?? 14,
                            ),
                            lineHeight: LineHeight.number(1.2),
                            color: tokens.textSecondary,
                            margin: Margins.zero,
                            padding: HtmlPaddings.zero,
                          ),
                          'p': Style(margin: Margins.zero),
                        },
                      ),
```

- [ ] **Step 3: 圖片區 `descHtml` 改用 `AppHtml`**

把圖片區（約 698-704 行）原本的：

```dart
            Html(
              data: current.descHtml,
              style: {
                'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
                'p': Style(margin: Margins.symmetric(vertical: 4)),
              },
            ),
```

改為：

```dart
            AppHtml(
              data: current.descHtml,
              style: {
                'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
                'p': Style(margin: Margins.symmetric(vertical: 4)),
              },
            ),
```

> 註：保留 `flutter_html` 的 import — `Style`、`Margins`、`HtmlPaddings`、`FontSize`、`LineHeight` 仍由它提供。

- [ ] **Step 4: 跑既有 dialog 測試確認無回歸**

執行：`fvm flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart test/widgets/dialogs/gacha_item_detail_dialog_lazy_test.dart`
預期：PASS。既有 `find.byType(Html)` 斷言（約 328、351 行）仍命中 `AppHtml` 內層的 `Html`，毋須改測試；若有 finder 失敗則為真實回歸，需調查。

- [ ] **Step 5: 全套品質檢查 + commit**

```bash
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
git add lib/widgets/dialogs/gacha_item_detail_dialog.dart
git commit -m "feat(item-detail): render desc and gallery descriptions via AppHtml to linkify URLs"
```

預期：`No issues found!` 與 `All tests passed!`。

---

## Self-Review

**1. Spec coverage**
- 偵測範圍只 http/https → Task 1 regex `https?://`，測試涵蓋 ftp/www/裸網域不中。✓
- 裸 URL 與既有 `<a>` 都可點 → Task 1 跳過 `<a>` 子樹 + Task 3 `onLinkTap` 全域生效。✓
- 行內連結靜態 primary 色、無 hover → Task 3 `'a': Style(color: linkBaseColor, underline)`。✓
- 適用兩處（desc + descHtml）→ Task 4 兩個 site。✓
- parser-based、fail-safe 回原字串 + log → Task 1 `try/catch` + `_log.warning`。✓
- 複用 `openExternalUrl` → Task 2 抽 `openExternalUrlString` 委派之。✓
- 尾端標點剝除（半/全形）→ Task 1 `_trailingPunct` + 兩個測試。✓
- `html` 提升顯式依賴 → Task 1 Step 1。✓
- 測試（linkify 單元 / AppHtml widget / dialog 無回歸）→ Task 1／3／4。✓

**2. Placeholder scan**：無 TBD／TODO／「類似 Task N」；每個改碼步驟都附完整程式碼。✓

**3. Type consistency**：`linkifyHtml(String) → String`、`openExternalUrlString(String?) → Future<void>`、`AppHtml({required String data, Map<String, Style> style})` 在定義（Task 1/2/3）與使用（Task 3/4）處一致。`onLinkTap` 簽名 `(String? url, Map<String,String>, Element?)` 對齊 flutter_html `OnTap`。✓
