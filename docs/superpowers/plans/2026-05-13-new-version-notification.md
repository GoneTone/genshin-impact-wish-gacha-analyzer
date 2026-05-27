# 新版本通知 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 對齊舊版（master, Electron）的版本通知行為，在 Flutter rewrite 移植：啟動時自動 + 設定頁手動檢查 GitHub Releases，列出累積 changelog，使用者可「跳過此版本」或開外部瀏覽器下載。

**Architecture:** 純函式 service 負責 GitHub API 與版本比對；Riverpod Notifier 管 ReleaseCheckState 並讀寫 `AppSettings.skippedReleaseTag`；dialog 顯示在 `AppShell`、Snackbar 在 `SettingsPage`，職責切乾淨。失敗時 `manual=false` 靜默、`manual=true` 才推到 UI。

**Tech Stack:** Flutter (Material 3), Riverpod 3, `http`, `package_info_plus`, `shared_preferences`, `url_launcher`, 新增 `pub_semver`、`markdown_widget`。i18n 使用 `gen_l10n`，template = `app_zh_Hant.arb`。

**Spec reference:** `docs/superpowers/specs/2026-05-13-new-version-notification-design.md`

---

## 全域提醒

**每個 task commit 前都必須跑以下三項（CLAUDE.md 規範）**：

1. `dart format lib/ test/`
2. `flutter analyze` — 必須輸出 `No issues found!`
3. `flutter test` — 必須輸出 `All tests passed!`

任何一項失敗就先修，不要用 `--no-verify` 跳過 hooks。

---

## File Structure

**新增**

- `lib/data/app_repo.dart` — AppRepo class（owner / repo / githubUrl / apiBase 常數）
- `lib/services/app_release_checker.dart` — `AppRelease` model、`ReleaseCheckError` sealed、`fetchNewerReleases` 純函式
- `lib/state/app_release.dart` — `httpClientProvider`、`ReleaseCheckState` sealed、`AppReleaseNotifier`、`appReleaseProvider`
- `lib/widgets/dialogs/new_version_dialog.dart` — `NewVersionDialog`（AlertDialog）
- `test/data/app_repo_test.dart`
- `test/services/app_release_checker_test.dart`
- `test/state/app_release_test.dart`

**修改**

- `pubspec.yaml` — 加 `pub_semver`、`markdown_widget`
- `lib/data/team_info.dart` — 移除 `appGithubUrl` 常數
- `lib/widgets/team_links_bar.dart:41` — `appGithubUrl` → `AppRepo.githubUrl`
- `test/data/team_info_test.dart` — 移除 `group('appGithubUrl', …)`
- `lib/services/settings_storage.dart` — `AppSettings` 加 `skippedReleaseTag`、`copyWith` 對應參數、`load`/`save` 對應 IO
- `lib/state/settings.dart` — `SettingsNotifier.setSkippedReleaseTag`
- `lib/l10n/app_zh_Hant.arb` — 14 個 i18n keys
- `lib/pages/app_shell.dart` — `initState` 觸發 + `ref.listen` dialog
- `lib/pages/settings_page.dart` — `_AboutContent` 加按鈕 + Snackbar listener
- `test/services/settings_storage_test.dart` — `skippedReleaseTag` round-trip 測試
- `test/state/settings_test.dart` — `setSkippedReleaseTag` 測試

---

## Task 1: 新增套件依賴

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 編輯 pubspec.yaml dependencies 區塊**

在現有 `font_awesome_flutter: ^11.0.0` 後面加兩行：

```yaml
  font_awesome_flutter: ^11.0.0
  pub_semver: ^2.2.0
  markdown_widget: ^2.3.2+8
```

- [ ] **Step 2: 安裝套件**

Run: `flutter pub get`
Expected: `Got dependencies!` 結尾無錯誤；`pubspec.lock` 內出現 `pub_semver` 與 `markdown_widget` 項目。

- [ ] **Step 3: 驗證 import 可用**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add pub_semver and markdown_widget for version check"
```

---

## Task 2: 新增 AppRepo 常數（TDD）

**Files:**
- Create: `lib/data/app_repo.dart`
- Test: `test/data/app_repo_test.dart`

- [ ] **Step 1: 寫失敗測試**

Create `test/data/app_repo_test.dart`：

```dart
// test/data/app_repo_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';

void main() {
  group('AppRepo', () {
    test('owner 與 repo 非空', () {
      expect(AppRepo.owner, isNotEmpty);
      expect(AppRepo.repo, isNotEmpty);
    });

    test('githubUrl 由 owner / repo 組成且指向 github.com', () {
      final uri = Uri.parse(AppRepo.githubUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, 'github.com');
      expect(AppRepo.githubUrl, contains('/${AppRepo.owner}/${AppRepo.repo}'));
    });

    test('apiBase 指向 api.github.com 並含 repos path', () {
      final uri = Uri.parse(AppRepo.apiBase);
      expect(uri.scheme, 'https');
      expect(uri.host, 'api.github.com');
      expect(AppRepo.apiBase, contains('/repos/${AppRepo.owner}/${AppRepo.repo}'));
    });
  });
}
```

- [ ] **Step 2: 跑失敗測試確認 fail**

Run: `flutter test test/data/app_repo_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '...app_repo.dart'`

- [ ] **Step 3: 寫實作**

Create `lib/data/app_repo.dart`：

```dart
// lib/data/app_repo.dart
//
// 專案 GitHub repo 座標。集中於此檔，未來 fork 修改成其他遊戲使用時，
// 只需改 owner / repo 兩行常數即可全專案套用。

class AppRepo {
  const AppRepo._();

