# AppLink 與連結滑鼠指標統一規範 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 統一外部 URL 連結的 UI 與互動，讓所有外連結 hover 時都會切換成 click cursor，並消除 `launchUrl` 重複實作。

**Architecture:** 新增 `AppLink` widget（`MouseRegion + GestureDetector` 包 child，內部 hover state 切換 cursor 與連結色）。新增 `openExternalUrl(Uri)` top-level helper，封裝 `canLaunchUrl + launchUrl(externalApplication)`。`_ContributorChips` 改用 `AppLink`；`TranslatorText` 的 `LinkSegment` 對應 `TextSpan` 補上 `mouseCursor`，`_open` 改呼叫 helper。

**Tech Stack:** Flutter 3.x、`url_launcher` ^6.3.2、`flutter_test`。

**Spec:** `docs/superpowers/specs/2026-05-12-app-link-cursor-design.md`

---

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `lib/widgets/app_link.dart` | 新增 | `AppLink` widget + `openExternalUrl(Uri)` helper |
| `lib/widgets/translator_text.dart` | 修改 | 加 `mouseCursor`、`_open` 改用共用 helper |
| `lib/pages/contributors_page.dart` | 修改 | `_ContributorChips` 改用 `AppLink`，移除 `_open` 與 `url_launcher` import |
| `test/widgets/app_link_test.dart` | 新增 | `AppLink` 渲染、cursor、hover、tap 行為 |
| `test/widgets/translator_text_test.dart` | 修改 | 補 `linkSpan.mouseCursor` 斷言 |
| `test/pages/contributors_page_test.dart` | 修改 | `find.byType(InkWell)` → `find.byType(AppLink)` |

每個 Task 完成時都會跑 `dart format lib/ test/` → `flutter analyze` → `flutter test`，全綠才能 commit。**不要對 `.` 跑 `dart format`**，會動到 `rust_builder/` vendored 程式碼（見 `CLAUDE.md`）。

---

## Task 1: 新增 `AppLink` widget 與 `openExternalUrl` helper（TDD 多輪）

**Files:**
- Create: `lib/widgets/app_link.dart`
- Create: `test/widgets/app_link_test.dart`

### Round A — Stub + 渲染樣式

- [ ] **Step A1: 建立 widget stub**

建立 `lib/widgets/app_link.dart`，先放最小 stub 讓測試可以 import：

```dart
import 'package:flutter/material.dart';

class AppLink extends StatelessWidget {
  const AppLink({super.key, required this.url, required this.child});

  final String url;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

Future<void> openExternalUrl(Uri uri) async {
  throw UnimplementedError();
}
```

- [ ] **Step A2: 寫渲染樣式 failing test**

建立 `test/widgets/app_link_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

void main() {
  testWidgets('預設樣式：primary color + underline', (tester) async {
    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: AppLink(url: 'https://example.test', child: Text('hi')),
        ),
      ),
    );

    final textWidget = tester.widget<Text>(find.text('hi'));
    final effectiveStyle =
        DefaultTextStyle.of(tester.element(find.text('hi'))).style.merge(
              textWidget.style,
            );

    expect(effectiveStyle.color, theme.colorScheme.primary);
    expect(effectiveStyle.decoration, TextDecoration.underline);
  });
}
```

- [ ] **Step A3: 跑測試確認 fail**

Run: `flutter test test/widgets/app_link_test.dart`
Expected: FAIL（stub `build` 直接 return child，沒套樣式，color 不是 primary）

- [ ] **Step A4: 實作渲染樣式**

把 `lib/widgets/app_link.dart` 改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class AppLink extends StatelessWidget {
  const AppLink({super.key, required this.url, required this.child});

  final String url;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTextStyle.merge(
      style: TextStyle(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      child: child,
    );
  }
}

