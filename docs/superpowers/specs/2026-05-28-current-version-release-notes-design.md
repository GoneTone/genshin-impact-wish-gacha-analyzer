# 目前版本更新內容（Current Version Release Notes）設計

在「設定頁 → 關於」區塊新增入口，讓使用者隨時主動查看「**目前安裝這個版本**」對應的 GitHub release notes，補上既有「新版本通知」（只在偵測到更新時跳）所沒有的回顧能力。

## 背景

現況（見 [2026-05-13 新版本通知設計](2026-05-13-new-version-notification-design.md)）：

- `AppReleaseChecker.fetchNewerReleases()` 只回傳比目前版本「**更新**」的 releases，沒有抓「目前版本本身」的能力
- `NewVersionDialog` 用 `markdown_widget` 渲染 release notes，但只能由「啟動自動檢查偵測到新版」或「設定頁手動檢查回報有新版」觸發
- 使用者升級到最新版後，無法在 app 內回頭看「我這版到底做了什麼」，只能自己去 GitHub
- 設定頁「關於」區塊已有版本號 + 「檢查更新」按鈕，是天然的延伸點

新功能補上這個缺口：版本號旁加一個按鈕，點下開 dialog 顯示「目前版本」對應的 release notes。

## 需求決定

| 項目 | 決定 |
|---|---|
| 入口位置 | 設定頁「關於」section，版本號右側加 `OutlinedButton.icon`「查看更新內容」，與既有「檢查更新」按鈕並列 |
| Dialog 樣式 | 沿用 `AppDialog` `size: lg, scrollable: true`，與 `NewVersionDialog` 視覺一致 |
| 顯示範圍 | 只顯示「目前版本」對應的單一 release（YAGNI；不做歷史 N 版） |
| 元件重用 | 抽出 `ReleaseNotesContent` 共用 widget，`NewVersionDialog` 與新建的 `CurrentReleaseDialog` 都用它；不另造輪子 |
| API endpoint | `GET /repos/{owner}/{repo}/releases/tags/{tag}`（單筆抓，比 list filter 省 quota） |
| 「找不到」處理 | dialog 內顯示「找不到 {version} 對應的 release」訊息 + [在 GitHub Releases 開啟] [關閉] |
| 錯誤處理 | 沿用 `ReleaseCheckError` 家族；新增 `ReleaseCheckNotFound` 子類對應 404；UI 顯示既有 `update*` 錯誤字串 |
| 快取 | in-memory（Riverpod `FutureProvider.family` 自帶），同 app 生命週期內不重打；按「重試」呼叫 `ref.invalidate` 清快取重 fetch |
| Loading 行為 | dialog 立即開啟，內部三態：loading skeleton / error / content |
| i18n 範圍 | 新增字串加在 **所有非空殼 ARB**（9 個：`zh, zh_Hans, en, es, fr, ja, pt_BR, th, vi`），空殼 22 個不動 |
| Logger 命名 | `release.notes` |

## 架構總覽

```
[新增]
lib/state/current_release.dart                          新 Riverpod FutureProvider.family
lib/widgets/dialogs/release_notes_content.dart          抽出的共用 content widget + _markdownConfig
lib/widgets/dialogs/current_release_dialog.dart         新 dialog 殼，三態 + actions

[修改]
lib/services/app_release_checker.dart                   + fetchReleaseByVersion()
                                                        + ReleaseCheckNotFound 子類
lib/widgets/dialogs/new_version_dialog.dart             _ReleaseCard / _markdownConfig 抽出到 release_notes_content
lib/pages/settings_page.dart                            _AboutContent 加按鈕
lib/l10n/app_{zh,zh_Hans,en,es,fr,ja,pt_BR,th,vi}.arb   新增 i18n keys
```

職責切分：

- `CurrentReleaseDialog` 只負責「殼」（標題、actions、三態切換）
- `ReleaseNotesContent` 只負責「單筆 release 視覺呈現」（共用）
- `currentReleaseProvider` 只負責「以 version key 抓單筆 release + cache」
- `fetchReleaseByVersion` 只負責「API 呼叫 + parsing + 錯誤分類」（純函式）

## 詳細設計

### 1. Service 層擴充

`lib/services/app_release_checker.dart`：