  static const String owner = 'GoneTone';
  static const String repo = 'genshin-impact-wish-gacha-analyzer';
  static const String githubUrl = 'https://github.com/$owner/$repo';
  static const String apiBase = 'https://api.github.com/repos/$owner/$repo';
}
```

- [ ] **Step 4: 跑測試確認 pass**

Run: `flutter test test/data/app_repo_test.dart`
Expected: PASS — 3 tests

- [ ] **Step 5: 提交前檢查**

```bash
dart format lib/data/app_repo.dart test/data/app_repo_test.dart
flutter analyze
flutter test
```
Expected: 三項全綠。

- [ ] **Step 6: Commit**

```bash
git add lib/data/app_repo.dart test/data/app_repo_test.dart
git commit -m "feat(data): add AppRepo constants for GitHub repo coordinates"
```

---

## Task 3: 把現有 `appGithubUrl` 替換為 `AppRepo.githubUrl`

**Files:**
- Modify: `lib/data/team_info.dart`
- Modify: `lib/widgets/team_links_bar.dart`
- Modify: `test/data/team_info_test.dart`

- [ ] **Step 1: 替換 widget 中的引用**

Edit `lib/widgets/team_links_bar.dart`：

把 import:
```dart
import 'package:genshin_impact_wish_gacha_analyzer/data/team_info.dart';
```
保留（`TeamInfo` 仍要用）。加一行：
```dart
import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';
```

把 line 41 附近的 `url: appGithubUrl,` 改成 `url: AppRepo.githubUrl,`。

- [ ] **Step 2: 移除 team_info.dart 內的 `appGithubUrl`**

Edit `lib/data/team_info.dart`，刪除以下兩段（從第 16 行起）：

```dart
/// 專案 GitHub repo。對齊 master `configs.app.githubUrl`（屬於 app 而非 team）。
const String appGithubUrl =
    'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer';
```

- [ ] **Step 3: 移除 team_info_test 中對應 group**

Edit `test/data/team_info_test.dart`，刪除整個 `group('appGithubUrl', …)`（line 36-42）以及該檔不再需要的部分。最終檔案應只剩 `TeamInfo constants` group。

刪除後檔案應該長這樣（完整覆寫即可避免遺漏）：

```dart
// test/data/team_info_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/team_info.dart';