Future<void> openExternalUrl(Uri uri) async {
  throw UnimplementedError();
}
```

（保留 `flutter/services.dart`、`url_launcher` 的 import，下一輪會用到。）

- [ ] **Step A5: 跑測試確認 pass**

Run: `flutter test test/widgets/app_link_test.dart`
Expected: PASS

### Round B — Cursor 切換

- [ ] **Step B1: 寫 cursor failing test**

把 `test/widgets/app_link_test.dart` 加入第二筆 `testWidgets`：

```dart
testWidgets('hover 時 cursor 為 SystemMouseCursors.click', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: AppLink(url: 'https://example.test', child: Text('hi')),
      ),
    ),
  );

  final region = tester.widget<MouseRegion>(
    find.descendant(
      of: find.byType(AppLink),
      matching: find.byType(MouseRegion),
    ).first,
  );
  expect(region.cursor, SystemMouseCursors.click);
});
```

- [ ] **Step B2: 跑測試確認 fail**

Run: `flutter test test/widgets/app_link_test.dart`
Expected: 新測試 FAIL（`AppLink` 內還沒有 `MouseRegion`）

- [ ] **Step B3: 加 MouseRegion**

把 `lib/widgets/app_link.dart` 的 build 方法改為：

```dart
@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return MouseRegion(
    cursor: SystemMouseCursors.click,
    child: DefaultTextStyle.merge(
      style: TextStyle(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      child: child,
    ),
  );
}
```

- [ ] **Step B4: 跑測試確認 pass**

Run: `flutter test test/widgets/app_link_test.dart`
Expected: PASS（兩筆）

### Round C — Hover 變色

- [ ] **Step C1: 寫 hover 變色 failing test**

把 `test/widgets/app_link_test.dart` 加入第三筆 `testWidgets`：

```dart
testWidgets('hover 時文字顏色與未 hover 時不同', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: Center(
          child: AppLink(url: 'https://example.test', child: Text('hi')),
        ),
      ),
    ),
  );

  Color? readColor() {
    final ctx = tester.element(find.text('hi'));
    return DefaultTextStyle.of(ctx).style.color;
  }

  final before = readColor();

  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(tester.getCenter(find.text('hi')));
  await tester.pump();

  final after = readColor();

  expect(before, isNotNull);
  expect(after, isNotNull);
  expect(after, isNot(equals(before)));
});
```

並在檔案開頭 import：

```dart
import 'package:flutter/gestures.dart';
```

- [ ] **Step C2: 跑測試確認 fail**

Run: `flutter test test/widgets/app_link_test.dart`
Expected: 新測試 FAIL（hover 前後顏色相同）

- [ ] **Step C3: 改成 StatefulWidget + hover state**

把 `lib/widgets/app_link.dart` 改為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class AppLink extends StatefulWidget {
  const AppLink({super.key, required this.url, required this.child});

  final String url;
  final Widget child;

  @override
  State<AppLink> createState() => _AppLinkState();
}

class _AppLinkState extends State<AppLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.primary;
    final hoverColor =
        Color.lerp(baseColor, theme.colorScheme.onSurface, 0.15) ?? baseColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: _hovering ? hoverColor : baseColor,
          decoration: TextDecoration.underline,
        ),
        child: widget.child,
      ),
    );
  }
}

Future<void> openExternalUrl(Uri uri) async {
  throw UnimplementedError();
}
```

- [ ] **Step C4: 跑測試確認三筆都 pass**

Run: `flutter test test/widgets/app_link_test.dart`
Expected: PASS（三筆）

### Round D — Tap 觸發 launchUrl

- [ ] **Step D1: 寫 tap failing test**

把 `test/widgets/app_link_test.dart` 加入第四筆 `testWidgets`：

```dart
testWidgets('點擊 AppLink 不會拋例外', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: AppLink(url: 'https://example.test', child: Text('hi')),
      ),
    ),
  );

  await tester.tap(find.text('hi'));
  await tester.pumpAndSettle();
});
```

（不 mock `url_launcher`；驗證 `tap()` + `pumpAndSettle()` 跑完不 throw。`canLaunchUrl` 在測試環境會回 `false`，`openExternalUrl` 早 return，不會真的開瀏覽器。）

- [ ] **Step D2: 跑測試確認 fail**

Run: `flutter test test/widgets/app_link_test.dart`
Expected: 新測試 FAIL（`AppLink` 還沒有 `GestureDetector`，tap 不會觸發任何 handler；事實上會 pass 但 helper 還 throw UnimplementedError — 重點是接下來實作完整 path）

> 註：`testWidgets` 的 `tap` 找不到 hit 區域時不會 fail，這個測試的真正價值是「實作 tap + helper 之後不能 throw」。實作完成後它仍要 pass。

