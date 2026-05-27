# localeTranslator HTML 顯示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `localeTranslator` 在設定頁 About 區塊把 `<a href="...">text</a>` 渲染為可點擊的超連結，點擊後用系統預設瀏覽器開啟。

**Architecture:** 新增 `TranslatorText` widget，內部用純函式 `parseTranslatorMarkup` 將原字串拆成 `TextSegment` / `LinkSegment`，組成 `Text.rich`。連結 `TextSpan` 透過 `TapGestureRecognizer` 呼叫 `url_launcher` 開啟 URL。只支援 `<a href>` 一種標籤；只用於 About 譯者署名一處。

**Tech Stack:** Flutter、Dart 3 sealed class、`url_launcher: ^6.3.2`、`flutter_test`。

**Spec：** `docs/superpowers/specs/2026-05-12-locale-translator-html-design.md`（同樣不進版控，但內含完整設計依據）。

**CLAUDE.md 規範：** 每個 task 的 commit 前必跑：
1. `dart format lib/ test/`
2. `flutter analyze` → `No issues found!`
3. `flutter test` → `All tests passed!`

---

## Task 1：加入 `url_launcher` 依賴

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 在 `dependencies` 區加入 url_launcher**

在 `pubspec.yaml` 的 `dependencies:` 區、`screen_retriever: ^0.2.0` 後面加上：

```yaml
  url_launcher: ^6.3.2
```

加完後 dependencies 區應像這樣（節錄）：

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  flutter_rust_bridge: ^2.12.0
  ffi: ^2.2.0
  flutter_riverpod: ^3.0.0
  go_router: ^17.0.0
  http: ^1.2.0
  path_provider: ^2.1.0
  shared_preferences: ^2.3.0
  file_selector: ^1.0.0
  fl_chart: ^1.0.0
  intl: ^0.20.0
  package_info_plus: ^10.0.0
  window_manager: ^0.5.1
  screen_retriever: ^0.2.0
  url_launcher: ^6.3.2
```

- [ ] **Step 2: 安裝套件**

Run: `flutter pub get`
Expected: 出現 `Got dependencies!` 且無錯誤。`pubspec.lock` 會被更新。

- [ ] **Step 3: 確認既有測試仍通過**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build: add url_launcher dependency for translator credit links"
```

---

## Task 2：實作 `parseTranslatorMarkup` 純函式（TDD）

**Files:**
- Create: `lib/widgets/translator_text.dart`（先只放 segment 型別與 parse 函式，widget 留到 Task 3）
- Create: `test/widgets/translator_text_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/widgets/translator_text_test.dart`：