void main() {
  group('TeamInfo constants', () {
    test('name 非空', () {
      expect(TeamInfo.name, isNotEmpty);
    });

    test('websiteUrl 是 https URL', () {
      final uri = Uri.parse(TeamInfo.websiteUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    });

    test('facebookUrl 是 https URL', () {
      final uri = Uri.parse(TeamInfo.facebookUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    });

    test('discordUrl 是 https URL', () {
      final uri = Uri.parse(TeamInfo.discordUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    });

    test('lineUrl 是 https URL', () {
      final uri = Uri.parse(TeamInfo.lineUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    });
  });
}
```

- [ ] **Step 4: 提交前檢查**

```bash
dart format lib/ test/
flutter analyze
flutter test
```
Expected: 全綠（特別注意 `flutter analyze` 不再有 unused import 或 unresolved reference）。

- [ ] **Step 5: Commit**

```bash
git add lib/data/team_info.dart lib/widgets/team_links_bar.dart test/data/team_info_test.dart
git commit -m "refactor(data): replace appGithubUrl with AppRepo.githubUrl"
```

---

## Task 4: `AppSettings` 擴 `skippedReleaseTag`（TDD）

**Files:**
- Modify: `lib/services/settings_storage.dart`
- Modify: `test/services/settings_storage_test.dart`

- [ ] **Step 1: 寫失敗測試**

Edit `test/services/settings_storage_test.dart`，在 `group('SettingsStorage', () { … });` 內最後一個 test 之後（line 172 `});` 前）加：

```dart
    test('skippedReleaseTag round-trip', () async {
      await SettingsStorage.save(
        const AppSettings(
          themeMode: AppThemeMode.system,
          locale: SystemLanguage(),
          skippedReleaseTag: 'v1.2.0',
        ),
      );
      final s = await SettingsStorage.load();
      expect(s.skippedReleaseTag, 'v1.2.0');
    });

    test('skippedReleaseTag null 表清除（save 後 load 取得 null）', () async {
      SharedPreferences.setMockInitialValues({
        'pref.skippedReleaseTag': 'v1.0.0',
      });
      await SettingsStorage.save(
        const AppSettings(
          themeMode: AppThemeMode.system,
          locale: SystemLanguage(),
          skippedReleaseTag: null,
        ),
      );
      final s = await SettingsStorage.load();
      expect(s.skippedReleaseTag, isNull);
    });

    test('預設 skippedReleaseTag 為 null', () async {
      final s = await SettingsStorage.load();
      expect(s.skippedReleaseTag, isNull);
    });
```

也把現有 `'新欄位預設為 null / 空 map / 空 list'` 那個 test 加上一行 `expect(s.skippedReleaseTag, isNull);`：

```dart
    test('新欄位預設為 null / 空 map / 空 list', () async {
      final s = await SettingsStorage.load();
      expect(s.lastActiveUid, isNull);
      expect(s.uidAliases, isEmpty);
      expect(s.uidOrder, isEmpty);
      expect(s.skippedReleaseTag, isNull);
    });
```

- [ ] **Step 2: 跑失敗測試確認 fail**

Run: `flutter test test/services/settings_storage_test.dart`
Expected: FAIL — `The named parameter 'skippedReleaseTag' isn't defined.`

- [ ] **Step 3: 修改 AppSettings**

Edit `lib/services/settings_storage.dart`，在 `class AppSettings` 內：

把 constructor 改為（line 58-65）：

```dart
  const AppSettings({
    required this.themeMode,
    required this.locale,
    this.lastActiveUid,
    this.uidAliases = const {},
    this.uidOrder = const [],
    this.skippedReleaseTag,
  });
```

在 `final List<String> uidOrder;` 後（line 71）加：

```dart
  final String? skippedReleaseTag;
```

改 `copyWith`（line 78-93）為：

```dart
  AppSettings copyWith({
    AppThemeMode? themeMode,
    LanguagePreference? locale,
    String? lastActiveUid,
    bool clearLastActiveUid = false,
    Map<String, String>? uidAliases,
    List<String>? uidOrder,
    String? skippedReleaseTag,
    bool clearSkippedReleaseTag = false,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
    lastActiveUid: clearLastActiveUid
        ? null
        : (lastActiveUid ?? this.lastActiveUid),
    uidAliases: uidAliases ?? this.uidAliases,
    uidOrder: uidOrder ?? this.uidOrder,
    skippedReleaseTag: clearSkippedReleaseTag
        ? null
        : (skippedReleaseTag ?? this.skippedReleaseTag),
  );
```

- [ ] **Step 4: 修改 SettingsStorage load/save**

在 `class SettingsStorage` 內常數區（line 97-101）加：

```dart
  static const _kSkippedReleaseTag = 'pref.skippedReleaseTag';
```

修改 `load` 函式回傳：

```dart
  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      themeMode: _parseThemeMode(prefs.getString(_kThemeMode)),
      locale: _parseLocale(prefs.getString(_kLocale)),
      lastActiveUid: prefs.getString(_kLastActiveUid),
      uidAliases: _parseAliases(prefs.getString(_kUidAliases)),
      uidOrder: _parseOrder(prefs.getString(_kUidOrder)),
      skippedReleaseTag: prefs.getString(_kSkippedReleaseTag),
    );
  }
```

修改 `save` 函式，在現有 `await prefs.setString(_kUidOrder, …)` 之後加：

```dart
    if (s.skippedReleaseTag == null) {
      await prefs.remove(_kSkippedReleaseTag);
    } else {
      await prefs.setString(_kSkippedReleaseTag, s.skippedReleaseTag!);
    }
```

- [ ] **Step 5: 跑測試確認 pass**

Run: `flutter test test/services/settings_storage_test.dart`
Expected: PASS — 全部通過（既有 + 新增 3 個 + 修改 1 個）。

- [ ] **Step 6: 提交前檢查**

```bash
dart format lib/services/settings_storage.dart test/services/settings_storage_test.dart
flutter analyze
flutter test
```
Expected: 全綠。

- [ ] **Step 7: Commit**

```bash
git add lib/services/settings_storage.dart test/services/settings_storage_test.dart
git commit -m "feat(settings): add skippedReleaseTag to AppSettings"
```

---

## Task 5: `SettingsNotifier.setSkippedReleaseTag`（TDD）

**Files:**
- Modify: `lib/state/settings.dart`
- Modify: `test/state/settings_test.dart`

- [ ] **Step 1: 寫失敗測試**

Edit `test/state/settings_test.dart`，在最後一個 test（`applyImportedPreferences with null lastActiveUid clears it`）之後加：

```dart
  test('setSkippedReleaseTag 寫入 state 與 prefs', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();

    await container
        .read(settingsProvider.notifier)
        .setSkippedReleaseTag('v1.2.0');
    expect(container.read(settingsProvider).skippedReleaseTag, 'v1.2.0');
    final reloaded = await SettingsStorage.load();
    expect(reloaded.skippedReleaseTag, 'v1.2.0');
  });

  test('setSkippedReleaseTag(null) 清掉 state 與 prefs', () async {
    SharedPreferences.setMockInitialValues({
      'pref.skippedReleaseTag': 'v1.2.0',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    expect(container.read(settingsProvider).skippedReleaseTag, 'v1.2.0');

    await container.read(settingsProvider.notifier).setSkippedReleaseTag(null);
    expect(container.read(settingsProvider).skippedReleaseTag, isNull);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.skippedReleaseTag, isNull);
  });
```

- [ ] **Step 2: 跑失敗測試確認 fail**

Run: `flutter test test/state/settings_test.dart`
Expected: FAIL — `The method 'setSkippedReleaseTag' isn't defined for the type 'SettingsNotifier'.`

- [ ] **Step 3: 在 SettingsNotifier 加方法**

Edit `lib/state/settings.dart`，在 `setUidOrder` 之後（line 58）加：

```dart
  Future<void> setSkippedReleaseTag(String? tag) async {
    state = state.copyWith(
      skippedReleaseTag: tag,
      clearSkippedReleaseTag: tag == null,
    );
    await SettingsStorage.save(state);
  }
```

- [ ] **Step 4: 跑測試確認 pass**

Run: `flutter test test/state/settings_test.dart`
Expected: PASS — 全部通過。

- [ ] **Step 5: 提交前檢查**

```bash
dart format lib/state/settings.dart test/state/settings_test.dart
flutter analyze
flutter test
```
Expected: 全綠。

- [ ] **Step 6: Commit**

```bash
git add lib/state/settings.dart test/state/settings_test.dart
git commit -m "feat(settings): add setSkippedReleaseTag notifier method"
```

---

## Task 6: `AppRelease` model 與 service 純函式（TDD）

**Files:**
- Create: `lib/services/app_release_checker.dart`
- Test: `test/services/app_release_checker_test.dart`

### 6.1 model + error 型別 + skeleton

- [ ] **Step 1: 寫失敗測試（最小骨架）**

Create `test/services/app_release_checker_test.dart`：

```dart
// test/services/app_release_checker_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';

http.Response _ok(List<Map<String, dynamic>> body) =>
    http.Response(jsonEncode(body), 200);

Map<String, dynamic> _release({
  required String tag,
  required String published,
  bool prerelease = false,
  bool draft = false,
  String name = '',
  String body = '',
  String htmlUrl = 'https://example.com',
}) => {
  'tag_name': tag,
  'name': name,
  'body': body,
  'prerelease': prerelease,
  'draft': draft,
  'html_url': htmlUrl,
  'published_at': published,
};

void main() {
  group('fetchNewerReleases — happy path', () {
    test('回傳新到舊的、比 currentVersion 新的 release', () async {
      final client = MockClient((req) async => _ok([
            _release(tag: 'v1.2.0', published: '2026-05-13T00:00:00Z'),
            _release(tag: 'v1.1.0', published: '2026-05-10T00:00:00Z'),
            _release(tag: 'v1.0.0', published: '2026-05-01T00:00:00Z'),
          ]));
      final result = await fetchNewerReleases(
        currentVersion: '1.0.0',
        client: client,
      );
      expect(result.map((r) => r.tagName), ['v1.2.0', 'v1.1.0']);
      expect(result[0].version, '1.2.0');
      expect(result[0].publishedAt, DateTime.utc(2026, 5, 13));
    });
  });
}
```

- [ ] **Step 2: 跑失敗測試**

Run: `flutter test test/services/app_release_checker_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '...app_release_checker.dart'`

- [ ] **Step 3: 寫最小實作**

Create `lib/services/app_release_checker.dart`：

```dart
// lib/services/app_release_checker.dart
//
// 純函式：查 GitHub Releases，過濾 prerelease/draft，回傳比 currentVersion
// 新的 release（新到舊）。i18n 留給 notifier 端；service 端不依賴
// AppLocalizations，方便單元測試。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';

class AppRelease {
  const AppRelease({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
  });

  final String tagName;       // 例 "v1.2.0"
  final String version;       // 例 "1.2.0"（剝掉 "v"）
  final String name;
  final String body;          // Markdown
  final String htmlUrl;
  final DateTime publishedAt;
}

sealed class ReleaseCheckError implements Exception {
  const ReleaseCheckError();
}

class ReleaseCheckNetwork extends ReleaseCheckError {
  const ReleaseCheckNetwork();
}

class ReleaseCheckTimeout extends ReleaseCheckError {
  const ReleaseCheckTimeout();
}

class ReleaseCheckRateLimited extends ReleaseCheckError {
  const ReleaseCheckRateLimited();
}

class ReleaseCheckServer extends ReleaseCheckError {
  const ReleaseCheckServer(this.status);
  final int status;
}

class ReleaseCheckFormat extends ReleaseCheckError {
  const ReleaseCheckFormat();
}

/// 內部 helper：剝掉 leading 'v' 後嘗試 Version.parse；無法 parse 則回 null。
Version? _parseTag(String tag) {
  final stripped = tag.startsWith('v') ? tag.substring(1) : tag;
  try {
    return Version.parse(stripped);
  } catch (_) {
    return null;
  }
}

Future<List<AppRelease>> fetchNewerReleases({
  required String currentVersion,
  required http.Client client,
}) async {
  final Version current;
  try {
    current = Version.parse(currentVersion);
  } catch (_) {
    throw const ReleaseCheckFormat();
  }

  final uri = Uri.parse('${AppRepo.apiBase}/releases');
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

  if (resp.statusCode == 403 &&
      resp.headers['x-ratelimit-remaining'] == '0') {
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
  if (decoded is! List) throw const ReleaseCheckFormat();

  final out = <AppRelease>[];
  for (final raw in decoded) {
    if (raw is! Map) continue;
    if (raw['draft'] == true) continue;
    if (raw['prerelease'] == true) continue;
    final tag = raw['tag_name'];
    if (tag is! String) continue;
    final parsed = _parseTag(tag);
    if (parsed == null) continue;
    if (parsed <= current) continue;
    final published = DateTime.tryParse(raw['published_at']?.toString() ?? '');
    if (published == null) continue;
    out.add(
      AppRelease(
        tagName: tag,
        version: parsed.toString(),
        name: (raw['name'] as String?) ?? '',
        body: (raw['body'] as String?) ?? '',
        htmlUrl: (raw['html_url'] as String?) ?? '',
        publishedAt: published,
      ),
    );
  }

  out.sort((a, b) => Version.parse(b.version).compareTo(Version.parse(a.version)));
  return out;
}
```

- [ ] **Step 4: 跑測試確認 happy path pass**

Run: `flutter test test/services/app_release_checker_test.dart`
Expected: PASS — 1 test。

### 6.2 過濾測試（prerelease / draft / tag 格式錯）

- [ ] **Step 5: 加過濾相關失敗測試**

在 `test/services/app_release_checker_test.dart` 內 main() 加：

```dart
  group('fetchNewerReleases — filtering', () {
    test('過濾 prerelease 與 draft', () async {
      final client = MockClient((_) async => _ok([
            _release(tag: 'v1.2.0', published: '2026-05-13T00:00:00Z'),
            _release(
                tag: 'v1.3.0',
                published: '2026-05-14T00:00:00Z',
                prerelease: true),
            _release(
                tag: 'v1.4.0',
                published: '2026-05-15T00:00:00Z',
                draft: true),
          ]));
      final result = await fetchNewerReleases(
        currentVersion: '1.0.0',
        client: client,
      );
      expect(result.map((r) => r.tagName), ['v1.2.0']);
    });

    test('tag 格式錯（"weird-tag"）→ 該筆跳過，其他正常', () async {
      final client = MockClient((_) async => _ok([
            _release(tag: 'v1.2.0', published: '2026-05-13T00:00:00Z'),
            _release(tag: 'weird-tag', published: '2026-05-14T00:00:00Z'),
          ]));
      final result = await fetchNewerReleases(
        currentVersion: '1.0.0',
        client: client,
      );
      expect(result.map((r) => r.tagName), ['v1.2.0']);
    });

    test('current = 最新 → 回空 list', () async {
      final client = MockClient((_) async => _ok([
            _release(tag: 'v1.0.0', published: '2026-05-13T00:00:00Z'),
          ]));
      final result = await fetchNewerReleases(
        currentVersion: '1.0.0',
        client: client,
      );
      expect(result, isEmpty);
    });

    test('tag 無 "v" 前綴也可被 parse', () async {
      final client = MockClient((_) async => _ok([
            _release(tag: '1.2.0', published: '2026-05-13T00:00:00Z'),
          ]));
      final result = await fetchNewerReleases(
        currentVersion: '1.0.0',
        client: client,
      );
      expect(result.map((r) => r.tagName), ['1.2.0']);
      expect(result[0].version, '1.2.0');
    });
  });
```

- [ ] **Step 6: 跑測試確認 pass**

Run: `flutter test test/services/app_release_checker_test.dart`
Expected: PASS — happy path 1 + filtering 4 = 5 tests。

### 6.3 錯誤映射測試

- [ ] **Step 7: 加錯誤測試**

加入 main() 內：

```dart
  group('fetchNewerReleases — errors', () {
    test('200 但 body 非 JSON list → ReleaseCheckFormat', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'oops': 1}), 200),
      );
      expect(
        () => fetchNewerReleases(currentVersion: '1.0.0', client: client),
        throwsA(isA<ReleaseCheckFormat>()),
      );
    });

    test('200 但 body 不是 JSON → ReleaseCheckFormat', () async {
      final client = MockClient((_) async => http.Response('<html/>', 200));
      expect(
        () => fetchNewerReleases(currentVersion: '1.0.0', client: client),
        throwsA(isA<ReleaseCheckFormat>()),
      );
    });

    test('503 → ReleaseCheckServer(503)', () async {
      final client = MockClient((_) async => http.Response('boom', 503));
      try {
        await fetchNewerReleases(currentVersion: '1.0.0', client: client);
        fail('expected throw');
      } on ReleaseCheckServer catch (e) {
        expect(e.status, 503);
      }
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
        () => fetchNewerReleases(currentVersion: '1.0.0', client: client),
        throwsA(isA<ReleaseCheckRateLimited>()),
      );
    });

    test('403 但 ratelimit 還有 → ReleaseCheckServer(403)', () async {
      final client = MockClient(
        (_) async => http.Response(
          'forbidden',
          403,
          headers: const {'x-ratelimit-remaining': '42'},
        ),
      );
      try {
        await fetchNewerReleases(currentVersion: '1.0.0', client: client);
        fail('expected throw');
      } on ReleaseCheckServer catch (e) {
        expect(e.status, 403);
      }
    });

    test('SocketException → ReleaseCheckNetwork', () async {
      final client = MockClient((_) async {
        throw const SocketException('offline');
      });
      expect(
        () => fetchNewerReleases(currentVersion: '1.0.0', client: client),
        throwsA(isA<ReleaseCheckNetwork>()),
      );
    });

    test('http.ClientException → ReleaseCheckNetwork', () async {
      final client = MockClient((_) async {
        throw http.ClientException('connection reset');
      });
      expect(
        () => fetchNewerReleases(currentVersion: '1.0.0', client: client),
        throwsA(isA<ReleaseCheckNetwork>()),
      );
    });

    test('TimeoutException 觸發 → ReleaseCheckTimeout', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 15));
        return http.Response('[]', 200);
      });
      expect(
        () => fetchNewerReleases(currentVersion: '1.0.0', client: client),
        throwsA(isA<ReleaseCheckTimeout>()),
      );
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('currentVersion 無法 parse → ReleaseCheckFormat', () async {
      final client = MockClient((_) async => _ok([]));
      expect(
        () => fetchNewerReleases(
          currentVersion: 'not-a-version',
          client: client,
        ),
        throwsA(isA<ReleaseCheckFormat>()),
      );
    });
  });
```

- [ ] **Step 8: 跑測試確認 pass**

Run: `flutter test test/services/app_release_checker_test.dart`
Expected: PASS — 共 14 tests。

注意：timeout 那個測試會等 10 秒（service 內 timeout 期限），整體 test 約 11-13 秒。若 CI 太慢，可以接受。

- [ ] **Step 9: 提交前檢查**

```bash
dart format lib/services/app_release_checker.dart test/services/app_release_checker_test.dart
flutter analyze
flutter test
```
Expected: 全綠。

- [ ] **Step 10: Commit**

```bash
git add lib/services/app_release_checker.dart test/services/app_release_checker_test.dart
git commit -m "feat(services): add app release checker (GitHub API + version compare)"
```

---

## Task 7: `AppReleaseNotifier` 與 Riverpod state（TDD）

**Files:**
- Create: `lib/state/app_release.dart`
- Test: `test/state/app_release_test.dart`

### 7.1 State 型別 + provider 骨架 + happy path

- [ ] **Step 1: 寫失敗測試**

Create `test/state/app_release_test.dart`：

```dart
// test/state/app_release_test.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

http.Response _ok(List<Map<String, dynamic>> body) =>
    http.Response(jsonEncode(body), 200);

Map<String, dynamic> _release(String tag, String published) => {
  'tag_name': tag,
  'name': '',
  'body': '',
  'prerelease': false,
  'draft': false,
  'html_url': 'https://example.com/$tag',
  'published_at': published,
};

ProviderContainer _container({
  required String currentVersion,
  required http.Client client,
  Map<String, Object> prefs = const {},
}) {
  SharedPreferences.setMockInitialValues(Map<String, Object>.from(prefs));
  final container = ProviderContainer(
    overrides: [
      appVersionProvider.overrideWithValue(currentVersion),
      httpClientProvider.overrideWithValue(client),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('初始 state = ReleaseIdle', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient((_) async => _ok([])),
    );
    expect(container.read(appReleaseProvider), isA<ReleaseIdle>());
  });

  test('check(manual: true) 有新版 → ReleaseAvailable', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient(
        (_) async => _ok([_release('v1.2.0', '2026-05-13T00:00:00Z')]),
      ),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: true);

    final state = container.read(appReleaseProvider);
    expect(state, isA<ReleaseAvailable>());
    expect((state as ReleaseAvailable).releases.first.tagName, 'v1.2.0');
  });
}
```

- [ ] **Step 2: 跑失敗測試**

Run: `flutter test test/state/app_release_test.dart`
Expected: FAIL — 找不到 `app_release.dart`。

- [ ] **Step 3: 寫最小實作**

Create `lib/state/app_release.dart`：

```dart
// lib/state/app_release.dart
//
// 版本檢查狀態管理。啟動自動 + 設定頁手動兩個入口共用同一個 notifier。
// 失敗時 `manual=false` 靜默（僅 debugPrint），`manual=true` 才把錯誤
// 推給 UI。i18n localize 在這層完成；service 端保持純函式。

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

export 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart'
    show AppRelease;

sealed class ReleaseCheckState {
  const ReleaseCheckState();
}

class ReleaseIdle extends ReleaseCheckState {
  const ReleaseIdle();
}

class ReleaseChecking extends ReleaseCheckState {
  const ReleaseChecking();
}

class ReleaseUpToDate extends ReleaseCheckState {
  const ReleaseUpToDate();
}

class ReleaseAvailable extends ReleaseCheckState {
  const ReleaseAvailable(this.releases);
  final List<AppRelease> releases;
}

class ReleaseCheckFailed extends ReleaseCheckState {
  const ReleaseCheckFailed(this.reason);
  final String reason;
}

/// 預設 `http.Client()`；測試 override 用 `MockClient`。
final httpClientProvider = Provider<http.Client>((_) => http.Client());

class AppReleaseNotifier extends Notifier<ReleaseCheckState> {
  @override
  ReleaseCheckState build() => const ReleaseIdle();

  Future<void> check({required bool manual}) async {
    state = const ReleaseChecking();
    final currentVersion = ref.read(appVersionProvider);
    final client = ref.read(httpClientProvider);

    final List<AppRelease> releases;
    try {
      releases = await fetchNewerReleases(
        currentVersion: currentVersion,
        client: client,
      );
    } on ReleaseCheckError catch (e) {
      if (manual) {
        state = ReleaseCheckFailed(_localizeError(e));
      } else {
        debugPrint('[app_release] silent failure: $e');
        state = const ReleaseIdle();
      }
      return;
    }

    if (releases.isEmpty) {
      state = const ReleaseUpToDate();
      return;
    }

    if (!manual) {
      final skipped = ref.read(settingsProvider).skippedReleaseTag;
      if (skipped != null && releases.first.tagName == skipped) {
        state = const ReleaseIdle();
        return;
      }
    }

    state = ReleaseAvailable(releases);
  }

  Future<void> skipVersion(String tagName) async {
    await ref.read(settingsProvider.notifier).setSkippedReleaseTag(tagName);
  }

  /// 把 service error 轉成 user-readable 字串。i18n key 由呼叫端 (UI) 解；
  /// 此處先給穩定 token，UI 拿 token 做翻譯。
  /// 為了讓 ReleaseCheckFailed.reason 是已 localize 文字，UI 層在 listener
  /// 內呼叫 AppLocalizations 重新處理會更乾淨；但本 notifier 直接吐簡短的
  /// 英文 fallback 也可用——這裡採取吐 token (e.g. "network", "timeout")，
  /// UI 端 switch token 轉 l10n。
  String _localizeError(ReleaseCheckError e) => switch (e) {
    ReleaseCheckNetwork() => 'network',
    ReleaseCheckTimeout() => 'timeout',
    ReleaseCheckRateLimited() => 'rateLimited',
    ReleaseCheckServer(:final status) => 'server:$status',
    ReleaseCheckFormat() => 'format',
  };
}

final appReleaseProvider =
    NotifierProvider<AppReleaseNotifier, ReleaseCheckState>(
      AppReleaseNotifier.new,
    );
```

注意設計：`_localizeError` 吐穩定 token（`"network"` / `"server:503"`）而非 i18n 字串，UI listener 端拿 token 解析後呼叫 `AppLocalizations`。理由：notifier 拿不到 `BuildContext`，且 token 比直接 dump enum 名穩定（switch 在一處）。

- [ ] **Step 4: 跑測試確認 pass**

Run: `flutter test test/state/app_release_test.dart`
Expected: PASS — 2 tests。

### 7.2 補完所有 state 轉換測試

- [ ] **Step 5: 加完整 state 轉換測試**

在 `test/state/app_release_test.dart` main() 內後續加：

```dart
  test('check(manual: false) 有新版 → ReleaseAvailable', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient(
        (_) async => _ok([_release('v1.2.0', '2026-05-13T00:00:00Z')]),
      ),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: false);

    expect(container.read(appReleaseProvider), isA<ReleaseAvailable>());
  });

  test(
    'check(manual: false) 且最新 tag == skippedReleaseTag → 維持 ReleaseIdle',
    () async {
      final container = _container(
        currentVersion: '1.0.0',
        client: MockClient(
          (_) async => _ok([_release('v1.2.0', '2026-05-13T00:00:00Z')]),
        ),
        prefs: const {'pref.skippedReleaseTag': 'v1.2.0'},
      );
      await container.read(settingsProvider.notifier).waitForLoad();

      await container.read(appReleaseProvider.notifier).check(manual: false);

      expect(container.read(appReleaseProvider), isA<ReleaseIdle>());
    },
  );

  test('check(manual: true) 無視 skippedReleaseTag → ReleaseAvailable', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient(
        (_) async => _ok([_release('v1.2.0', '2026-05-13T00:00:00Z')]),
      ),
      prefs: const {'pref.skippedReleaseTag': 'v1.2.0'},
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: true);

    expect(container.read(appReleaseProvider), isA<ReleaseAvailable>());
  });

  test('check — 空 list → ReleaseUpToDate', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient((_) async => _ok([])),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: true);

    expect(container.read(appReleaseProvider), isA<ReleaseUpToDate>());
  });

  test('check(manual: true) error → ReleaseCheckFailed (含 token)', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient((_) async => http.Response('boom', 503)),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: true);

    final state = container.read(appReleaseProvider);
    expect(state, isA<ReleaseCheckFailed>());
    expect((state as ReleaseCheckFailed).reason, 'server:503');
  });

  test('check(manual: false) error → 維持 ReleaseIdle，靜默', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient((_) async => http.Response('boom', 503)),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: false);

    expect(container.read(appReleaseProvider), isA<ReleaseIdle>());
  });

  test('skipVersion 寫入 settings.skippedReleaseTag', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient((_) async => _ok([])),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).skipVersion('v1.5.0');

    expect(
      container.read(settingsProvider).skippedReleaseTag,
      'v1.5.0',
    );
  });

  test('error token: network', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient((_) async {
        throw http.ClientException('offline');
      }),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: true);
    final state = container.read(appReleaseProvider);
    expect((state as ReleaseCheckFailed).reason, 'network');
  });

  test('error token: rateLimited', () async {
    final container = _container(
      currentVersion: '1.0.0',
      client: MockClient(
        (_) async => http.Response(
          'forbidden',
          403,
          headers: const {'x-ratelimit-remaining': '0'},
        ),
      ),
    );
    await container.read(settingsProvider.notifier).waitForLoad();

    await container.read(appReleaseProvider.notifier).check(manual: true);
    final state = container.read(appReleaseProvider);
    expect((state as ReleaseCheckFailed).reason, 'rateLimited');
  });
```

- [ ] **Step 6: 跑測試確認 pass**

Run: `flutter test test/state/app_release_test.dart`
Expected: PASS — 11 tests。

- [ ] **Step 7: 提交前檢查**

```bash
dart format lib/state/app_release.dart test/state/app_release_test.dart
flutter analyze
flutter test
```
Expected: 全綠。

- [ ] **Step 8: Commit**

```bash
git add lib/state/app_release.dart test/state/app_release_test.dart
git commit -m "feat(state): add AppReleaseNotifier and ReleaseCheckState"
```

---

## Task 8: i18n keys（template `app_zh_Hant.arb`）

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`

- [ ] **Step 1: 加新 i18n keys**

Edit `lib/l10n/app_zh_Hant.arb`，在最後一個 entry (`bannerFiveStarPullsSinceLast` 的 `@…` 區塊) 結尾把 `}` 的前一個 entry 加上 comma，並插入新 keys。完成後檔案結尾應該長這樣：

```json
  "bannerFiveStarCountTitle": "各卡池 5★ 件數",
  "bannerFiveStarPullsSinceLast": "距上次 5★ {n} 抽",
  "@bannerFiveStarPullsSinceLast": {
    "placeholders": { "n": { "type": "int" } }
  },

  "updateTitle": "有新版本 {version} 可用",
  "@updateTitle": {
    "placeholders": { "version": { "type": "String" } }
  },
  "updateReleasedAt": "發布於 {date}",
  "@updateReleasedAt": {
    "placeholders": { "date": { "type": "String" } }
  },
  "updateButtonDownload": "前往下載",
  "updateButtonSkip": "跳過此版本",
  "updateButtonLater": "稍後再說",
  "updateCheckButton": "檢查更新",
  "updateChecking": "檢查中…",
  "updateAlreadyLatest": "已是最新版本",
  "updateCheckFailed": "檢查更新失敗：{reason}",
  "@updateCheckFailed": {
    "placeholders": { "reason": { "type": "String" } }
  },
  "updateErrorNetwork": "無法連線，請檢查網路",
  "updateErrorTimeout": "請求逾時",
  "updateErrorRateLimited": "GitHub API 配額用盡，請稍後再試",
  "updateErrorServer": "伺服器錯誤 (HTTP {status})",
  "@updateErrorServer": {
    "placeholders": { "status": { "type": "String" } }
  },
  "updateErrorFormat": "回應格式異常"
}
```

注意：JSON 規格不允許 trailing comma，最末 entry 不加 comma；其他 entry 都要加 comma。

- [ ] **Step 2: 觸發 codegen**

Run: `flutter gen-l10n`
Expected: 無錯誤，`lib/l10n/generated/app_localizations.dart` 等檔案被更新。

驗證 generated 檔內出現 `updateTitle` 方法：
Run: `grep updateTitle lib/l10n/generated/app_localizations.dart | head -3`
Expected: 至少看到 `String updateTitle(String version);`。

- [ ] **Step 3: 提交前檢查**

```bash
flutter analyze
flutter test
```
Expected: 全綠（generated 檔不需 format，但 analyze 必須過）。

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/
git commit -m "i18n(zh_Hant): add keys for new version notification"
```

