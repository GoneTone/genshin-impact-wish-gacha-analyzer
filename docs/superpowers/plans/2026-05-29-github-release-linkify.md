# GitHub Release Notes 連結 GitHub 化顯示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 App 內渲染 release notes 前，把本專案的 GitHub 連結（PR / Issue / compare / commit）與 `@提及` 改寫成與 GitHub 網頁一致的精簡顯示樣式。

**Architecture:** 新增純函式 `linkifyGithubReferences(String)` 於 `lib/utils/`，以一連串 `RegExp` 替換完成轉換；在 `ReleaseNotesContent` 渲染 Markdown 前呼叫。`AppRelease.body` 保持 API 原樣，轉換屬呈現層職責。`NewVersionDialog` 與 `CurrentReleaseDialog` 共用該 widget，兩處自動生效。

**Tech Stack:** Dart / Flutter、`RegExp`（含 lookbehind）、`markdown_widget`、`flutter_test`。

---

## File Structure

- **Create** `lib/utils/github_release_linkify.dart` — 純函式 `linkifyGithubReferences`，唯一職責是字串層級的 GitHub 連結／提及改寫。無 Flutter 依賴，對齊 `lib/utils/` 既有純工具慣例（`format_bytes.dart`、`uid_display.dart`）。
- **Create** `test/utils/github_release_linkify_test.dart` — 上述函式的單元測試。
- **Modify** `lib/widgets/dialogs/release_notes_content.dart` — `MarkdownBlock(data:)` 改為先過 `linkifyGithubReferences`。

---

## Task 1: `linkifyGithubReferences` 純函式（TDD）

**Files:**
- Create: `lib/utils/github_release_linkify.dart`
- Test: `test/utils/github_release_linkify_test.dart`

- [ ] **Step 1: 撰寫失敗測試**

建立 `test/utils/github_release_linkify_test.dart`，內容如下：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/utils/github_release_linkify.dart';

void main() {
  const base =
      'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer';

  group('linkifyGithubReferences — 網址型', () {
    test('PR 連結轉成 #N', () {
      expect(
        linkifyGithubReferences('$base/pull/70'),
        '[#70]($base/pull/70)',
      );
    });

    test('Issue 連結轉成 #N', () {
      expect(
        linkifyGithubReferences('$base/issues/123'),
        '[#123]($base/issues/123)',
      );
    });

    test('compare 連結轉成比較區間', () {
      expect(
        linkifyGithubReferences('$base/compare/v1.0.0...v1.1.0'),
        '[v1.0.0...v1.1.0]($base/compare/v1.0.0...v1.1.0)',
      );
    });

    test('commit 連結轉成前 7 碼短 SHA', () {
      const sha = '0123456789abcdef0123456789abcdef01234567';
      expect(
        linkifyGithubReferences('$base/commit/$sha'),
        '[0123456]($base/commit/$sha)',
      );
    });
  });

  group('linkifyGithubReferences — @提及', () {
    test('一般使用者轉成個人頁連結', () {
      expect(
        linkifyGithubReferences('@GoneTone'),
        '[@GoneTone](https://github.com/GoneTone)',
      );
    });

    test('[bot] 後綴轉成 app 連結並保留 [bot] 顯示', () {
      expect(
        linkifyGithubReferences('@dependabot[bot]'),
        '[@dependabot[bot]](https://github.com/apps/dependabot)',
      );
    });

    test('email 樣式不被誤判為提及', () {
      expect(
        linkifyGithubReferences('contact foo@example.com please'),
        'contact foo@example.com please',
      );
    });
  });

  group('linkifyGithubReferences — 不該動的情況', () {
    test('非 GitHub 網址維持原樣', () {
      expect(
        linkifyGithubReferences('https://genshininfo.reh.tw/archives/97'),
        'https://genshininfo.reh.tw/archives/97',
      );
    });

    test('已是 markdown 連結的網址不再被包一層', () {
      expect(
        linkifyGithubReferences('[#70]($base/pull/70)'),
        '[#70]($base/pull/70)',
      );
    });

    test('autolink <url> 形式不被改寫', () {
      expect(
        linkifyGithubReferences('<$base/pull/70>'),
        '<$base/pull/70>',
      );
    });
  });

  group('linkifyGithubReferences — 組合', () {
    test('同一行的提及與 PR 連結皆正確轉換', () {
      expect(
        linkifyGithubReferences('* feat by @GoneTone in $base/pull/70'),
        '* feat by [@GoneTone](https://github.com/GoneTone) '
            'in [#70]($base/pull/70)',
      );
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/utils/github_release_linkify_test.dart`
Expected: 編譯失敗，錯誤訊息類似 `Error: Couldn't resolve the package 'github_release_linkify.dart'` 或 `linkifyGithubReferences isn't defined`（檔案尚未建立）。

- [ ] **Step 3: 撰寫最小實作**

建立 `lib/utils/github_release_linkify.dart`，內容如下：

```dart
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
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/utils/github_release_linkify_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 格式化並提交**

```bash
dart format lib/utils/github_release_linkify.dart test/utils/github_release_linkify_test.dart
git add lib/utils/github_release_linkify.dart test/utils/github_release_linkify_test.dart
git commit -m "feat(release): linkify GitHub references in release notes

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: 接到 `ReleaseNotesContent` 渲染流程

**Files:**
- Modify: `lib/widgets/dialogs/release_notes_content.dart`

- [ ] **Step 1: 匯入工具函式**

在 `lib/widgets/dialogs/release_notes_content.dart` 既有的 import 區塊（與其他 `package:genshin_impact_wish_gacha_analyzer/...` import 並列、依字母序）加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/utils/github_release_linkify.dart';
```

- [ ] **Step 2: 在渲染前套用轉換**

把現有的：

```dart
            if (release.body.isNotEmpty)
              MarkdownBlock(
                data: release.body,
                config: releaseNotesMarkdownConfig(theme),
              ),
```

改為：

```dart
            if (release.body.isNotEmpty)
              MarkdownBlock(
                data: linkifyGithubReferences(release.body),
                config: releaseNotesMarkdownConfig(theme),
              ),
```

- [ ] **Step 3: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: 跑既有相關 widget 測試確認未回歸**

Run: `flutter test test/widgets/dialogs/current_release_dialog_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/dialogs/release_notes_content.dart
git commit -m "feat(release): render linkified GitHub references in release notes UI

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: 全套品質檢查

**Files:** 無（僅驗證）

- [ ] **Step 1: 格式化**

Run: `dart format lib/ test/`
Expected: 無待格式化變更（或顯示已格式化的檔案數，無錯誤）。

- [ ] **Step 2: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全套測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: 若 Step 1 產生變更則補提交**

```bash
git add -A
git commit -m "style(release): apply dart format

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

若 Step 1 無任何變更，跳過此步。

---

## Self-Review 紀錄

- **Spec coverage**：六種轉換（PR/Issue/compare/commit/@user/@bot）→ Task 1 Step 3 實作 + Step 1 測試逐項涵蓋；防重複包裝、email 排除 → Task 1 測試涵蓋；渲染接點（兩 dialog 共用）→ Task 2；驗收條件（format/analyze/test 全綠）→ Task 3。無遺漏。
- **Placeholder scan**：所有 code step 皆含完整程式碼，無 TBD／TODO／「處理邊界」類占位。
- **Type/命名一致**：函式名 `linkifyGithubReferences` 在實作、測試 import、Task 2 呼叫處一致；regex 變數 `_prRe`/`_issueRe`/`_compareRe`/`_commitRe`/`_mentionRe` 與 `linkifyGithubReferences` 內引用一致。