```dart
/// 找不到指定 tag 對應的 release（HTTP 404）。
class ReleaseCheckNotFound extends ReleaseCheckError {
  /// 建立 [ReleaseCheckNotFound]，[tag] 為查詢的 tag（含 v 前綴）。
  const ReleaseCheckNotFound(this.tag);

  /// 查詢的 tag，例如 `v1.1.0`。
  final String tag;
}

/// 抓指定 [version] 對應的 GitHub Release。
///
/// [version] 可帶 SemVer build metadata（例如 `1.1.0+2`），內部會剝掉
/// build metadata 並補上 `v` 前綴，組成 tag `v1.1.0` 後查詢。
///
/// 失敗時拋 [ReleaseCheckError] 的具體子類；找不到 release 時拋
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
  final core = '${parsed.major}.${parsed.minor}.${parsed.patch}'; // 剝 build metadata
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

注意：

- `_parseTag` 是檔內既有 private helper，重用
- 不過濾 `draft` / `prerelease`：使用者明確查指定 tag，若該 tag 是 pre-release 也照顯（這場景下使用者「裝了那個版本」就代表他想看那個版本的 notes）

### 2. State 層

`lib/state/current_release.dart`（新檔）：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart'
    show httpClientProvider;

/// 依 version key 抓對應的 GitHub Release，自帶 in-memory cache。
/// 重試呼叫 `ref.invalidate(currentReleaseProvider(version))`。
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
      Logger('release.notes').warning('fetch failed: $e');
      rethrow;
    }
  },
);
```

`httpClientProvider` 從 `state/app_release.dart` 重用，不另建。

### 3. UI — 抽出共用 content widget

`lib/widgets/dialogs/release_notes_content.dart`（新檔）：

從 `new_version_dialog.dart` 把 `_ReleaseCard` 改寫升格為 public widget，並把 `_markdownConfig` 一併搬過來：

```dart
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

`new_version_dialog.dart` 同步調整：

- 刪除檔內 `_ReleaseCard` 與 `_markdownConfig`
- 在 `for` 迴圈內改用 `ReleaseNotesContent(release: releases[i])`
- 視覺與行為完全不變（既有測試應全綠）

### 4. UI — Dialog 殼

`lib/widgets/dialogs/current_release_dialog.dart`（新檔）：

```dart
/// 顯示「目前版本」對應 GitHub Release 內容的 dialog。
class CurrentReleaseDialog extends ConsumerWidget {
  /// 建立 [CurrentReleaseDialog]，需傳入要查的 [version]
  /// （pubspec 版本，例如 `1.1.0+2`）。
  const CurrentReleaseDialog({super.key, required this.version});

  /// 要查詢的版本字串。
  final String version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final async = ref.watch(currentReleaseProvider(version));