說明：`flutter gen-l10n` 會 regenerate `lib/l10n/generated/` 下所有語言檔，整個 `lib/l10n/` 一起 add 比較不會漏。

---

## Task 9: `NewVersionDialog`

**Files:**
- Create: `lib/widgets/dialogs/new_version_dialog.dart`

- [ ] **Step 1: 寫 dialog 實作**

Create `lib/widgets/dialogs/new_version_dialog.dart`：

```dart
// lib/widgets/dialogs/new_version_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class NewVersionDialog extends ConsumerWidget {
  const NewVersionDialog({super.key, required this.releases});
  final List<AppRelease> releases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final latest = releases.first;
    final maxHeight = MediaQuery.of(context).size.height * 0.6;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: tokens.stateSuccess),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: Text(l.updateTitle(latest.tagName))),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in releases) ...[
                  _ReleaseCard(release: r, l: l),
                  const SizedBox(height: AppSpacing.m),
                ],
              ],
            ),
          ),
        ),
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
            await launchUrl(
              Uri.parse(latest.htmlUrl),
              mode: LaunchMode.externalApplication,
            );
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release, required this.l});
  final AppRelease release;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final dateText = DateFormat('yyyy-MM-dd').format(release.publishedAt.toLocal());

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  release.tagName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Text(
                  l.updateReleasedAt(dateText),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            if (release.body.isNotEmpty) MarkdownBlock(data: release.body),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 檢查 analyze**

Run: `flutter analyze`
Expected: `No issues found!`（特別要確認 `MarkdownBlock` 與 `gacha` extension 都解析得到）

- [ ] **Step 3: 提交前檢查**

```bash
dart format lib/widgets/dialogs/new_version_dialog.dart
flutter analyze
flutter test
```
Expected: 全綠。

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/dialogs/new_version_dialog.dart
git commit -m "feat(widgets): add NewVersionDialog with markdown changelog"
```

