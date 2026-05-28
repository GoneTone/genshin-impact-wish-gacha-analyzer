# 目前版本更新內容 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在設定頁「關於」section 新增「查看更新內容」按鈕，點擊開啟 dialog 顯示**目前安裝版本**對應的 GitHub release notes（Markdown）。

**Architecture:** 重用既有 `AppReleaseChecker` + `markdown_widget` + `AppDialog` 堆疊。新增 `fetchReleaseByVersion()` endpoint method、`ReleaseCheckNotFound` sealed 子類、`currentReleaseProvider` (Riverpod `FutureProvider.family`，自帶 in-memory cache)、抽出共用 `ReleaseNotesContent` widget、`CurrentReleaseDialog` (loading / error / data 三態殼)。

**Tech Stack:** Flutter (Dart 3 sealed classes)、`flutter_riverpod` (FutureProvider.family)、`http` + `package:http/testing.dart` MockClient、`pub_semver` (`Version.parse`)、`markdown_widget` (`MarkdownBlock`)、`logging` (`Logger`)、`fake_async` (timeout 測試)。

**Spec:** `docs/superpowers/specs/2026-05-28-current-version-release-notes-design.md`

---

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `lib/services/app_release_checker.dart` | 修改 | + `fetchReleaseByVersion()` + `ReleaseCheckNotFound` sealed 子類 |
| `lib/state/current_release.dart` | 新增 | `currentReleaseProvider = FutureProvider.family<AppRelease, String>` |
| `lib/widgets/dialogs/release_notes_content.dart` | 新增 | 共用 `ReleaseNotesContent` widget + `releaseNotesMarkdownConfig` helper |
| `lib/widgets/dialogs/new_version_dialog.dart` | 修改 | 移除 `_ReleaseCard` + `_markdownConfig`，改用 `ReleaseNotesContent` |
| `lib/widgets/dialogs/current_release_dialog.dart` | 新增 | `CurrentReleaseDialog` (ConsumerWidget) — 三態 dialog 殼 |
| `lib/pages/settings_page.dart` | 修改 | `_AboutContent` Row 加 `OutlinedButton.icon`「查看更新內容」 |
| `lib/l10n/app_zh.arb` (template) | 修改 | + 5 個新 keys |
| `lib/l10n/app_{zh_Hans,en,es,fr,ja,pt_BR,th,vi}.arb` | 修改 | + 對應翻譯 |
| `test/services/app_release_checker_test.dart` | 修改 | + `group 'fetchReleaseByVersion'` |
| `test/state/current_release_test.dart` | 新增 | provider cache / invalidate / error path 測試 |
| `test/widgets/dialogs/current_release_dialog_test.dart` | 新增 | 三態 + actions 測試 |

---

## Task 1: 實作 `fetchReleaseByVersion()` + `ReleaseCheckNotFound` (TDD)

**Files:**
- Modify: `lib/services/app_release_checker.dart` (尾端 append)
- Test: `test/services/app_release_checker_test.dart` (尾端 append)

### Step 1.1: 寫 happy path 測試

- [ ] 在 `test/services/app_release_checker_test.dart` `void main()` 最後加新 `group`：

```dart
  group('fetchReleaseByVersion — happy path', () {
    test('200 + valid JSON → AppRelease', () async {
      late Uri requested;
      final client = MockClient((req) async {
        requested = req.url;
        return http.Response(
          jsonEncode(_release(
            tag: 'v1.1.0',
            published: '2026-05-27T00:00:00Z',
            name: 'v1.1.0',
            body: '## Features\n- foo\n- bar',
            htmlUrl: 'https://github.com/o/r/releases/tag/v1.1.0',
          )),
          200,
        );
      });

      final release = await fetchReleaseByVersion(
        version: '1.1.0',
        client: client,
      );

      expect(requested.path, endsWith('/releases/tags/v1.1.0'));
      expect(release.tagName, 'v1.1.0');
      expect(release.version, '1.1.0');
      expect(release.name, 'v1.1.0');
      expect(release.body, '## Features\n- foo\n- bar');
      expect(release.htmlUrl, 'https://github.com/o/r/releases/tag/v1.1.0');
      expect(release.publishedAt, DateTime.utc(2026, 5, 27));
    });

    test('version 帶 build metadata → endpoint 用核心 SemVer', () async {
      late Uri requested;
      final client = MockClient((req) async {
        requested = req.url;
        return http.Response(
          jsonEncode(_release(
            tag: 'v1.1.0',
            published: '2026-05-27T00:00:00Z',
          )),
          200,
        );
      });

      await fetchReleaseByVersion(version: '1.1.0+2', client: client);

      expect(requested.path, endsWith('/releases/tags/v1.1.0'));
    });
  });
```

註：`_release()` helper 已在檔案上方既有；只多了一個 `htmlUrl` 參數有預設值，傳什麼都 OK。

### Step 1.2: 跑測試確認 fail

- [ ] 執行：

```
flutter test test/services/app_release_checker_test.dart --plain-name "fetchReleaseByVersion"
```

Expected: FAIL 並提示 `fetchReleaseByVersion` 未定義。

### Step 1.3: 實作 `ReleaseCheckNotFound` + `fetchReleaseByVersion`

- [ ] 在 `lib/services/app_release_checker.dart` 既有 `ReleaseCheckFormat` 類別後面（約第 77 行後）加：

```dart
/// 找不到指定 tag 對應的 release（HTTP 404）。
class ReleaseCheckNotFound extends ReleaseCheckError {
  /// 建立 [ReleaseCheckNotFound]，[tag] 為查詢的 tag（含 v 前綴）。
  const ReleaseCheckNotFound(this.tag);

  /// 查詢的 tag，例如 `v1.1.0`。
  final String tag;
}
```

- [ ] 在檔案最尾端（`fetchNewerReleases` 函式結束後）加：

