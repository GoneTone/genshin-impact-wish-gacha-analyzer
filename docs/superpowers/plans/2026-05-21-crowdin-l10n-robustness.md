# Crowdin l10n 流程強化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 Crowdin 自動 PR 不再卡 CI（`@@locale` 帶地區碼）、且 app 只呈現真正釋出的語言（軟體端過濾未翻譯空殼），全程不依賴 Crowdin 端設定。

**Architecture:** 三個獨立元件：(A) 零相依 Dart 腳本 `tool/normalize_arb_locale.dart` 在 `flutter pub get` 前把 `@@locale` 正規化成檔名衍生 locale，整合進 CI `quality` job 並 commit 回 PR 分支；(B) `localization_metadata.dart` 新增純函式 `filterReleasedLocales` + `releasedLocalesProvider`，以「localeNativeName 是否 fallback 成模板繁中」為 gate，餵給 `MaterialApp.supportedLocales` 與語言選單；(C) 清掉失效的 `crowdin.yml` 設定、並把 l10n 測試改成資料無關的不變式。

**Tech Stack:** Flutter (Dart `^3.11.5`)、flutter_riverpod、gen-l10n（`generate: true`）、GitHub Actions、Crowdin GitHub 整合。

**前置：** 在 master 開一個 feature 分支執行（例如 `l10n-robustness`）。本計畫所有改動都在 master 的 arb 資料（9 個精選語言、`pt` 完整、無空殼）下開發，故過濾在 master 上是 no-op；過濾的真正行為由純函式單元測試驗證（與分支資料無關）。**commit 不 push**（CLAUDE.md）。

---

## File Structure

- **Create** `tool/normalize_arb_locale.dart` — 零相依（只用 `dart:io`）的 `@@locale` 正規化腳本，匯出可測函式 `normalizeArbLocales(Directory)`。
- **Create** `test/tool/normalize_arb_locale_test.dart` — 對上述函式的單元測試（暫存目錄）。
- **Modify** `lib/state/localization_metadata.dart` — 新增純函式 `filterReleasedLocales(...)` 與 `releasedLocalesProvider`；`localeMetadataProvider` 改吃 released set；更新過時 dartdoc。
- **Modify** `lib/main.dart:178` — `supportedLocales` 改為 `ref.watch(releasedLocalesProvider)`。
- **Modify** `test/l10n/locale_metadata_test.dart` — 加 `filterReleasedLocales` / `releasedLocalesProvider` 測試；把 Portuguese 與「保留語言」斷言改成資料無關版本。
- **Modify** `.github/workflows/ci.yml` — `permissions: write`、checkout head 分支、pub get 前正規化 + 同 repo PR 時 commit 回分支。
- **Modify** `crowdin.yml` — 移除失效的 `skip_untranslated_files` 與誤導註解。

每個 commit 前依 CLAUDE.md 跑 `dart format lib/ test/`、`flutter analyze`（須 `No issues found!`）、`flutter test`（須 `All tests passed!`）。

---

## Task 1: `@@locale` 正規化腳本

**Files:**
- Create: `tool/normalize_arb_locale.dart`
- Test: `test/tool/normalize_arb_locale_test.dart`

- [ ] **Step 1: 先寫失敗測試**

`test/tool/normalize_arb_locale_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/normalize_arb_locale.dart';

void main() {
  test('normalizeArbLocales 把 @@locale 改成檔名衍生 locale、已正確者不動', () {
    final dir = Directory.systemTemp.createTempSync('arb_normalize_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    File('${dir.path}/app_es.arb')
        .writeAsStringSync('{\n  "@@locale": "es-ES",\n  "x": "y"\n}');
    File('${dir.path}/app_zh_Hans.arb')
        .writeAsStringSync('{\n  "@@locale": "zh-CN"\n}');
    File('${dir.path}/app_en.arb').writeAsStringSync('{\n  "@@locale": "en"\n}');

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
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/tool/normalize_arb_locale_test.dart`
Expected: 編譯失敗 —「Target of URI doesn't exist: '../../tool/normalize_arb_locale.dart'」。

- [ ] **Step 3: 實作腳本**

`tool/normalize_arb_locale.dart`：

```dart
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
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/tool/normalize_arb_locale_test.dart`
Expected: PASS（All tests passed!）。