---

## Task 10: `AppShell` 啟動觸發 + dialog listener

**Files:**
- Modify: `lib/pages/app_shell.dart`

- [ ] **Step 1: 加 imports**

Edit `lib/pages/app_shell.dart`，在現有 imports 區塊（line 1-14）後加：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/new_version_dialog.dart';
```

- [ ] **Step 2: 改 `_AppShellState` 加 initState + 新 flag**

Edit `_AppShellState`：

把 line 25 `bool _dialogOpen = false;` 後面加：

```dart
  bool _releaseDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appReleaseProvider.notifier).check(manual: false);
    });
  }
```

- [ ] **Step 3: 加 dialog listener 到 build 開頭**

Edit `_AppShellState.build`，在現有 `ref.listen<UpdateProgress?>(…)`（line 29-43）之後、`final l = AppLocalizations.of(context)!;`（line 45）之前加：

```dart
    ref.listen<ReleaseCheckState>(appReleaseProvider, (prev, next) {
      if (next is ReleaseAvailable && !_releaseDialogOpen) {
        _releaseDialogOpen = true;
        showDialog(
          context: context,
          builder: (_) => NewVersionDialog(releases: next.releases),
        ).whenComplete(() {
          _releaseDialogOpen = false;
        });
      }
    });
```

- [ ] **Step 4: 檢查 analyze + run**

```bash
dart format lib/pages/app_shell.dart
flutter analyze
flutter test
```
Expected: 全綠。

- [ ] **Step 5: 人工驗證（dev run）**

> 這步是 UI 整合驗證，目前 settings_page 還沒接，所以只能驗證「啟動時若有新版會跳 dialog」。可選擇暫時把 pubspec.yaml 的 version 改成 `0.0.1+1` 來強制讓所有 GitHub release 都比 current 新（驗證後改回）。

Run: `flutter run -d windows`
- App 啟動後 ~1 秒應該跳出 `NewVersionDialog`
- 看到 release notes（markdown 渲染）、三顆按鈕
- 點「前往下載」開外部瀏覽器到 `https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases/tag/...`
- 點 X 關閉視窗

驗證完記得把 pubspec.yaml 改回原版本。

- [ ] **Step 6: Commit**

```bash
git add lib/pages/app_shell.dart
git commit -m "feat(app-shell): wire startup version check and dialog"
```

---

## Task 11: 設定頁「檢查更新」按鈕 + Snackbar listener

**Files:**
- Modify: `lib/pages/settings_page.dart`

- [ ] **Step 1: 加 imports**

Edit `lib/pages/settings_page.dart`，在 imports 區塊加：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
```