```dart
/// 抓指定 [version] 對應的單一 GitHub Release。
///
/// [version] 可帶 SemVer build metadata（例如 `1.1.0+2`，這是 Flutter
/// `pubspec.yaml` / `PackageInfo.version` 的標準格式）；內部會剝掉 build
/// metadata、補上 `v` 前綴後組成 tag（如 `v1.1.0`）查詢。
///
/// 與 [fetchNewerReleases] 不同，這個函式不過濾 `draft` / `prerelease`；
/// 使用者主動查指定 tag 即表示想看那個版本，無論其發佈狀態。
///
/// 失敗時拋 [ReleaseCheckError] 的具體子類；指定 tag 不存在時拋
/// [ReleaseCheckNotFound]。
Future<AppRelease> fetchReleaseByVersion({
  required String version,
  required http.Client client,
}) async {
  final Version parsed;
  try {
    parsed = Version.parse(version);
  } catch (_) {
    throw const ReleaseCheckFormat();
  }
  final core = '${parsed.major}.${parsed.minor}.${parsed.patch}';
  final tag = 'v$core';
  final uri = Uri.parse('${AppRepo.apiBase}/releases/tags/$tag');

  final http.Response resp;
  try {
    resp = await client
        .get(uri, headers: const {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 10));
  } on TimeoutException {
    throw const ReleaseCheckTimeout();
  } on SocketException {
    throw const ReleaseCheckNetwork();
  } on http.ClientException {
    throw const ReleaseCheckNetwork();
  }

  if (resp.statusCode == 404) {
    throw ReleaseCheckNotFound(tag);
  }
  if (resp.statusCode == 429 ||
      (resp.statusCode == 403 &&
          resp.headers['x-ratelimit-remaining'] == '0')) {
    throw const ReleaseCheckRateLimited();
  }
  if (resp.statusCode != 200) {
    throw ReleaseCheckServer(resp.statusCode);
  }

  final dynamic decoded;
  try {
    decoded = jsonDecode(resp.body);
  } on FormatException {
    throw const ReleaseCheckFormat();
  }
  if (decoded is! Map) throw const ReleaseCheckFormat();
  final raw = decoded;
  final tagName = raw['tag_name'];
  if (tagName is! String) throw const ReleaseCheckFormat();
  final parsedTag = _parseTag(tagName);
  if (parsedTag == null) throw const ReleaseCheckFormat();
  final published = DateTime.tryParse(raw['published_at']?.toString() ?? '');
  if (published == null) throw const ReleaseCheckFormat();

  return AppRelease(
    tagName: tagName,
    version: parsedTag.toString(),
    name: (raw['name'] as String?) ?? '',
    body: (raw['body'] as String?) ?? '',
    htmlUrl: (raw['html_url'] as String?) ?? '',
    publishedAt: published,
  );
}
```

### Step 1.4: 跑 happy path 測試確認 pass

- [ ] 執行：

```
flutter test test/services/app_release_checker_test.dart --plain-name "fetchReleaseByVersion"
```

Expected: 兩個 happy path 測試 PASS。

### Step 1.5: 加完整錯誤情境測試

- [ ] 在 Step 1.1 加的 group 之後再加：

```dart
  group('fetchReleaseByVersion — errors', () {
    test('404 → ReleaseCheckNotFound (tag = v1.1.0)', () async {
      final client = MockClient(
        (_) async => http.Response('Not Found', 404),
      );
      try {
        await fetchReleaseByVersion(version: '1.1.0', client: client);
        fail('expected throw');
      } on ReleaseCheckNotFound catch (e) {
        expect(e.tag, 'v1.1.0');
      }
    });

    test('5xx → ReleaseCheckServer(status)', () async {
      final client = MockClient(
        (_) async => http.Response('boom', 503),
      );
      try {
        await fetchReleaseByVersion(version: '1.1.0', client: client);
        fail('expected throw');
      } on ReleaseCheckServer catch (e) {
        expect(e.status, 503);
      }
    });

    test('429 → ReleaseCheckRateLimited', () async {
      final client = MockClient(
        (_) async => http.Response('rate limited', 429),
      );
      expect(
        () => fetchReleaseByVersion(version: '1.1.0', client: client),
        throwsA(isA<ReleaseCheckRateLimited>()),
      );
    });

    test('403 + x-ratelimit-remaining: 0 → ReleaseCheckRateLimited', () async {
      final client = MockClient(
        (_) async => http.Response(
          'forbidden',
          403,
          headers: const {'x-ratelimit-remaining': '0'},
        ),
      );
      expect(
        () => fetchReleaseByVersion(version: '1.1.0', client: client),
        throwsA(isA<ReleaseCheckRateLimited>()),
      );
    });

    test('200 但 body 不是 JSON object → ReleaseCheckFormat', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode([1, 2, 3]), 200),
      );
      expect(
        () => fetchReleaseByVersion(version: '1.1.0', client: client),
        throwsA(isA<ReleaseCheckFormat>()),
      );
    });

    test('200 但缺 tag_name → ReleaseCheckFormat', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'published_at': '2026-05-27T00:00:00Z'}),
          200,
        ),
      );
      expect(
        () => fetchReleaseByVersion(version: '1.1.0', client: client),
        throwsA(isA<ReleaseCheckFormat>()),
      );
    });

    test('200 但 tag_name 無法 parse → ReleaseCheckFormat', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'tag_name': 'weird-tag',
            'published_at': '2026-05-27T00:00:00Z',
          }),
          200,
        ),
      );
      expect(
        () => fetchReleaseByVersion(version: '1.1.0', client: client),
        throwsA(isA<ReleaseCheckFormat>()),
      );
    });

    test('SocketException → ReleaseCheckNetwork', () async {
      final client = MockClient((_) async {
        throw const SocketException('offline');
      });
      expect(
        () => fetchReleaseByVersion(version: '1.1.0', client: client),
        throwsA(isA<ReleaseCheckNetwork>()),
      );
    });

    test('http.ClientException → ReleaseCheckNetwork', () async {
      final client = MockClient((_) async {
        throw http.ClientException('connection reset');
      });
      expect(
        () => fetchReleaseByVersion(version: '1.1.0', client: client),
        throwsA(isA<ReleaseCheckNetwork>()),
      );
    });

    test('TimeoutException 觸發 → ReleaseCheckTimeout', () {
      fakeAsync((async) {
        final client = MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 15));
          return http.Response(
            jsonEncode(_release(
              tag: 'v1.1.0',
              published: '2026-05-27T00:00:00Z',
            )),
            200,
          );
        });

        Object? caught;
        fetchReleaseByVersion(version: '1.1.0', client: client).then(
          (_) {},
          onError: (Object e) {
            caught = e;
          },
        );

        async.elapse(const Duration(seconds: 11));

        expect(caught, isA<ReleaseCheckTimeout>());
      });
    });

    test('version 無法 parse → ReleaseCheckFormat', () async {
      final client = MockClient((_) async => http.Response('', 200));
      expect(
        () => fetchReleaseByVersion(version: 'not-a-version', client: client),
        throwsA(isA<ReleaseCheckFormat>()),
      );
    });
  });
```

### Step 1.6: 跑全部 fetchReleaseByVersion 測試確認 pass

- [ ] 執行：

```
flutter test test/services/app_release_checker_test.dart
```

Expected: All tests passed!（含既有 + 新加的）

### Step 1.7: 提交前品質檢查

- [ ] 依 CLAUDE.md 規矩：

```
dart format lib/ test/
flutter analyze
flutter test
```

Expected: `dart format` 無 issue、`flutter analyze` 顯示 `No issues found!`、`flutter test` 顯示 `All tests passed!`。

### Step 1.8: Commit

- [ ] 執行：

```bash
git add lib/services/app_release_checker.dart test/services/app_release_checker_test.dart
git commit -m "$(cat <<'EOF'
feat(release-checker): add fetchReleaseByVersion + ReleaseCheckNotFound

Add a new endpoint method to fetch a single GitHub release by version,
plus a sealed subclass for 404 responses. Strips SemVer build metadata
before composing the v-prefixed tag (e.g. "1.1.0+2" -> "v1.1.0"). Does
NOT filter draft/prerelease — caller explicitly asked for that tag.

Used by the upcoming "view current version release notes" entry in the
Settings > About section.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: 新增 `currentReleaseProvider` (FutureProvider.family) + 測試

**Files:**
- Create: `lib/state/current_release.dart`
- Create: `test/state/current_release_test.dart`

### Step 2.1: 寫 provider 測試

- [ ] 建立新檔 `test/state/current_release_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart'
    show httpClientProvider;