- [ ] **Step 5: format / analyze**

Run: `dart format lib/ test/ && flutter analyze`
Expected: `No issues found!`（注意：`tool/` 不在 format 範圍，請確保手寫即符合格式；`flutter analyze` 會分析 `tool/`，須無 issue）。

- [ ] **Step 6: Commit**

```bash
git add tool/normalize_arb_locale.dart test/tool/normalize_arb_locale_test.dart
git commit -m "feat(l10n): add @@locale normalization script

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `filterReleasedLocales` 純函式（gate 邏輯）

**Files:**
- Modify: `lib/state/localization_metadata.dart`
- Test: `test/l10n/locale_metadata_test.dart`

- [ ] **Step 1: 先寫失敗測試**

在 `test/l10n/locale_metadata_test.dart` 的 import 區確認已有：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';
```

在 `void main() {` 內最上方新增一個 group：

```dart
  group('filterReleasedLocales', () {
    test('排除 fallback（nativeName == 模板）的 locale、保留模板與已翻譯', () {
      const template = Locale('zh');
      final names = <Locale, String>{
        const Locale('zh'): '繁體中文',
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'): '简体中文',
        const Locale('en'): 'English',
        const Locale('de'): '繁體中文', // 漏翻 localeNativeName → fallback
        const Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'):
            'Português',
        const Locale('pt'): '繁體中文', // 空殼 → fallback
      };

      final released = filterReleasedLocales(
        all: names.keys,
        template: template,
        templateNativeName: '繁體中文',
        nativeNameOf: (l) => names[l]!,
      );
      final tags = released.map((l) => l.toLanguageTag()).toSet();

      expect(tags, containsAll(<String>['zh', 'zh-Hans', 'en', 'pt-BR']));
      expect(tags, isNot(contains('de')));
      expect(tags, isNot(contains('pt')));
    });
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/l10n/locale_metadata_test.dart -p vm --plain-name "filterReleasedLocales"`
Expected: 編譯失敗 —「The function 'filterReleasedLocales' isn't defined」。

- [ ] **Step 3: 實作純函式**

在 `lib/state/localization_metadata.dart`，於 `localeMetadataProvider` 宣告**之前**新增：

```dart
/// 從 [all] 過濾出「已釋出」的 locale：保留 [template] 自身，以及 `nativeName`
/// 不等於 [templateNativeName] 的 locale。
///
/// gen-l10n 對漏翻 `localeNativeName` 的語系會 fallback 成模板（裸 `zh` = 繁體
/// 中文）的顯示名，這類「空殼／半翻譯」語系的 `nativeName` 會等於
/// [templateNativeName]，據此排除；模板自身則明確保留。[nativeNameOf] 提供
/// 各 locale 的 `localeNativeName`，方便以合成資料做單元測試。
List<Locale> filterReleasedLocales({
  required Iterable<Locale> all,
  required Locale template,
  required String templateNativeName,
  required String Function(Locale) nativeNameOf,
}) {
  return [
    for (final locale in all)
      if (locale == template || nativeNameOf(locale) != templateNativeName)
        locale,
  ];
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/l10n/locale_metadata_test.dart -p vm --plain-name "filterReleasedLocales"`
Expected: PASS。

- [ ] **Step 5: format / analyze**