```dart
// test/widgets/translator_text_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/translator_text.dart';

void main() {
  group('parseTranslatorMarkup', () {
    test('純文字 → 單一 TextSegment', () {
      final segs = parseTranslatorMarkup('Alice, Bob');
      expect(segs, hasLength(1));
      expect(segs.first, isA<TextSegment>());
      expect((segs.first as TextSegment).text, 'Alice, Bob');
    });

    test('日文 ARB 實例：jj、<a>世界へいわ</a>', () {
      const raw =
          'jj、<a href="https://home.gamer.com.tw/homeindex.php?owner=XMoiswnX">世界へいわ</a>';
      final segs = parseTranslatorMarkup(raw);
      expect(segs, hasLength(2));
      expect((segs[0] as TextSegment).text, 'jj、');
      final link = segs[1] as LinkSegment;
      expect(link.text, '世界へいわ');
      expect(
        link.uri,
        Uri.parse(
          'https://home.gamer.com.tw/homeindex.php?owner=XMoiswnX',
        ),
      );
    });

    test('連結在開頭 → [Link, Text]', () {
      final segs = parseTranslatorMarkup('<a href="https://x.test">A</a> end');
      expect(segs, hasLength(2));
      expect(segs[0], isA<LinkSegment>());
      expect((segs[0] as LinkSegment).text, 'A');
      expect((segs[1] as TextSegment).text, ' end');
    });

    test('連續多個連結 → [Link, Text, Link]', () {
      final segs = parseTranslatorMarkup(
        '<a href="https://a.test">A</a>、<a href="https://b.test">B</a>',
      );
      expect(segs, hasLength(3));
      expect(segs[0], isA<LinkSegment>());
      expect((segs[1] as TextSegment).text, '、');
      expect(segs[2], isA<LinkSegment>());
    });

    test('標籤未閉合 → 整段純文字', () {
      const raw = '<a href="https://x.test">未閉合';
      final segs = parseTranslatorMarkup(raw);
      expect(segs, hasLength(1));
      expect((segs.first as TextSegment).text, raw);
    });

    test('巢狀標籤 → 整段純文字（不 match）', () {
      const raw = '<a href="https://x.test"><b>x</b></a>';
      final segs = parseTranslatorMarkup(raw);
      expect(segs, hasLength(1));
      expect((segs.first as TextSegment).text, raw);
    });

    test('javascript: scheme → 降為顯示文字', () {
      final segs = parseTranslatorMarkup(
        '<a href="javascript:alert(1)">x</a>',
      );
      expect(segs, hasLength(1));
      expect((segs.first as TextSegment).text, 'x');
    });

    test('無效 Uri → 降為顯示文字', () {
      final segs = parseTranslatorMarkup('<a href=":::">x</a>');
      expect(segs, hasLength(1));
      expect((segs.first as TextSegment).text, 'x');
    });

    test('空字串 → 空 list', () {
      expect(parseTranslatorMarkup(''), isEmpty);
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/widgets/translator_text_test.dart`
Expected: 編譯失敗（`parseTranslatorMarkup` / `TextSegment` / `LinkSegment` 未定義）。

- [ ] **Step 3: 寫最小實作讓測試通過**

建立 `lib/widgets/translator_text.dart`：

```dart
// lib/widgets/translator_text.dart
import 'package:flutter/foundation.dart';

/// 把 localeTranslator 字串拆成可渲染段落。
///
/// 只支援 `<a href="https://...">label</a>` 一種標籤；href 必須是
/// http / https 且能被 [Uri.tryParse] 解析。其他情境降為純文字。
@visibleForTesting
List<TranslatorSegment> parseTranslatorMarkup(String raw) {
  if (raw.isEmpty) return const [];

  final pattern = RegExp(r'<a\s+href="([^"]+)">([^<]+)</a>');
  final segments = <TranslatorSegment>[];
  var cursor = 0;

  for (final match in pattern.allMatches(raw)) {
    if (match.start > cursor) {
      segments.add(TextSegment(raw.substring(cursor, match.start)));
    }
    final href = match.group(1)!;
    final label = match.group(2)!;
    final uri = Uri.tryParse(href);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      segments.add(LinkSegment(label, uri));
    } else {
      debugPrint('TranslatorText: dropping invalid href "$href"');
      segments.add(TextSegment(label));
    }
    cursor = match.end;
  }

  if (cursor < raw.length) {
    segments.add(TextSegment(raw.substring(cursor)));
  }

  return segments;
}

sealed class TranslatorSegment {
  const TranslatorSegment();
}

class TextSegment extends TranslatorSegment {
  const TextSegment(this.text);
  final String text;
}

class LinkSegment extends TranslatorSegment {
  const LinkSegment(this.text, this.uri);
  final String text;
  final Uri uri;
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/widgets/translator_text_test.dart`
Expected: 9 個測試全通過。

- [ ] **Step 5: 提交前品質檢查**