import 'package:genshin_impact_wish_gacha_analyzer/state/current_release.dart';

Map<String, dynamic> _releaseJson(String tag, String published) => {
  'tag_name': tag,
  'name': tag,
  'body': '## body for $tag',
  'prerelease': false,
  'draft': false,
  'html_url': 'https://github.com/o/r/releases/tag/$tag',
  'published_at': published,
};

ProviderContainer _container(http.Client client) {
  final container = ProviderContainer(
    overrides: [httpClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('首次 watch → 打一次 API，state 變 AsyncData', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(_releaseJson('v1.1.0', '2026-05-27T00:00:00Z')),
        200,
      ),
    );
    final container = _container(client);

    final release = await container.read(
      currentReleaseProvider('1.1.0').future,
    );

    expect(release.tagName, 'v1.1.0');
    final state = container.read(currentReleaseProvider('1.1.0'));
    expect(state.hasValue, isTrue);
    expect(state.value?.tagName, 'v1.1.0');
  });

  test('重複 read 同一 version → 不重打 API（FutureProvider.family cache）', () async {
    var callCount = 0;
    final client = MockClient((_) async {
      callCount++;
      return http.Response(
        jsonEncode(_releaseJson('v1.1.0', '2026-05-27T00:00:00Z')),
        200,
      );
    });
    final container = _container(client);

    await container.read(currentReleaseProvider('1.1.0').future);
    await container.read(currentReleaseProvider('1.1.0').future);
    await container.read(currentReleaseProvider('1.1.0').future);

    expect(callCount, 1);
  });

  test('不同 version key → 各自打一次 API', () async {
    final calledFor = <String>[];
    final client = MockClient((req) async {
      calledFor.add(req.url.path);
      final tag = req.url.path.split('/').last;
      return http.Response(
        jsonEncode(_releaseJson(tag, '2026-05-27T00:00:00Z')),
        200,
      );
    });
    final container = _container(client);

    await container.read(currentReleaseProvider('1.0.0').future);
    await container.read(currentReleaseProvider('1.1.0').future);

    expect(calledFor.where((p) => p.endsWith('v1.0.0')).length, 1);
    expect(calledFor.where((p) => p.endsWith('v1.1.0')).length, 1);
  });

  test('ref.invalidate → 重新 fetch', () async {
    var callCount = 0;
    final client = MockClient((_) async {
      callCount++;
      return http.Response(
        jsonEncode(_releaseJson('v1.1.0', '2026-05-27T00:00:00Z')),
        200,
      );
    });
    final container = _container(client);

    await container.read(currentReleaseProvider('1.1.0').future);
    expect(callCount, 1);

    container.invalidate(currentReleaseProvider('1.1.0'));
    await container.read(currentReleaseProvider('1.1.0').future);
    expect(callCount, 2);
  });

  test('service 拋 ReleaseCheckNotFound → state 變 AsyncError', () async {
    final client = MockClient(
      (_) async => http.Response('Not Found', 404),
    );
    final container = _container(client);

    try {
      await container.read(currentReleaseProvider('1.1.0').future);
      fail('expected throw');
    } on ReleaseCheckNotFound catch (e) {
      expect(e.tag, 'v1.1.0');
    }
    final state = container.read(currentReleaseProvider('1.1.0'));
    expect(state.hasError, isTrue);
    expect(state.error, isA<ReleaseCheckNotFound>());
  });

  test('service 拋 ReleaseCheckServer → state 變 AsyncError', () async {
    final client = MockClient(
      (_) async => http.Response('boom', 503),
    );
    final container = _container(client);

    try {
      await container.read(currentReleaseProvider('1.1.0').future);
      fail('expected throw');
    } on ReleaseCheckServer catch (e) {
      expect(e.status, 503);
    }
    expect(
      container.read(currentReleaseProvider('1.1.0')).error,
      isA<ReleaseCheckServer>(),
    );
  });
}
```

### Step 2.2: 跑測試確認 fail

- [ ] 執行：

```
flutter test test/state/current_release_test.dart
```

Expected: FAIL 並提示 `current_release.dart` 找不到。

### Step 2.3: 建檔實作 provider

- [ ] 建立新檔 `lib/state/current_release.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart'
    show httpClientProvider;

/// 依 version key 抓對應的 GitHub Release，自帶 in-memory cache。
///
/// 同一 `version` 重複 watch 不會重打 API；要強制重新 fetch，呼叫
/// `ref.invalidate(currentReleaseProvider(version))`。
///
/// 失敗時 future 會拋 [ReleaseCheckError] 的具體子類，UI 端用
/// `AsyncValue.when(error: ...)` 處理。
final currentReleaseProvider = FutureProvider.family<AppRelease, String>(
  (ref, version) async {
    Logger('release.notes').info('fetch start version=$version');
    final client = ref.read(httpClientProvider);
    try {
      final release = await fetchReleaseByVersion(
        version: version,
        client: client,
      );
      Logger('release.notes').info('fetch success tag=${release.tagName}');
      return release;
    } on ReleaseCheckError catch (e) {
      Logger('release.notes').warning('fetch failed version=$version: $e');
      rethrow;
    }
  },
);
```

### Step 2.4: 跑測試確認 pass

- [ ] 執行：

```
flutter test test/state/current_release_test.dart
```

Expected: All tests passed!

### Step 2.5: 提交前品質檢查

- [ ] 執行：

```
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 全綠。

### Step 2.6: Commit

- [ ] 執行：

```bash
git add lib/state/current_release.dart test/state/current_release_test.dart
git commit -m "$(cat <<'EOF'
feat(state): add currentReleaseProvider FutureProvider.family

A version-keyed FutureProvider that fetches the GitHub release for the
given version. FutureProvider.family provides in-memory caching for free
(same version key is not refetched within app lifetime); UI calls
ref.invalidate(currentReleaseProvider(version)) to force a refresh.

Errors propagate as the native ReleaseCheckError sealed subclasses so
UI layer can render specific messages per error type.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: 抽出 `ReleaseNotesContent` widget + 重構 `NewVersionDialog`

**Files:**
- Create: `lib/widgets/dialogs/release_notes_content.dart`
- Modify: `lib/widgets/dialogs/new_version_dialog.dart`

### Step 3.1: 建立共用 content widget

- [ ] 建立新檔 `lib/widgets/dialogs/release_notes_content.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/relative_time_text.dart';

/// 單一 release 的內容卡片：版本標題 + 發布時間 + Markdown body。
/// 由 `NewVersionDialog` 與 `CurrentReleaseDialog` 共用。
class ReleaseNotesContent extends StatelessWidget {
  /// 建立 [ReleaseNotesContent]。
  const ReleaseNotesContent({super.key, required this.release});