- [ ] **Step 2: 改造 `_AboutContent`**

Edit `_AboutContent`（line 176-227）。整段替換為：

```dart
class _AboutContent extends ConsumerWidget {
  const _AboutContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider);

    ref.listen<ReleaseCheckState>(appReleaseProvider, (prev, next) {
      if (next is ReleaseUpToDate) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.updateAlreadyLatest)),
        );
      } else if (next is ReleaseCheckFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.updateCheckFailed(_resolveReason(l, next.reason))),
          ),
        );
      }
    });

    final releaseState = ref.watch(appReleaseProvider);
    final checking = releaseState is ReleaseChecking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.code, size: 16, color: theme.gacha.textSecondary),
            const SizedBox(width: AppSpacing.xs),
            const Text('Developed by '),
            const AppLink(
              url: 'https://github.com/GoneTone',
              child: Text('GoneTone'),
            ),
            const Text(' ('),
            const AppLink(url: TeamInfo.websiteUrl, child: Text(TeamInfo.name)),
            const Text(')'),
          ],
        ),
        const SizedBox(height: AppSpacing.l),
        Wrap(
          spacing: AppSpacing.l,
          runSpacing: AppSpacing.l,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: const [
            BannerLink(
              assetPath: 'assets/banners/gonetone_banner.png',
              url: 'https://blog.reh.tw/',
              semanticLabel: '旋風之音 GoneTone',
              height: 64,
            ),
            BannerLink(
              assetPath: 'assets/banners/genshin_info_banner.png',
              url: TeamInfo.websiteUrl,
              semanticLabel: TeamInfo.name,
              height: 64,
            ),
          ],
        ),
      ],
    );
  }

  /// 把 notifier 給的 token 轉成 i18n 字串。
  /// Token 格式：
  ///   - "network" / "timeout" / "rateLimited" / "format"
  ///   - "server:<status>"（status 為 HTTP code）
  String _resolveReason(AppLocalizations l, String token) {
    if (token == 'network') return l.updateErrorNetwork;
    if (token == 'timeout') return l.updateErrorTimeout;
    if (token == 'rateLimited') return l.updateErrorRateLimited;
    if (token == 'format') return l.updateErrorFormat;
    if (token.startsWith('server:')) {
      final status = token.substring('server:'.length);
      return l.updateErrorServer(status);
    }
    return token;
  }
}
```