    return AppDialog(
      size: AppDialogSize.lg,
      scrollable: true,
      title: Row(
        children: [
          Icon(Icons.description_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: Text(l.currentReleaseTitle)),
        ],
      ),
      content: async.when(
        loading: () => _LoadingSkeleton(tokens: tokens),
        data: (release) => ReleaseNotesContent(release: release),
        error: (e, _) => _ErrorBlock(error: e, version: version, l: l, tokens: tokens),
      ),
      actions: _actionsFor(context, ref, l, async, version),
    );
  }

  List<Widget> _actionsFor(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    AsyncValue<AppRelease> async,
    String version,
  ) {
    // 三態 actions：
    // loading      → [關閉]
    // data         → [在 GitHub 上開啟] [關閉]
    // rate limited → [在 GitHub Releases 開啟] [關閉]（重試無意義）
    // not found    → [在 GitHub Releases 開啟] [關閉]（重試也找不到）
    // 其他 error    → [重試] [關閉]
    // 實作見下方完整版
  }
}
```

三態 UI 細節：

- **Loading skeleton**：尺寸近似 `ReleaseNotesContent` 的卡片，內含灰色 `Container`（標題列高度 + 數行 body 寬高），用 `tokens.borderSubtle` 色塊；不引入額外 shimmer 套件（YAGNI）
- **Data**：直接 `ReleaseNotesContent(release: release)`
- **Error**：
  - 取 i18n message 對應 `ReleaseCheckError` 子類：
    - `ReleaseCheckNotFound` → `l.currentReleaseNotFound(version)`
    - 其餘沿用既有 `l.updateErrorXxx`
  - 視覺：`Icon(Icons.error_outline)` + 訊息文字
- **Actions 對應**：

| 狀態                       | Actions                                            |
|--------------------------|----------------------------------------------------|
| loading                  | `[Close]`                                          |
| data                     | `[OpenOnGitHub (release.htmlUrl)] [Close]`         |
| ReleaseCheckNotFound     | `[OpenReleasesPage (.../releases)] [Close]`        |
| ReleaseCheckRateLimited  | `[OpenReleasesPage (.../releases)] [Close]`        |
| 其他 ReleaseCheckError    | `[Retry (ref.invalidate)] [Close]`                 |

「在 GitHub 上開啟」用既有 `openExternalUrl(Uri.parse(...))`。

### 5. UI — 設定頁按鈕

`lib/pages/settings_page.dart` `_AboutContent`（第 243-349 行範圍）：

版本號右側 `Row` 內加一顆按鈕，與既有「檢查更新」按鈕並列：

```dart
OutlinedButton.icon(
  onPressed: () => showDialog(
    context: context,
    builder: (_) => CurrentReleaseDialog(version: version),
  ),
  icon: const Icon(Icons.description_outlined, size: 18),
  label: Text(l.aboutViewReleaseNotes),
),
```

按鈕擺在「檢查更新」按鈕**右側**，順序：[檢查更新] [查看更新內容]。

Hover/cursor 處理：`OutlinedButton` 自帶；不需顯式 `mouseCursor`（記憶 `feedback_inkwell_explicit_mouse_cursor.md` 只針對 `InkWell`）。

### 6. i18n 字串

新增 5 個 keys（template 為 `app_zh.arb`，按專案慣例「繁中起手」）。`actionClose`（關閉）、`actionRetry`（重試）、`actionCancel`（取消）等共用按鈕字串 ARB 已有，直接重用，不新增：

| key | 繁中 (zh) | 英文 (en) | 說明 |
|---|---|---|---|
| `aboutViewReleaseNotes` | 查看更新內容 | View release notes | 設定頁按鈕文字 |
| `currentReleaseTitle` | 目前版本更新內容 | Current release notes | Dialog 標題 |
| `currentReleaseNotFound` | 找不到 {version} 對應的更新內容 | Release notes not found for {version} | 404 訊息（含 `version` placeholder） |
| `currentReleaseOpenOnGithub` | 在 GitHub 上開啟 | Open on GitHub | data 狀態的主按鈕 |
| `currentReleaseOpenReleasesPage` | 開啟 GitHub Releases 頁面 | Open GitHub Releases page | error/not-found 狀態的主按鈕 |

**翻譯範圍**：依使用者明確指示與 [`feedback_i18n_skip_empty_arbs.md`](記憶)，新增字串加在 **9 個非空殼 ARB**：

```
app_zh.arb       (source, 繁中)
app_zh_Hans.arb  (簡中)
app_en.arb       (英文)
app_es.arb       (西班牙文)
app_fr.arb       (法文)
app_ja.arb       (日文)
app_pt_BR.arb    (巴西葡文)
app_th.arb       (泰文)
app_vi.arb       (越南文)
```

22 個空殼 ARB（`af, ar, ca, cs, da, de, el, fi, he, hu, it, ko, nl, no, pl, pt, ro, ru, sr, sv, tr, uk`）不動，留給 Crowdin pipeline 同步。

**翻譯流程**：

1. 先在 `app_zh.arb` 加 key + `@metadata`（placeholders）
2. 以繁中為基準，依術語表 `docs/術語表.md` 翻其他 8 個語系
3. 跑 `flutter gen-l10n` 重產 `app_localizations*.dart`
4. CLAUDE.md 提交前品質檢查：`dart format` + `flutter analyze` + `flutter test`

### 7. Logger

新樹 `release.notes`（與既有 `release`、`release.notes` 對齊 `release.*` 命名）：

- `Logger('release.notes').info('fetch start version=$version')`
- `Logger('release.notes').info('fetch success tag=${release.tagName}')`
- `Logger('release.notes').warning('fetch failed: $e')`

URL 不含敏感資料（公開 repo + 公開 version），無需 `sanitizeUrl`。

## 套件依賴

無新增。完全重用既有 `http`、`pub_semver`、`markdown_widget`、`flutter_riverpod`、`logging`。

## 測試策略

### `test/services/app_release_checker_test.dart` 擴充

```
group 'fetchReleaseByVersion':
  - happy path: 200 + valid JSON → AppRelease 正確 parse
  - 404 → throws ReleaseCheckNotFound(tag: 'v1.1.0')
  - 5xx → throws ReleaseCheckServer(status)
  - 403 + x-ratelimit-remaining: 0 → throws ReleaseCheckRateLimited
  - 200 但 body 不是 JSON object → throws ReleaseCheckFormat
  - 200 但缺 tag_name → throws ReleaseCheckFormat
  - SocketException → throws ReleaseCheckNetwork
  - TimeoutException → throws ReleaseCheckTimeout
  - version 帶 build metadata（'1.1.0+2'）→ 打的 endpoint 是 .../releases/tags/v1.1.0
  - version 不合法（'foo'）→ throws ReleaseCheckFormat