  /// 要呈現的 release 資料。
  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  release.tagName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                RelativeTimeText(
                  time: release.publishedAt,
                  templateBuilder: l.updateReleasedAt,
                  useDateOnly: true,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Divider(height: 1, color: tokens.borderSubtle),
            const SizedBox(height: AppSpacing.s),
            if (release.body.isNotEmpty)
              MarkdownBlock(
                data: release.body,
                config: releaseNotesMarkdownConfig(theme),
              ),
          ],
        ),
      ),
    );
  }
}

/// 依 [theme] 亮暗模式建立 markdown 渲染設定，統一連結樣式。
MarkdownConfig releaseNotesMarkdownConfig(ThemeData theme) {
  final base = theme.brightness == Brightness.dark
      ? MarkdownConfig.darkConfig
      : MarkdownConfig.defaultConfig;
  return base.copy(
    configs: [LinkConfig(style: TextStyle(color: linkBaseColor(theme)))],
  );
}
```

### Step 3.2: 重構 `NewVersionDialog` 改用 `ReleaseNotesContent`

- [ ] 修改 `lib/widgets/dialogs/new_version_dialog.dart`，整檔覆寫為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/release_notes_content.dart';

/// 新版本通知 dialog，列出自上次版本以來的所有 release notes。
class NewVersionDialog extends ConsumerWidget {
  /// 建立 [NewVersionDialog]，需傳入要顯示的 release 列表。
  const NewVersionDialog({super.key, required this.releases});

  /// 需要顯示的 release 列表（最新版在前）。
  final List<AppRelease> releases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final latest = releases.first;

    return AppDialog(
      size: AppDialogSize.lg,
      scrollable: true,
      title: Row(
        children: [
          Icon(Icons.system_update, color: tokens.stateSuccess),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: Text(l.updateTitle(latest.tagName))),
        ],
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < releases.length; i++) ...[
            ReleaseNotesContent(release: releases[i]),
            if (i < releases.length - 1) const SizedBox(height: AppSpacing.m),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await ref
                .read(appReleaseProvider.notifier)
                .skipVersion(latest.tagName);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(l.updateButtonSkip),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.updateButtonLater),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download),
          label: Text(l.updateButtonDownload),
          onPressed: () async {
            await openExternalUrl(Uri.parse(latest.htmlUrl));
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
```

註：移除了既有的 `_ReleaseCard` private 類別與 `_markdownConfig` private 函式，視覺與行為完全等價，但程式碼移到 `release_notes_content.dart`。

### Step 3.3: 提交前品質檢查

- [ ] 執行：

```
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 全綠。本 task 沒新增測試（重構，依靠 analyze 守住型別、靠人工驗證視覺），但既有測試應不受影響。

### Step 3.4: Commit

- [ ] 執行：

```bash
git add lib/widgets/dialogs/release_notes_content.dart lib/widgets/dialogs/new_version_dialog.dart
git commit -m "$(cat <<'EOF'
refactor(dialogs): extract ReleaseNotesContent shared widget

Pull the single-release rendering ("_ReleaseCard" + "_markdownConfig")
out of new_version_dialog.dart into a standalone widget that the
upcoming CurrentReleaseDialog can reuse. NewVersionDialog now composes
it; visual and behavioural output is unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: 新增 i18n keys 到 `app_zh.arb` (template) 並 gen-l10n

**Files:**
- Modify: `lib/l10n/app_zh.arb`

### Step 4.1: 加 5 個 keys 到 template

- [ ] 編輯 `lib/l10n/app_zh.arb`，在 `updateErrorFormat` 後（第 536 行附近）插入：

```json
  "currentReleaseTitle": "目前版本更新內容",
  "@currentReleaseTitle": {
    "description": "Title of the dialog showing release notes for the currently installed version."
  },
  "currentReleaseNotFound": "找不到 {version} 對應的更新內容",
  "@currentReleaseNotFound": {
    "description": "Shown inside the current-release dialog when GitHub returns 404 for the version's tag.",
    "placeholders": { "version": { "type": "String" } }
  },
  "currentReleaseOpenOnGithub": "在 GitHub 上開啟",
  "@currentReleaseOpenOnGithub": {
    "description": "Action button: open this release page on github.com in the external browser."
  },
  "currentReleaseOpenReleasesPage": "開啟 GitHub Releases 頁面",
  "@currentReleaseOpenReleasesPage": {
    "description": "Action button shown when no release was found / rate-limited: open the repo's GitHub Releases listing."
  },
  "aboutViewReleaseNotes": "查看更新內容",
  "@aboutViewReleaseNotes": {
    "description": "Settings > About: button next to the version label that opens the current-release dialog."
  },
```

確認 JSON 語法仍有效（前面條目的 `,` 結尾、自己的條目之間也用 `,`、最後一個條目接續到原本檔案的下一條，最後不要殘留 `,,`）。

### Step 4.2: 跑 gen-l10n

- [ ] 執行：

```
flutter gen-l10n
```

Expected: 重新產生 `lib/l10n/generated/app_localizations*.dart`。無錯誤輸出。

### Step 4.3: 提交前品質檢查

- [ ] 執行：

```
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 全綠。Generated 檔會被 format 改動，這正常。

### Step 4.4: Commit

- [ ] 執行：

```bash
git add lib/l10n/app_zh.arb lib/l10n/generated/
git commit -m "$(cat <<'EOF'
feat(i18n): add zh-Hant strings for current-version release notes dialog

Add 5 new keys (currentReleaseTitle, currentReleaseNotFound,
currentReleaseOpenOnGithub, currentReleaseOpenReleasesPage,
aboutViewReleaseNotes) to the template ARB and regenerate. Reuses
existing update*/actionClose/actionRetry strings for everything else.

Translations for other non-empty locales follow in the next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: 翻譯 i18n keys 到其他 8 個非空殼 ARB

**Files (each modified):**
- `lib/l10n/app_zh_Hans.arb`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_es.arb`
- `lib/l10n/app_fr.arb`
- `lib/l10n/app_ja.arb`
- `lib/l10n/app_pt_BR.arb`
- `lib/l10n/app_th.arb`
- `lib/l10n/app_vi.arb`

22 個空殼 ARB（`af, ar, ca, cs, da, de, el, fi, he, hu, it, ko, nl, no, pl, pt, ro, ru, sr, sv, tr, uk`）**不動**，依專案規矩留給 Crowdin pipeline 同步。

每個 ARB 的插入位置都是「`updateErrorFormat` 條目之後」（找該 key 確定位置；不同檔案附近可能有其他 `update*` 變體例如 `updateErrorWipeHoyoWikiCache`，插在 `updateErrorFormat` 後但 `updateErrorWipeHoyoWikiCache` 前即可，或統一插在所有 `update*` 結束後）。`@metadata` 區塊與 zh 範本相同（description 用英文、placeholder 結構相同），下面表格只列 value 字串。

### Step 5.1: 加翻譯到 `app_zh_Hans.arb` (簡中)

- [ ] 在 `lib/l10n/app_zh_Hans.arb` 內加：

```json
  "currentReleaseTitle": "当前版本更新内容",
  "@currentReleaseTitle": { "description": "Title of the dialog showing release notes for the currently installed version." },
  "currentReleaseNotFound": "找不到 {version} 对应的更新内容",
  "@currentReleaseNotFound": {
    "description": "Shown inside the current-release dialog when GitHub returns 404 for the version's tag.",
    "placeholders": { "version": { "type": "String" } }
  },
  "currentReleaseOpenOnGithub": "在 GitHub 上打开",
  "@currentReleaseOpenOnGithub": { "description": "Action button: open this release page on github.com in the external browser." },
  "currentReleaseOpenReleasesPage": "打开 GitHub Releases 页面",
  "@currentReleaseOpenReleasesPage": { "description": "Action button shown when no release was found / rate-limited: open the repo's GitHub Releases listing." },
  "aboutViewReleaseNotes": "查看更新内容",
  "@aboutViewReleaseNotes": { "description": "Settings > About: button next to the version label that opens the current-release dialog." },