- [ ] **Step 3: 檢查 analyze + test**

```bash
dart format lib/pages/settings_page.dart
flutter analyze
flutter test
```
Expected: 全綠。

- [ ] **Step 4: 人工驗證（dev run）**

Run: `flutter run -d windows`

驗證點：
1. 進入設定頁「關於」區塊 → 看到「v1.0.0」與「檢查更新」按鈕並排
2. 點「檢查更新」→
   - 按鈕變 spinner + 文字「檢查中…」
   - 約 1-2 秒後：
     - 若無新版 → Snackbar「已是最新版本」
     - 若有新版 → AppShell 跳 `NewVersionDialog`（與啟動相同流程）
3. 拔網路再點「檢查更新」→ Snackbar「檢查更新失敗：無法連線，請檢查網路」
4. 啟動時看到 dialog 後點「跳過此版本」→ 完全關閉 app 再開 → 不再跳 dialog；再從設定頁點「檢查更新」→ 仍會跳 dialog（手動忽視 skip）

- [ ] **Step 5: Commit**

```bash
git add lib/pages/settings_page.dart
git commit -m "feat(settings): add check-for-updates button in About section"
```

---

## Task 12: 全面整合驗證

**Files:** 無新增，僅驗證

- [ ] **Step 1: 整體格式 / analyze / test**