- [ ] **Step D3: 實作 GestureDetector + openExternalUrl**

把 `lib/widgets/app_link.dart` 完成版本改為：

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AppLink extends StatefulWidget {
  const AppLink({super.key, required this.url, required this.child});

  final String url;
  final Widget child;

  @override
  State<AppLink> createState() => _AppLinkState();
}

class _AppLinkState extends State<AppLink> {
  bool _hovering = false;

  Future<void> _handleTap() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      debugPrint('AppLink: invalid url "${widget.url}"');
      return;
    }
    await openExternalUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.primary;
    final hoverColor =
        Color.lerp(baseColor, theme.colorScheme.onSurface, 0.15) ?? baseColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: _hovering ? hoverColor : baseColor,
            decoration: TextDecoration.underline,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

Future<void> openExternalUrl(Uri uri) async {
  if (!await canLaunchUrl(uri)) {
    debugPrint('openExternalUrl: cannot launch $uri');
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
```

移除不必要的 `package:flutter/services.dart` import（`SystemMouseCursors` 由 `flutter/material.dart` 透出）。

- [ ] **Step D4: 跑全部 widget tests 確認 pass**

Run: `flutter test test/widgets/app_link_test.dart`
Expected: PASS（四筆）

### Round E — 提交前檢查 + Commit

- [ ] **Step E1: 格式化**

Run: `dart format lib/ test/`
Expected: 顯示格式化過的檔案數量；無錯誤。

- [ ] **Step E2: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step E3: 跑全測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step E4: Commit**

```powershell
git add lib/widgets/app_link.dart test/widgets/app_link_test.dart
git commit -m @'
feat(widgets): add AppLink widget for external URL links

- 統一連結 UI：primary color + underline + hover 變色
- MouseRegion 切換 cursor 為 SystemMouseCursors.click
- openExternalUrl() helper 封裝 canLaunchUrl + launchUrl 邏輯
'@
```

---

## Task 2: `TranslatorText` 補 `mouseCursor` 並改用共用 helper

**Files:**
- Modify: `lib/widgets/translator_text.dart`
- Modify: `test/widgets/translator_text_test.dart`

- [ ] **Step 1: 改 test — 補 mouseCursor 斷言**

打開 `test/widgets/translator_text_test.dart`，在第 78 行起的 `testWidgets('含連結時：...'` 中，於 `expect(linkSpan.recognizer, isNotNull);` 之後加入：

```dart
expect(linkSpan.mouseCursor, SystemMouseCursors.click);
```

- [ ] **Step 2: 跑測試確認 fail**

Run: `flutter test test/widgets/translator_text_test.dart`
Expected: 該筆 FAIL（`linkSpan.mouseCursor` 是 `MouseCursor.defer`，不是 `SystemMouseCursors.click`）

- [ ] **Step 3: 改 widget — 補 mouseCursor + 改用 helper**

打開 `lib/widgets/translator_text.dart`。

第 1–4 行調整 import：

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
```

（移除 `url_launcher` import；改 import `app_link.dart`。）

把 `_open` 方法（第 107–113 行）整段改為：

```dart
Future<void> _open(Uri uri) => openExternalUrl(uri);
```

把 build 方法中 `LinkSegment` 對應的 `TextSpan`（第 128–135 行）加上 `mouseCursor`：

```dart
TextSpan(
  text: seg.text,
  style: baseStyle.copyWith(
    color: linkColor,
    decoration: TextDecoration.underline,
  ),
  mouseCursor: SystemMouseCursors.click,
  recognizer: _recognizers[linkIndex++],
),
```

- [ ] **Step 4: 跑測試確認 pass**

Run: `flutter test test/widgets/translator_text_test.dart`
Expected: PASS

- [ ] **Step 5: 跑全測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: 格式化 + 靜態分析**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```powershell
git add lib/widgets/translator_text.dart test/widgets/translator_text_test.dart
git commit -m @'
fix(translator-text): show click cursor on link spans

- TextSpan 補 mouseCursor: SystemMouseCursors.click（原本沒設導致 hover 不切換）
- _open() 改呼叫共用 openExternalUrl() helper
- 涵蓋 GitHub 貢獻者連結、Crowdin、License、翻譯者連結
'@
```

---

## Task 3: `_ContributorChips` 改用 `AppLink`

**Files:**
- Modify: `lib/pages/contributors_page.dart`
- Modify: `test/pages/contributors_page_test.dart`

- [ ] **Step 1: 改 test — InkWell → AppLink**

打開 `test/pages/contributors_page_test.dart`。

第 38–46 行的 `'GoneTone 包成 InkWell'` 測試標題與 matcher 改為：

```dart
testWidgets('專案負責人 SectionCard 顯示 GoneTone 並包成 AppLink', (tester) async {
  await tester.pumpWidget(_wrap(const ContributorsPage()));
  await tester.pumpAndSettle();
  expect(find.text('GoneTone'), findsOneWidget);
  expect(
    find.ancestor(of: find.text('GoneTone'), matching: find.byType(AppLink)),
    findsOneWidget,
  );
});
```

第 55–70 行的 `'pan93412 / Lemon7777 為純文字（無 url）'` 測試將兩個 `find.byType(InkWell)` 改為 `find.byType(AppLink)`：

```dart
expect(
  find.ancestor(of: find.text('pan93412'), matching: find.byType(AppLink)),
  findsNothing,
);
expect(
  find.ancestor(of: find.text('Lemon7777'), matching: find.byType(AppLink)),
  findsNothing,
);
```

並在檔案頂端 import 區塊加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
```

- [ ] **Step 2: 跑測試確認 fail**

Run: `flutter test test/pages/contributors_page_test.dart`
Expected: 兩筆 FAIL（找不到 `AppLink` ancestor）

- [ ] **Step 3: 改 widget — InkWell → AppLink**

打開 `lib/pages/contributors_page.dart`。

調整 import（移除第 4 行 `url_launcher`，新增 `app_link.dart`）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/contributors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/translator_text.dart';
```

把 `_ContributorChips`（第 86–121 行整段）改為：

```dart
class _ContributorChips extends StatelessWidget {
  const _ContributorChips(this.items);
  final List<Contributor> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.s,
      children: [
        for (final c in items)
          if (c.url == null)
            Text(c.name)
          else
            AppLink(url: c.url!, child: Text(c.name)),
      ],
    );
  }
}
```

說明：
- 移除 `_open` 私有方法（行為改由 `AppLink` 內部 + `openExternalUrl` 承擔）。
- 移除 `linkColor` 區域變數與 `TextStyle(...)`（`AppLink` 已套樣式）。
- `Text(c.name)` 不傳 style，由 `AppLink` 的 `DefaultTextStyle.merge` 套用。

- [ ] **Step 4: 跑測試確認 pass**

Run: `flutter test test/pages/contributors_page_test.dart`
Expected: PASS

- [ ] **Step 5: 跑全測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: 格式化 + 靜態分析**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```powershell
git add lib/pages/contributors_page.dart test/pages/contributors_page_test.dart
git commit -m @'
refactor(contributors): use AppLink for contributor name links

- _ContributorChips 內 InkWell + Text 換成 AppLink
- 移除重複的 _open() 與 url_launcher import
- 統一 cursor 切換、hover 變色行為
'@
```

---

## Self-Review 結果

對照 spec 各章節：

1. **背景兩個成因** → Task 2（TranslatorText `mouseCursor`）、Task 3（ContributorChips 換 AppLink）皆覆蓋。
2. **`AppLink` widget**（StatefulWidget、MouseRegion、GestureDetector、hover lerp、DefaultTextStyle.merge）→ Task 1 Round A–D。
3. **`openExternalUrl` helper** → Task 1 Round D 完整實作；Task 2、Task 3 改為呼叫它。
4. **TranslatorText 不切 WidgetSpan** → Task 2 維持 `TextSpan` + recognizer，只補 `mouseCursor`。
5. **不動 app_shell / sortable_table** → Plan 沒有對應 Task，符合預期。
6. **不做 active / pressed / focus / 動畫過渡** → Plan 內無相關 Step。
7. **測試三檔** → Task 1（新增 `app_link_test.dart`）、Task 2（改 `translator_text_test.dart`）、Task 3（改 `contributors_page_test.dart`）。
8. **提交前檢查（format / analyze / test）** → 每個 Task 的 commit 前都跑。

無 placeholder、type 名稱跨 task 一致（`AppLink`、`openExternalUrl`、`_handleTap`、`_hovering`）。