```

### Step 5.2: 加翻譯到 `app_en.arb` (英文)

- [ ] 在 `lib/l10n/app_en.arb` 內加（注意 metadata 完整與 zh template 對齊）：

```json
  "currentReleaseTitle": "Current release notes",
  "@currentReleaseTitle": { "description": "Title of the dialog showing release notes for the currently installed version." },
  "currentReleaseNotFound": "Release notes not found for {version}",
  "@currentReleaseNotFound": {
    "description": "Shown inside the current-release dialog when GitHub returns 404 for the version's tag.",
    "placeholders": { "version": { "type": "String" } }
  },
  "currentReleaseOpenOnGithub": "Open on GitHub",
  "@currentReleaseOpenOnGithub": { "description": "Action button: open this release page on github.com in the external browser." },
  "currentReleaseOpenReleasesPage": "Open GitHub Releases page",
  "@currentReleaseOpenReleasesPage": { "description": "Action button shown when no release was found / rate-limited: open the repo's GitHub Releases listing." },
  "aboutViewReleaseNotes": "View release notes",
  "@aboutViewReleaseNotes": { "description": "Settings > About: button next to the version label that opens the current-release dialog." },
```

### Step 5.3: 加翻譯到 `app_es.arb` (西班牙文)

- [ ] 在 `lib/l10n/app_es.arb` 內加：

```json
  "currentReleaseTitle": "Notas de la versión actual",
  "@currentReleaseTitle": { "description": "Title of the dialog showing release notes for the currently installed version." },
  "currentReleaseNotFound": "Notas de la versión no encontradas para {version}",
  "@currentReleaseNotFound": {
    "description": "Shown inside the current-release dialog when GitHub returns 404 for the version's tag.",
    "placeholders": { "version": { "type": "String" } }
  },
  "currentReleaseOpenOnGithub": "Abrir en GitHub",
  "@currentReleaseOpenOnGithub": { "description": "Action button: open this release page on github.com in the external browser." },
  "currentReleaseOpenReleasesPage": "Abrir página de GitHub Releases",
  "@currentReleaseOpenReleasesPage": { "description": "Action button shown when no release was found / rate-limited: open the repo's GitHub Releases listing." },
  "aboutViewReleaseNotes": "Ver notas de la versión",
  "@aboutViewReleaseNotes": { "description": "Settings > About: button next to the version label that opens the current-release dialog." },
```

### Step 5.4: 加翻譯到 `app_fr.arb` (法文)

- [ ] 在 `lib/l10n/app_fr.arb` 內加：

```json
  "currentReleaseTitle": "Notes de version actuelles",
  "@currentReleaseTitle": { "description": "Title of the dialog showing release notes for the currently installed version." },
  "currentReleaseNotFound": "Notes de version introuvables pour {version}",
  "@currentReleaseNotFound": {
    "description": "Shown inside the current-release dialog when GitHub returns 404 for the version's tag.",
    "placeholders": { "version": { "type": "String" } }
  },
  "currentReleaseOpenOnGithub": "Ouvrir sur GitHub",
  "@currentReleaseOpenOnGithub": { "description": "Action button: open this release page on github.com in the external browser." },
  "currentReleaseOpenReleasesPage": "Ouvrir la page des versions GitHub",
  "@currentReleaseOpenReleasesPage": { "description": "Action button shown when no release was found / rate-limited: open the repo's GitHub Releases listing." },
  "aboutViewReleaseNotes": "Voir les notes de version",
  "@aboutViewReleaseNotes": { "description": "Settings > About: button next to the version label that opens the current-release dialog." },
```

### Step 5.5: 加翻譯到 `app_ja.arb` (日文)

- [ ] 在 `lib/l10n/app_ja.arb` 內加：

```json
  "currentReleaseTitle": "現在のバージョンの更新内容",
  "@currentReleaseTitle": { "description": "Title of the dialog showing release notes for the currently installed version." },
  "currentReleaseNotFound": "{version} に対応するリリースノートが見つかりません",
  "@currentReleaseNotFound": {
    "description": "Shown inside the current-release dialog when GitHub returns 404 for the version's tag.",
    "placeholders": { "version": { "type": "String" } }
  },
  "currentReleaseOpenOnGithub": "GitHub で開く",
  "@currentReleaseOpenOnGithub": { "description": "Action button: open this release page on github.com in the external browser." },
  "currentReleaseOpenReleasesPage": "GitHub Releases ページを開く",
  "@currentReleaseOpenReleasesPage": { "description": "Action button shown when no release was found / rate-limited: open the repo's GitHub Releases listing." },
  "aboutViewReleaseNotes": "更新内容を表示",
  "@aboutViewReleaseNotes": { "description": "Settings > About: button next to the version label that opens the current-release dialog." },
```

### Step 5.6: 加翻譯到 `app_pt_BR.arb` (巴西葡文)

- [ ] 在 `lib/l10n/app_pt_BR.arb` 內加：

```json
  "currentReleaseTitle": "Notas da versão atual",
  "@currentReleaseTitle": { "description": "Title of the dialog showing release notes for the currently installed version." },
  "currentReleaseNotFound": "Notas da versão não encontradas para {version}",
  "@currentReleaseNotFound": {
    "description": "Shown inside the current-release dialog when GitHub returns 404 for the version's tag.",
    "placeholders": { "version": { "type": "String" } }
  },
  "currentReleaseOpenOnGithub": "Abrir no GitHub",
  "@currentReleaseOpenOnGithub": { "description": "Action button: open this release page on github.com in the external browser." },
  "currentReleaseOpenReleasesPage": "Abrir página de Releases do GitHub",
  "@currentReleaseOpenReleasesPage": { "description": "Action button shown when no release was found / rate-limited: open the repo's GitHub Releases listing." },
  "aboutViewReleaseNotes": "Ver notas da versão",
  "@aboutViewReleaseNotes": { "description": "Settings > About: button next to the version label that opens the current-release dialog." },