```bash
dart format lib/ test/
flutter analyze
flutter test
```
Expected: 三項全綠，且測試總數應比起初多出（至少）：
- `test/data/app_repo_test.dart`: +3
- `test/services/settings_storage_test.dart`: +3 既有改 1
- `test/state/settings_test.dart`: +2
- `test/services/app_release_checker_test.dart`: +14
- `test/state/app_release_test.dart`: +11
- 合計：33+

- [ ] **Step 2: 人工最終跑一遍**

Run: `flutter run -d windows --release`（release mode 確認效能）

驗證 checklist：
- [ ] App 啟動時，若 GitHub 上有新版 → 跳 `NewVersionDialog`；無新版 → 完全靜默不打擾
- [ ] 拔網路啟動 → app 正常啟動，不跳錯誤 dialog
- [ ] Dialog 中 markdown 列表/連結/標題可見且正確
- [ ] Dialog「跳過此版本」→ 重啟不再跳；推 release 升一版 → 又會跳
- [ ] Dialog「稍後再說」→ 下次啟動仍跳
- [ ] Dialog「前往下載」→ 開預設瀏覽器到正確 release 頁
- [ ] 設定頁「檢查更新」按鈕：
  - 已是最新 → Snackbar「已是最新版本」
  - 有新版 → 跳 dialog
  - 網路斷 → Snackbar「無法連線，請檢查網路」
- [ ] AppBar 與「祈願記錄更新」dialog 仍正常運作（未被新功能影響）

- [ ] **Step 3: 最終 commit（如有 housekeeping）**

如有 lint 或微調，補一個 commit；否則跳過。

---

## YAGNI / 不做的事

依 spec 邊界，本 plan 不包含：

- 自動下載 / 安裝 chain
- 「不再提醒任何版本」總開關
- 版本檢查結果快取
- 9 個非主要語言的 ARB 翻譯（留給 Crowdin）
- changelog 摺疊 UI（直接 scroll）
- UI 的 widget 自動化測試（與既有 `UpdateProgressDialog` 一致；以人工驗證代替）