Run: `dart format lib/ test/`
Expected: 無錯誤（會列出格式化過的檔案）。

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/translator_text.dart test/widgets/translator_text_test.dart
git commit -m "feat(widgets): add parseTranslatorMarkup for <a href> in translator credit"
```

---

## Task 3：實作 `TranslatorText` widget（TDD）

**Files:**
- Modify: `lib/widgets/translator_text.dart`（加上 widget 與 url_launcher 整合）
- Modify: `test/widgets/translator_text_test.dart`（追加 widget 測試 group）

- [ ] **Step 1: 寫失敗的 widget 測試**

在 `test/widgets/translator_text_test.dart` 檔尾、`main()` 大括號**內**、`group('parseTranslatorMarkup', ...)` 之後追加：

```dart
  group('TranslatorText widget', () {
    testWidgets('含連結時：連結 span 有 underline 與 recognizer，純文字 span 沒有', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TranslatorText(
              raw: 'jj、<a href="https://example.test">世界へいわ</a>',
            ),
          ),
        ),
      );

      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byType(TranslatorText),
          matching: find.byType(RichText),
        ),
      );
      final root = richText.text as TextSpan;
      final spans = root.children!.cast<TextSpan>();

      final linkSpan = spans.firstWhere((s) => s.text == '世界へいわ');
      expect(linkSpan.style?.decoration, TextDecoration.underline);
      expect(linkSpan.recognizer, isNotNull);

      final textSpan = spans.firstWhere((s) => s.text == 'jj、');
      expect(textSpan.recognizer, isNull);
    });

    testWidgets('純文字輸入：所有 span 都沒有 recognizer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TranslatorText(raw: 'Alice, Bob')),
        ),
      );

      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byType(TranslatorText),
          matching: find.byType(RichText),
        ),
      );
      final root = richText.text as TextSpan;
      for (final span in root.children!.cast<TextSpan>()) {
        expect((span as TextSpan).recognizer, isNull);
      }
    });
  });
```

並在檔頭加上對應的 import：

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
```

（`flutter_test` 與 `translator_text.dart` 的 import 在 Task 2 已加。）

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/widgets/translator_text_test.dart`
Expected: 編譯失敗（`TranslatorText` 類別未定義）。

- [ ] **Step 3: 寫 widget 實作**

修改 `lib/widgets/translator_text.dart`，在現有 parse 函式與 segment 型別之上**追加**以下內容（並補上對應 import）：

檔頭 import 區改為：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
```

檔尾追加 widget：

```dart
/// 把帶有 `<a href>` 標籤的字串顯示為可點擊文字。
///
/// 僅用於設定頁 About 區塊的譯者署名。
class TranslatorText extends StatefulWidget {
  const TranslatorText({super.key, required this.raw, this.style});

  final String raw;
  final TextStyle? style;

  @override
  State<TranslatorText> createState() => _TranslatorTextState();
}

class _TranslatorTextState extends State<TranslatorText> {
  late List<TranslatorSegment> _segments;
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant TranslatorText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.raw != widget.raw) {
      _disposeRecognizers();
      _rebuild();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _rebuild() {
    _segments = parseTranslatorMarkup(widget.raw);
    for (final seg in _segments) {
      if (seg is LinkSegment) {
        _recognizers.add(
          TapGestureRecognizer()..onTap = () => _open(seg.uri),
        );
      }
    }
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(Uri uri) async {
    if (!await canLaunchUrl(uri)) {
      debugPrint('TranslatorText: cannot launch $uri');
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final linkColor = Theme.of(context).colorScheme.primary;

    var linkIndex = 0;
    return Text.rich(
      TextSpan(
        children: [
          for (final seg in _segments)
            if (seg is TextSegment)
              TextSpan(text: seg.text, style: baseStyle)
            else if (seg is LinkSegment)
              TextSpan(
                text: seg.text,
                style: baseStyle.copyWith(
                  color: linkColor,
                  decoration: TextDecoration.underline,
                ),
                recognizer: _recognizers[linkIndex++],
              ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/widgets/translator_text_test.dart`
Expected: parse group 9 個 + widget group 2 個 = 11 個全通過。

- [ ] **Step 5: 提交前品質檢查**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/translator_text.dart test/widgets/translator_text_test.dart
git commit -m "feat(widgets): add TranslatorText for clickable translator credits"
```

---

## Task 4：把 settings_page._AboutContent 改用 `TranslatorText`

**Files:**
- Modify: `lib/pages/settings_page.dart`

- [ ] **Step 1: 加入 import**

`lib/pages/settings_page.dart` 檔頭 import 區（與其他 widgets/ 同層）加：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/translator_text.dart';
```