```

`MockClient` 用 `package:http/testing.dart`，並驗 `request.url.path` 確保 endpoint 正確。

### `test/state/current_release_test.dart`（新檔）

```
- 首次 watch → 打一次 API，state 變 AsyncData
- 重複 watch 同一 version → 不重打 API（FutureProvider.family 自帶 cache）
- 不同 version key → 各自打一次 API
- ref.invalidate(currentReleaseProvider(version)) → 重新 fetch
- service 拋 ReleaseCheckError → state 變 AsyncError，error 為對應子類
```

用 `ProviderContainer` + override `httpClientProvider` 為 `MockClient`。

### `test/widgets/dialogs/current_release_dialog_test.dart`（新檔）

```
- loading 狀態：render skeleton；actions 只有 [Close]
- data 狀態：render ReleaseNotesContent；actions 有 [OpenOnGitHub] [Close]
- ReleaseCheckNotFound：render not-found 訊息（含 version）；actions [OpenReleasesPage] [Close]
- ReleaseCheckRateLimited：render rate-limited 訊息；actions [OpenReleasesPage] [Close]
- ReleaseCheckNetwork：render network 訊息；actions [Retry] [Close]
- 按 [Retry] → ref.invalidate 被呼叫（用 ProviderObserver 驗）
- 按 [Close] → Navigator.pop
```

UI 測試用 `ProviderScope` override `currentReleaseProvider` family 為 stub。

### `test/widgets/new_version_dialog_test.dart`

既有測試需確認 `_ReleaseCard` → `ReleaseNotesContent` 重構後仍全綠。若既有測試是用 `find.byType(_ReleaseCard)` 之類的 private type，改用 `find.byType(ReleaseNotesContent)`。

### 人工驗證（`flutter run -d windows`）

1. 設定頁「關於」section：版本號右側出現「查看更新內容」按鈕
2. 點按鈕 → dialog 立即開啟，內部短暫 skeleton → 切換成 content
3. 內容渲染正確（標題、發布日期、Markdown body）
4. 按「在 GitHub 上開啟」→ 外部瀏覽器跳到正確 release URL，dialog 關閉
5. 把 hosts 擋 api.github.com → 重開 app 點按鈕 → dialog 顯示 network error + [Retry] [Close]
6. 按 [Retry] → 重新 fetch（仍失敗，仍顯示 error）
7. 解除 hosts 擋 → 按 [Retry] → 成功顯示內容
8. 暫時把 `pubspec.yaml` version 改成不存在的（例 `9.9.9+1`）重 build → 點按鈕 → 顯示 not-found 訊息 + [OpenReleasesPage]
9. 切換語系（中/英/日）→ 文字正確翻譯

## YAGNI 邊界（明確不做）

- **歷史 N 版列表**：使用者需求字面是「目前版本」，不延伸做歷史；要看歷史請走「Open GitHub Releases page」按鈕
- **持久化快取**：release notes 偶爾會被作者更新（補錯字、補圖），同 app 生命週期內快取即可；不寫 SharedPreferences
- **預先 fetch**：設定頁開啟時不背景 fetch，只在使用者點按鈕才打 API（節省 quota、避免 settings 頁 first-frame lag）
- **「在 GitHub 上開啟」的內嵌 webview**：跳外部瀏覽器即可，與既有 `NewVersionDialog` 行為一致
- **「複製連結」按鈕**：不放，使用者用「在 GitHub 上開啟」+ 瀏覽器位址列複製即可
- **新通用按鈕字串**：「重試」「關閉」沿用既有 `actionRetry` / `actionClose`，不為這次新功能新增任何 `common*` 通用 key