```

### Step 5.7: 加翻譯到 `app_th.arb` (泰文)

- [ ] 在 `lib/l10n/app_th.arb` 內加：

```json
  "currentReleaseTitle": "บันทึกการอัปเดตเวอร์ชันปัจจุบัน",
  "@currentReleaseTitle": { "description": "Title of the dialog showing release notes for the currently installed version." },
  "currentReleaseNotFound": "ไม่พบบันทึกการอัปเดตสำหรับ {version}",
  "@currentReleaseNotFound": {
    "description": "Shown inside the current-release dialog when GitHub returns 404 for the version's tag.",
    "placeholders": { "version": { "type": "String" } }
  },
  "currentReleaseOpenOnGithub": "เปิดใน GitHub",
  "@currentReleaseOpenOnGithub": { "description": "Action button: open this release page on github.com in the external browser." },
  "currentReleaseOpenReleasesPage": "เปิดหน้า GitHub Releases",
  "@currentReleaseOpenReleasesPage": { "description": "Action button shown when no release was found / rate-limited: open the repo's GitHub Releases listing." },
  "aboutViewReleaseNotes": "ดูบันทึกการอัปเดต",
  "@aboutViewReleaseNotes": { "description": "Settings > About: button next to the version label that opens the current-release dialog." },
```

### Step 5.8: 加翻譯到 `app_vi.arb` (越南文)

- [ ] 在 `lib/l10n/app_vi.arb` 內加：

```json
  "currentReleaseTitle": "Ghi chú phát hành phiên bản hiện tại",
  "@currentReleaseTitle": { "description": "Title of the dialog showing release notes for the currently installed version." },
  "currentReleaseNotFound": "Không tìm thấy ghi chú phát hành cho {version}",
  "@currentReleaseNotFound": {
    "description": "Shown inside the current-release dialog when GitHub returns 404 for the version's tag.",
    "placeholders": { "version": { "type": "String" } }
  },
  "currentReleaseOpenOnGithub": "Mở trên GitHub",
  "@currentReleaseOpenOnGithub": { "description": "Action button: open this release page on github.com in the external browser." },
  "currentReleaseOpenReleasesPage": "Mở trang GitHub Releases",
  "@currentReleaseOpenReleasesPage": { "description": "Action button shown when no release was found / rate-limited: open the repo's GitHub Releases listing." },
  "aboutViewReleaseNotes": "Xem ghi chú phát hành",
  "@aboutViewReleaseNotes": { "description": "Settings > About: button next to the version label that opens the current-release dialog." },
```

### Step 5.9: 跑 gen-l10n + 提交前品質檢查

- [ ] 執行：

```
flutter gen-l10n
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 全綠。Generated 檔會更新。

### Step 5.10: Commit

- [ ] 執行：

```bash
git add lib/l10n/app_zh_Hans.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_ja.arb lib/l10n/app_pt_BR.arb lib/l10n/app_th.arb lib/l10n/app_vi.arb lib/l10n/generated/
git commit -m "$(cat <<'EOF'
feat(i18n): translate current-release dialog strings to 8 locales

Add zh_Hans/en/es/fr/ja/pt_BR/th/vi translations for the 5 new keys.
Empty-shell ARBs (af/ar/ca/cs/da/de/el/fi/he/hu/it/ko/nl/no/pl/pt/ro/
ru/sr/sv/tr/uk) are left untouched per project convention — they are
synced from Crowdin downstream.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: 實作 `CurrentReleaseDialog` + widget 測試

**Files:**
- Create: `lib/widgets/dialogs/current_release_dialog.dart`
- Create: `test/widgets/dialogs/current_release_dialog_test.dart`

### Step 6.1: 寫 widget 測試

- [ ] 建立新檔 `test/widgets/dialogs/current_release_dialog_test.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/current_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/current_release_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/release_notes_content.dart';

AppRelease _release({
  String tag = 'v1.1.0',
  String body = '## Hi',
}) => AppRelease(
  tagName: tag,
  version: tag.startsWith('v') ? tag.substring(1) : tag,
  name: tag,
  body: body,
  htmlUrl: 'https://github.com/o/r/releases/tag/$tag',
  publishedAt: DateTime.utc(2026, 5, 27),
);