放在既有的 `widgets/*` import 旁邊保持字母排序，例如放在：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
```

之後（注意原本順序，視實際狀況調整保持一致）。

- [ ] **Step 2: 把 `Text(translator, ...)` 換成 `TranslatorText`**

`lib/pages/settings_page.dart` 第 192–197 行原本是：

```dart
              Expanded(
                child: Text(
                  translator,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
```

改為：

```dart
              Expanded(
                child: TranslatorText(
                  raw: translator,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
```

其餘（外層 `Row` / `Icon` / `translator.isNotEmpty` 守衛）**不動**。

- [ ] **Step 3: 提交前品質檢查**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add lib/pages/settings_page.dart
git commit -m "feat(settings): render translator credit HTML with TranslatorText"
```

---

## Task 5：手動驗證

**沒有檔案變更**，只跑 app 確認 UI 行為。

- [ ] **Step 1: 啟動 app**

Run: `flutter run -d windows`（或目前慣用的桌面 device）
Expected: app 正常開起來。

- [ ] **Step 2: 切換語言到日文**

進入「設定 → 語言」下拉，選「日本語」。

Expected: 介面切到日文。

- [ ] **Step 3: 檢查 About 區塊**

捲到頁面下方「このツールについて」（About）區塊。

Expected:
- 譯者列顯示 `jj、世界へいわ`，兩個之間有「、」。
- 「世界へいわ」是 primary color（theme 預設藍 / 紫色系）且有底線；「jj、」是一般文字色。
- 不應看到 `<a href="...">` 等 HTML 標籤的原文。

- [ ] **Step 4: 點擊連結**

點擊「世界へいわ」。

Expected:
- 系統預設瀏覽器（Edge / Chrome 等）自動開啟，網址為 `https://home.gamer.com.tw/homeindex.php?owner=XMoiswnX`。

- [ ] **Step 5: 切換到其他語言確認 regression**

依序切到：英文（`English`）、繁體中文、簡體中文、葡萄牙文、法文、西班牙文、泰文、越南文。

Expected:
- 英文：譯者列顯示 `Zanah_68, pan93412, Lemon7777`，純文字、無底線、不可點。
- 葡萄牙文：`Mirusausiliq & Boemio`，純文字。
- 泰文：`Armzyaec1234`，純文字。
- 西班牙文：`cahoinu`，純文字。
- 法文 / 越南文 / 繁中 / 簡中：因 ARB 內 `localeTranslator` 為空字串，整列（含 `Icon` + 文字）**不顯示**（依 `translator.isNotEmpty` 守衛）。

- [ ] **Step 6: 結束 app**

關閉 app。沒有需要 commit 的變更。

---

## Self-Review 摘要

- **Spec coverage：**
  - Spec「目標 1」（render `<a>`）→ Task 2 + 3。
  - Spec「目標 2」（用系統瀏覽器開啟）→ Task 3 `_open` + Task 1 url_launcher 依賴。
  - Spec「目標 3」（純文字維持原樣）→ Task 2 parse `[TextSegment]` 路徑 + Task 5 手動 regression。
  - Spec「Parse 規則」（regex、scheme 白名單、巢狀 / 未閉合 fallback、空字串）→ Task 2 測試 9 case 全覆蓋。
  - Spec「Recognizer 生命週期」（initState / didUpdateWidget / dispose）→ Task 3 實作。
  - Spec「測試 Group 2」（widget 渲染）→ Task 3 測試 2 case。
  - Spec「手動驗證」→ Task 5。
- **Placeholder scan：** 無 TBD / TODO。
- **Type consistency：** `TranslatorSegment` / `TextSegment` / `LinkSegment` / `parseTranslatorMarkup` / `TranslatorText` 在 Task 2 → 3 → 4 → 測試之間命名一致。