Run: `dart format lib/ test/ && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/state/localization_metadata.dart test/l10n/locale_metadata_test.dart
git commit -m "feat(l10n): add filterReleasedLocales gate

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `releasedLocalesProvider` + 接線

**Files:**
- Modify: `lib/state/localization_metadata.dart`
- Modify: `lib/main.dart:178`
- Test: `test/l10n/locale_metadata_test.dart`

- [ ] **Step 1: 先寫失敗測試**

在 `test/l10n/locale_metadata_test.dart` 的 `group('localeMetadataProvider', ...)` 之前（或之後）新增：

```dart
  group('releasedLocalesProvider', () {
    test('保留模板 zh / zh-Hans 與主要已翻譯語言；空殼若存在則排除', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final released = container.read(releasedLocalesProvider);
      final tags = released.map((l) => l.toLanguageTag()).toSet();

      // 不變式（與當下 arb 資料無關）：模板與恆有翻譯的語言一定在
      expect(tags, containsAll(<String>['zh', 'zh-Hans', 'en']));
      expect(tags, isNot(contains('zh-Hant')));
      // 釋出清單不得有任何 nativeName 與模板（繁中）相同的非 zh locale
      final metadata = container.read(localeMetadataProvider);
      final zhName = metadata['zh']!.nativeName;
      final fallbackTags = metadata.entries
          .where((e) => e.key != 'zh' && e.value.nativeName == zhName)
          .map((e) => e.key)
          .toList();
      expect(fallbackTags, isEmpty, reason: '釋出清單不應含 fallback 成繁中的 locale');
    });
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/l10n/locale_metadata_test.dart -p vm --plain-name "releasedLocalesProvider"`
Expected: 編譯失敗 —「The getter 'releasedLocalesProvider' isn't defined」。

- [ ] **Step 3: 實作 provider 並改 localeMetadataProvider**

在 `lib/state/localization_metadata.dart`，於 `filterReleasedLocales` 之後新增 `releasedLocalesProvider`，並把既有 `localeMetadataProvider` 改成吃 released set。把原本的：

```dart
final localeMetadataProvider = Provider<Map<String, LocaleMetadata>>((ref) {
  final all = AppLocalizations.supportedLocales;
  final result = <String, LocaleMetadata>{};
  for (final locale in all) {
    AppLocalizations.delegate.load(locale).then((l) {
      result[locale.toLanguageTag()] = LocaleMetadata(
        nativeName: l.localeNativeName,
        translator: l.localeTranslator,
      );
    });
  }
  return result;
});
```

替換為：

```dart
/// 已釋出（`localeNativeName` 有實際翻譯、未 fallback 成模板繁中）的 locale 清單。
///
/// 餵給 `MaterialApp.supportedLocales` 與語言選單，使 OS 為某半翻譯語系的使用者
/// 不會被解析到 100% fallback 的空殼、選單也不會冒出多個「繁體中文」。
/// gate 邏輯見 [filterReleasedLocales]。
final releasedLocalesProvider = Provider<List<Locale>>((ref) {
  const template = Locale('zh');
  final names = <Locale, String>{};
  for (final locale in AppLocalizations.supportedLocales) {
    AppLocalizations.delegate.load(locale).then((l) {
      names[locale] = l.localeNativeName;
    });
  }
  return filterReleasedLocales(
    all: AppLocalizations.supportedLocales,
    template: template,
    templateNativeName: names[template] ?? '',
    nativeNameOf: (l) => names[l] ?? '',
  );
});

/// 一次性 load 所有「已釋出」locale 的 metadata；Settings 語言選單與
/// About / Contributors 區塊讀此 provider。
///
/// `delegate.load` 對 gen_l10n 編譯後的 const 內容回傳 [SynchronousFuture]，
/// 所以 `.then` callback 在同個 stack frame 內同步觸發、無 microtask 跳轉，
/// 也就不會多畫一個 `AsyncLoading` frame（避免設定頁進入時的 spinner 閃）。
final localeMetadataProvider = Provider<Map<String, LocaleMetadata>>((ref) {
  final released = ref.watch(releasedLocalesProvider);
  final result = <String, LocaleMetadata>{};
  for (final locale in released) {
    AppLocalizations.delegate.load(locale).then((l) {
      result[locale.toLanguageTag()] = LocaleMetadata(
        nativeName: l.localeNativeName,
        translator: l.localeTranslator,
      );
    });
  }
  return result;
});
```

同時把檔案上方 `localeMetadataProvider` 舊 dartdoc 裡「每個 supported locale 都是可選的真實語言…故全部納入」那段過時敘述移除（已被上面新 dartdoc 取代）。

- [ ] **Step 4: 接線 main.dart**

`lib/main.dart` 第 178 行，把：

```dart
      supportedLocales: AppLocalizations.supportedLocales,
```

改為：

```dart
      supportedLocales: ref.watch(releasedLocalesProvider),
```

（`_MainAppState.build` 已是 `ConsumerState`，`ref` 可用；`localeListResolutionCallback` 不需改——Flutter 會把上面這個 released 清單當作 `supportedLocales` 參數傳給 `localeListResolution`。）

- [ ] **Step 5: 跑測試確認通過 + 全套**

Run: `flutter test test/l10n/locale_metadata_test.dart`
Expected: PASS。

Run: `flutter test`
Expected: All tests passed!（`contributors_page_test` 在 master 上仍為 9 個乾淨語系，過濾為 no-op，維持通過）。

- [ ] **Step 6: format / analyze**

Run: `dart format lib/ test/ && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/state/localization_metadata.dart lib/main.dart test/l10n/locale_metadata_test.dart
git commit -m "feat(l10n): filter unreleased locales from picker and supportedLocales

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: 測試改為資料無關（Portuguese pt/pt_BR、保留語言斷言）

**背景：** 既有測試把 `pt` 寫死。master 上 `pt` 完整（→ 釋出），但 Crowdin 更新 merge 後 `pt` 會空、改由 `pt_BR` 釋出。為了讓測試在「master 現況」與「未來 l10n merge 後」都過，改成不綁定特定變體。

**Files:**
- Modify: `test/l10n/locale_metadata_test.dart`

- [ ] **Step 1: 改 Portuguese 斷言為資料無關**

把現有這個測試（約原 line 40-47）：

```dart
    test('葡萄牙文 localeNativeName 含 "Portugu"', () async {
      final pt = await AppLocalizations.delegate.load(const Locale('pt'));
      expect(
        pt.localeNativeName.toLowerCase(),
        contains('portugu'),
        reason: 'pt localeNativeName 看起來不像葡萄牙文',
      );
    });
```

替換為（透過 released metadata 找「某個 pt* 變體」，不綁 `pt` 或 `pt_BR`）：

```dart
    test('某個 Portuguese 變體（pt 或 pt_BR）已釋出且母語名像葡萄牙文', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final metadata = container.read(localeMetadataProvider);
      final pt = metadata.entries.where((e) => e.key.startsWith('pt')).toList();
      expect(pt, isNotEmpty, reason: '應有某個 Portuguese 變體釋出');
      expect(pt.first.value.nativeName.toLowerCase(), contains('portugu'));
    });
```

- [ ] **Step 2: 改 localeMetadataProvider 的「保留」斷言、移除寫死的 pt**

把現有這個測試（約原 line 108-119）：

```dart
    test('裸 zh（繁中）與 zh-Hans 都保留，無重複空殼被排除', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final metadata = container.read(localeMetadataProvider);
      final tags = metadata.keys.toSet();

      expect(tags, containsAll(<String>['zh', 'zh-Hans']));
      expect(tags, isNot(contains('zh-Hant')));
      expect(tags, contains('pt'));
      expect(tags, containsAll(<String>['en', 'ja', 'es', 'fr', 'th', 'vi']));
    });
```

替換為（移除單獨的 `contains('pt')`；Portuguese 由 Step 1 的測試涵蓋）：

```dart
    test('裸 zh（繁中）與 zh-Hans 都保留，空殼 fallback 被排除', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final metadata = container.read(localeMetadataProvider);
      final tags = metadata.keys.toSet();

      expect(tags, containsAll(<String>['zh', 'zh-Hans']));
      expect(tags, isNot(contains('zh-Hant')));
      expect(tags, containsAll(<String>['en', 'ja', 'es', 'fr', 'th', 'vi']));
    });
```

- [ ] **Step 3: 跑全套確認通過**

Run: `flutter test`
Expected: All tests passed!（master 上 `pt` 完整，Step 1 找到 `pt` 變體、含 'portugu'；其餘語言齊全）。

- [ ] **Step 4: format / analyze**

Run: `dart format lib/ test/ && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add test/l10n/locale_metadata_test.dart
git commit -m "test(l10n): make locale assertions data-independent (pt/pt_BR)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: 清掉 crowdin.yml 失效設定

**Files:**
- Modify: `crowdin.yml`

- [ ] **Step 1: 移除 skip_untranslated_files 與誤導註解**

把 `crowdin.yml` 整檔改為：

```yaml
commit_message: Translations %language%
append_commit_message: false
files:
  - source: /lib/l10n/app_zh.arb
    translation: /lib/l10n/app_%two_letters_code%.arb
    languages_mapping:
      two_letters_code:
        zh-CN: zh_Hans
        pt-BR: pt_BR
```

- [ ] **Step 2: Commit**

```bash
git add crowdin.yml
git commit -m "chore(l10n): drop ineffective skip_untranslated_files

GitHub integration does not honor it; untranslated locales are now
filtered in-app via releasedLocalesProvider.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: CI — 正規化 + commit 回分支 + 驗證

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: 改寫 ci.yml**

把 `.github/workflows/ci.yml` 整檔改為：

```yaml
name: ci

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: write

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.head_ref }}
          persist-credentials: true

      - uses: subosito/flutter-action@v2
        with:
          flutter-version-file: .fvmrc
          channel: stable
          cache: true

      - name: Normalize ARB @@locale to match filenames
        run: dart tool/normalize_arb_locale.dart

      - name: Commit normalized ARB files (same-repo PRs only)
        if: github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository
        run: |
          if [ -n "$(git status --porcelain lib/l10n)" ]; then
            git config user.name "github-actions[bot]"
            git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
            git add lib/l10n
            git commit -m "fix(l10n): normalize @@locale to match filenames"
            git push origin "HEAD:${{ github.head_ref }}"
          fi

      - run: flutter pub get

      - name: Check formatting
        run: dart format --output=none --set-exit-if-changed lib/ test/

      - name: Analyze
        run: flutter analyze

      - name: Test
        run: flutter test
```

關鍵點：
- 正規化跑在 `flutter pub get`（觸發 gen-l10n 的失敗點）**之前**；腳本零相依，免 pub get 即可執行。
- commit 步驟只在「同 repo 的 PR」且 `lib/l10n` 有 diff 時動作，用預設 `GITHUB_TOKEN`（`contents: write` + `persist-credentials`）push 回 head 分支。
- 同一次 run 內 push 後繼續在已正規化的工作樹上跑 pub get/analyze/test → 直接綠；GITHUB_TOKEN 的 push 不會再觸發新 run，無迴圈。
- `push`/master 與非 l10n PR：檔案已正確 → 無 diff → 不 commit。

- [ ] **Step 2: 本機自我檢查（YAML 語法 + 腳本 no-op）**

Run: `dart tool/normalize_arb_locale.dart`
Expected: `done, 0 file(s) normalized`（master 上 9 個 arb 的 @@locale 皆已正確）。

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: normalize @@locale before gen-l10n and commit back on Crowdin PRs

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: 最終驗證

- [ ] **Step 1: 全套品質檢查**

Run: `dart format lib/ test/ && flutter analyze && flutter test`
Expected: 三項全綠 —「No issues found!」「All tests passed!」。

- [ ] **Step 2: 確認檔案清單**

Run: `git diff --stat master`
Expected: 僅含 `tool/normalize_arb_locale.dart`、`test/tool/normalize_arb_locale_test.dart`、`lib/state/localization_metadata.dart`、`lib/main.dart`、`test/l10n/locale_metadata_test.dart`、`crowdin.yml`、`.github/workflows/ci.yml`。

- [ ] **Step 3（手動，非自動化測試）：驗 CI 行為**

合併本分支到 master 後，下一個 Crowdin「New Crowdin updates」PR 應觀察到：CI 自動 push 一個 `fix(l10n): normalize @@locale...` commit、且 `quality` 同一次 run 變綠；語言選單只出現已釋出語言（無重複「繁體中文」）。若要提前驗證，可在 fork 開一個帶 `@@locale: es-ES` 的測試 PR 觀察。

---

## Self-Review 結果

- **Spec coverage：** 元件 A → Task 1+6；元件 B → Task 2+3；元件 C → Task 4(測試)+5(crowdin.yml)。Portuguese→pt_BR 由 gate 自動處理、測試改資料無關（Task 4）。皆有對應任務。
- **Placeholder scan：** 無 TBD/TODO；每個 code step 均含完整程式碼與預期輸出。
- **Type consistency：** `normalizeArbLocales(Directory) → int`、`filterReleasedLocales({all, template, templateNativeName, nativeNameOf}) → List<Locale>`、`releasedLocalesProvider: Provider<List<Locale>>`、`localeMetadataProvider: Provider<Map<String, LocaleMetadata>>` 跨任務一致。
- **已知風險：** `dart tool/normalize_arb_locale.dart` 須能在 pub get 前執行（已以零相依保證）；若 CI 環境出現 package_config 需求，退路為在該步改用等效 shell（sed）正規化——介面與效果相同。