/// Pump a Riverpod-scoped app that opens [CurrentReleaseDialog] with the
/// given provider override and waits for the dialog to settle.
Future<void> _pumpDialog(
  WidgetTester tester, {
  required Override currentReleaseOverride,
  String version = '1.1.0',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [currentReleaseOverride],
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => CurrentReleaseDialog(version: version),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump(); // open dialog frame
}

void main() {
  testWidgets('data state → renders ReleaseNotesContent + [Open on GitHub] [Close]',
      (tester) async {
    final release = _release();
    await _pumpDialog(
      tester,
      currentReleaseOverride: currentReleaseProvider('1.1.0')
          .overrideWith((ref) async => release),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReleaseNotesContent), findsOneWidget);
    expect(find.text('Open on GitHub'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('loading state → no ReleaseNotesContent yet, only [Close]',
      (tester) async {
    final completer = Completer<AppRelease>();
    await _pumpDialog(
      tester,
      currentReleaseOverride: currentReleaseProvider('1.1.0')
          .overrideWith((ref) => completer.future),
    );
    // 不 pumpAndSettle，保持 loading 狀態

    expect(find.byType(ReleaseNotesContent), findsNothing);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Open on GitHub'), findsNothing);

    completer.complete(_release());
    await tester.pumpAndSettle();
  });

  testWidgets('ReleaseCheckNotFound → renders not-found message + [Open Releases page] [Close]',
      (tester) async {
    await _pumpDialog(
      tester,
      currentReleaseOverride: currentReleaseProvider('1.1.0')
          .overrideWith((ref) => Future.error(const ReleaseCheckNotFound('v1.1.0'))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Release notes not found for 1.1.0'), findsOneWidget);
    expect(find.text('Open GitHub Releases page'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('ReleaseCheckRateLimited → [Open Releases page] [Close]',
      (tester) async {
    await _pumpDialog(
      tester,
      currentReleaseOverride: currentReleaseProvider('1.1.0')
          .overrideWith((ref) => Future.error(const ReleaseCheckRateLimited())),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('quota'), findsOneWidget); // updateErrorRateLimited
    expect(find.text('Open GitHub Releases page'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('ReleaseCheckNetwork → [Retry] [Close]', (tester) async {
    await _pumpDialog(
      tester,
      currentReleaseOverride: currentReleaseProvider('1.1.0')
          .overrideWith((ref) => Future.error(const ReleaseCheckNetwork())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Open GitHub Releases page'), findsNothing);
  });

  testWidgets('ReleaseCheckServer(503) → [Retry] [Close] with status code visible',
      (tester) async {
    await _pumpDialog(
      tester,
      currentReleaseOverride: currentReleaseProvider('1.1.0')
          .overrideWith((ref) => Future.error(const ReleaseCheckServer(503))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('503'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Retry → ref.invalidate triggers refetch', (tester) async {
    var fetches = 0;
    Override buildOverride() => currentReleaseProvider('1.1.0').overrideWith(
          (ref) {
            fetches++;
            if (fetches == 1) {
              return Future.error(const ReleaseCheckNetwork());
            }
            return Future.value(_release());
          },
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [buildOverride()],
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: ctx,
                    builder: (_) => const CurrentReleaseDialog(version: '1.1.0'),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(fetches, greaterThanOrEqualTo(2));
    expect(find.byType(ReleaseNotesContent), findsOneWidget);
  });

  testWidgets('Close → dialog dismissed', (tester) async {
    await _pumpDialog(
      tester,
      currentReleaseOverride: currentReleaseProvider('1.1.0')
          .overrideWith((ref) async => _release()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CurrentReleaseDialog), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(CurrentReleaseDialog), findsNothing);
  });
}
```

### Step 6.2: 跑測試確認 fail

- [ ] 執行：

```
flutter test test/widgets/dialogs/current_release_dialog_test.dart
```

Expected: FAIL，`current_release_dialog.dart` 找不到。

### Step 6.3: 實作 `CurrentReleaseDialog`

- [ ] 建立新檔 `lib/widgets/dialogs/current_release_dialog.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/current_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/release_notes_content.dart';

/// 顯示「目前版本」對應 GitHub Release 內容的 dialog。
class CurrentReleaseDialog extends ConsumerWidget {
  /// 建立 [CurrentReleaseDialog]，[version] 為要查詢的版本字串
  /// （pubspec / `PackageInfo` 版本，可帶 build metadata，例如 `1.1.0+2`）。
  const CurrentReleaseDialog({super.key, required this.version});

  /// 要查詢的版本字串。
  final String version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final async = ref.watch(currentReleaseProvider(version));

    return AppDialog(
      size: AppDialogSize.lg,
      scrollable: true,
      title: Row(
        children: [
          Icon(
            Icons.description_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: Text(l.currentReleaseTitle)),
        ],
      ),
      content: async.when(
        loading: () => _LoadingSkeleton(theme: theme),
        data: (release) => ReleaseNotesContent(release: release),
        error: (e, _) => _ErrorBlock(
          error: e,
          version: version,
          l: l,
          theme: theme,
        ),
      ),
      actions: _actionsFor(context, ref, l, async),
    );
  }

  List<Widget> _actionsFor(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    AsyncValue<AppRelease> async,
  ) {
    final closeButton = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(l.actionClose),
    );

    return async.when(
      loading: () => [closeButton],
      data: (release) => [
        closeButton,
        FilledButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: Text(l.currentReleaseOpenOnGithub),
          onPressed: () async {
            await openExternalUrl(Uri.parse(release.htmlUrl));
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
      error: (e, _) {
        // not-found / rate-limited：重試無意義，改提供「開 Releases 頁面」
        final terminalError =
            e is ReleaseCheckNotFound || e is ReleaseCheckRateLimited;
        if (terminalError) {
          return [
            closeButton,
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: Text(l.currentReleaseOpenReleasesPage),
              onPressed: () async {
                await openExternalUrl(
                  Uri.parse('${AppRepo.githubUrl}/releases'),
                );
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ];
        }
        return [
          closeButton,
          FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(l.actionRetry),
            onPressed: () => ref.invalidate(currentReleaseProvider(version)),
          ),
        ];
      },
    );
  }
}

/// 三態 loading 狀態下的灰色占位卡片。不引入 shimmer 套件，視覺極簡。
class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final tokens = theme.gacha;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bar(width: 120, height: 24, color: tokens.borderSubtle),
            const SizedBox(height: AppSpacing.s),
            _bar(width: double.infinity, height: 1, color: tokens.borderSubtle),
            const SizedBox(height: AppSpacing.s),
            _bar(width: double.infinity, height: 14, color: tokens.borderSubtle),
            const SizedBox(height: AppSpacing.xs),
            _bar(width: double.infinity, height: 14, color: tokens.borderSubtle),
            const SizedBox(height: AppSpacing.xs),
            _bar(width: 240, height: 14, color: tokens.borderSubtle),
          ],
        ),
      ),
    );
  }

  Widget _bar({required double width, required double height, required Color color}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// 三態 error 狀態下的訊息區塊。把 [error] 對應到 i18n 字串。
class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({
    required this.error,
    required this.version,
    required this.l,
    required this.theme,
  });

  final Object error;
  final String version;
  final AppLocalizations l;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final message = _messageFor(error);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  /// 把 [ReleaseCheckError] 子類對應到既有 `update*` i18n 字串，
  /// 維持與「檢查更新」流程的訊息一致性。
  String _messageFor(Object e) {
    if (e is ReleaseCheckNotFound) return l.currentReleaseNotFound(version);
    if (e is ReleaseCheckNetwork) return l.updateErrorNetwork;
    if (e is ReleaseCheckTimeout) return l.updateErrorTimeout;
    if (e is ReleaseCheckRateLimited) return l.updateErrorRateLimited;
    if (e is ReleaseCheckServer) return l.updateErrorServer(e.status.toString());
    if (e is ReleaseCheckFormat) return l.updateErrorFormat;
    return e.toString();
  }
}
```

### Step 6.4: 跑測試確認 pass

- [ ] 執行：

```
flutter test test/widgets/dialogs/current_release_dialog_test.dart
```

Expected: All tests passed!（8 個 widget test 全綠）。

若 retry 那個測試的 fetches 計數不到 2，可能是 `ref.invalidate` 觸發後 provider 未自動 read。改寫 retry 按鈕為：

```dart
onPressed: () {
  ref.invalidate(currentReleaseProvider(version));
  ref.read(currentReleaseProvider(version)); // 主動觸發重 fetch
},
```

並重跑測試。

### Step 6.5: 提交前品質檢查

- [ ] 執行：

```
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 全綠。

### Step 6.6: Commit

- [ ] 執行：

```bash
git add lib/widgets/dialogs/current_release_dialog.dart test/widgets/dialogs/current_release_dialog_test.dart
git commit -m "$(cat <<'EOF'
feat(dialogs): add CurrentReleaseDialog with three-state UI

A new dialog that loads the GitHub release for a given version via
currentReleaseProvider and renders one of:
- loading: a minimal grey skeleton card
- data: ReleaseNotesContent (shared with NewVersionDialog)
- error: an inline error block, reusing existing update* i18n strings

Actions adapt to state: data shows [Open on GitHub], not-found and
rate-limited show [Open GitHub Releases page] (retry is pointless),
other errors show [Retry] which invalidates the provider.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: 設定頁加按鈕

**Files:**
- Modify: `lib/pages/settings_page.dart`

### Step 7.1: 在 `_AboutContent` Row 加按鈕

- [ ] 編輯 `lib/pages/settings_page.dart`，定位到 `_AboutContent.build` 內第一個 `Row`（約第 273-293 行）。原本：

```dart
        Row(
          children: [
            Expanded(child: Text(l.settingsAboutVersion(version))),
            const SizedBox(width: AppSpacing.s),
            OutlinedButton.icon(
              onPressed: checking
                  ? null
                  : () => ref
                        .read(appReleaseProvider.notifier)
                        .check(manual: true),
              icon: checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(checking ? l.updateChecking : l.updateCheckButton),
            ),
          ],
        ),
```

改為（在「檢查更新」按鈕**右側**新增「查看更新內容」按鈕）：

```dart
        Row(
          children: [
            Expanded(child: Text(l.settingsAboutVersion(version))),
            const SizedBox(width: AppSpacing.s),
            OutlinedButton.icon(
              onPressed: checking
                  ? null
                  : () => ref
                        .read(appReleaseProvider.notifier)
                        .check(manual: true),
              icon: checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(checking ? l.updateChecking : l.updateCheckButton),
            ),
            const SizedBox(width: AppSpacing.s),
            OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CurrentReleaseDialog(version: version),
              ),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: Text(l.aboutViewReleaseNotes),
            ),
          ],
        ),
```

- [ ] 在 `lib/pages/settings_page.dart` 頂端 imports 加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/current_release_dialog.dart';
```

放在 dialogs/ 既有 import 附近，保持 alphabetical。

### Step 7.2: 提交前品質檢查

- [ ] 執行：

```
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 全綠。

### Step 7.3: 人工視覺驗證

- [ ] 執行：

```
flutter run -d windows
```

開啟設定頁，捲到「關於」section，確認：

1. 版本號右側有兩個按鈕：[檢查更新] [查看更新內容]
2. 兩按鈕視覺一致（OutlinedButton.icon、間距相同）
3. 視窗變窄時 Row 不溢出（按鈕會被 `Expanded` 推到右、必要時 wrap）
4. 點「查看更新內容」→ dialog 開啟、內容載入後顯示當前版本 `v1.1.0` (或 pubspec 對應版本) release notes

Ctrl+C 結束。

### Step 7.4: Commit

- [ ] 執行：

```bash
git add lib/pages/settings_page.dart
git commit -m "$(cat <<'EOF'
feat(settings): add "view release notes" button in About section

Place a new OutlinedButton.icon next to the existing "Check for
updates" button, so users can open CurrentReleaseDialog and review
what changed in the version they're running.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: 最終驗證（人工 smoke test）

**Files:** 無修改

### Step 8.1: 跑全套測試

- [ ] 執行：

```
flutter test
```

Expected: `All tests passed!`，無新 flaky。

### Step 8.2: 跑全套 analyze

- [ ] 執行：

```
flutter analyze
```

Expected: `No issues found!`。

### Step 8.3: 人工 smoke test

- [ ] 啟動 app：

```
flutter run -d windows
```

依序驗證 9 個情境（取自 spec § 測試策略「人工驗證」）：

1. **入口可見性**：設定頁「關於」section 版本號右側出現「查看更新內容」按鈕。
2. **基本開啟**：點按鈕 → dialog 立即開啟，短暫顯示 skeleton（灰色占位）→ 切換成 content。
3. **內容渲染**：標題顯示「目前版本更新內容」、卡片內顯示 `v{version}` 標題、發布日期、Markdown body 正確渲染（連結、列表、粗體都對）。
4. **Open on GitHub**：按「在 GitHub 上開啟」→ 外部瀏覽器跳到 `https://github.com/.../releases/tag/v{version}`、dialog 關閉。
5. **網路錯誤**：把 hosts 暫時擋 `api.github.com`（或關 wifi）→ 重開 app → 點按鈕 → dialog 顯示「無法連線，請檢查網路」+ [重試] [關閉] 按鈕。
6. **重試成功**：解除網路擋阻 → 按 [重試] → 重新 fetch、成功顯示內容。
7. **找不到 release**：暫時把 `pubspec.yaml` `version:` 改成不存在的版本（例如 `9.9.9+1`）→ 重 build → 點按鈕 → dialog 顯示「找不到 9.9.9 對應的更新內容」+ [開啟 GitHub Releases 頁面] [關閉]。完成後**還原** `pubspec.yaml`。
8. **語系切換**：把 app 語系切到日文、英文，重新打開 dialog → 文字依語系正確顯示。
9. **NewVersionDialog 不退步**：手動把本地 version 改成低於最新 release 的版本（例如 `0.1.0+1`），重新啟動 → 既有「新版本通知」dialog 仍應正常彈出、視覺與行為和重構前一致。完成後**還原** `pubspec.yaml`。

- [ ] 如有任何上述情境失敗，記錄並回到對應 Task 修正；全部通過才視為功能完成。

### Step 8.4: 確認 log 行為

- [ ] 在 app 內觸發一次「查看更新內容」（成功）+ 一次（失敗，網路擋）。
- [ ] 從「設定 → 日誌」匯出 logs。
- [ ] 確認 `release.notes` logger 有以下 entries：
  - `fetch start version=<version>`
  - `fetch success tag=v<version>` 或 `fetch failed version=<version>: <error>`
- [ ] 無 unintended sensitive data（公開 repo + 公開 version，本來就沒）。

### Step 8.5: （無 commit）功能完成

本 task 不產生 commit。若先前 task 流程中發現需要修正，請回到對應 task 步驟修正後再過來。

---

## Self-Review Notes

下面是寫完 plan 後對著 spec 做的 self-review，記在這裡供 review 用：

**1. Spec coverage check**

| Spec 章節 / 需求 | 對應 task |
|---|---|
| § 詳細設計 #1 Service 層（`fetchReleaseByVersion` + `ReleaseCheckNotFound`） | Task 1 |
| § 詳細設計 #2 State 層（`currentReleaseProvider`） | Task 2 |
| § 詳細設計 #3 抽出 `ReleaseNotesContent` + 重構 `NewVersionDialog` | Task 3 |
| § 詳細設計 #4 `CurrentReleaseDialog` 三態 + actions | Task 6 |
| § 詳細設計 #5 設定頁按鈕 | Task 7 |
| § 詳細設計 #6 i18n 新增 5 keys × 9 個非空殼 ARB | Task 4 + Task 5 |
| § 詳細設計 #7 Logger `release.notes` | Task 2 內實作 |
| § 測試策略 — service tests | Task 1 |
| § 測試策略 — state tests | Task 2 |
| § 測試策略 — widget tests | Task 6 |
| § 測試策略 — new_version_dialog 重構後仍綠 | Task 3 Step 3.3（analyze + 既有 test） + Task 8 Step 8.3 #9 人工驗證 |
| § 測試策略 — 人工驗證 9 情境 | Task 8 Step 8.3 |

無遺漏。

**2. Placeholder scan**

無 TBD/TODO，所有 step 都有具體 code/command/expected。Task 5 內 8 個語系翻譯都列出完整字串。Task 6 內所有 widget test 都列出完整 code（包含 Completer 修正說明）。

**3. Type consistency**

- `fetchReleaseByVersion({version, client})` — 簽名一致跨 Task 1, 2
- `ReleaseCheckNotFound(this.tag)` — `tag` 屬性一致跨 Task 1, 6
- `currentReleaseProvider` 是 `FutureProvider.family<AppRelease, String>` — 跨 Task 2, 6
- `releaseNotesMarkdownConfig(theme)` 命名跨 Task 3
- `ReleaseNotesContent({required release})` 簽名跨 Task 3, 6
- `CurrentReleaseDialog({required version})` 簽名跨 Task 6, 7
- i18n key 命名跨 Task 4, 5, 6, 7：`currentReleaseTitle` / `currentReleaseNotFound` / `currentReleaseOpenOnGithub` / `currentReleaseOpenReleasesPage` / `aboutViewReleaseNotes`，沿用 `actionClose` / `actionRetry`，全部一致

無不一致。
