# 新版本通知（New Version Notification）設計

對齊舊版（master, Electron）的版本通知行為，移植到新版 Flutter rewrite。

## 背景

舊版做法：

- Electron 主程序用 `electron-updater` 背景檢查（`autoDownload: false`、`autoInstallOnAppQuit: false`）
- 偵測到 `update-available` 後 IPC 通知 renderer
- Renderer 用 GitHub REST API `listReleases` 抓所有 release，把「目前版本之後」的所有 release notes 用 markdown → HTML 串接顯示
- modal 按鈕「下載」→ 開外部瀏覽器到 `release.html_url`

新版 (Flutter rewrite) 現狀：

- 無 `electron-updater` 等價物（Flutter desktop 無原生 auto-update）
- 已有套件：`package_info_plus`、`http`、`url_launcher`、`shared_preferences`、`flutter_riverpod`
- AppBar 已顯示 `${appName} v$version`；設定頁「關於」區塊顯示 `settingsAboutVersion(version)`
- 注意：既有 `UpdateProgress` / `UpdateError` 是「祈願記錄更新」用途，新功能命名避免衝突（採 `AppRelease` / `ReleaseCheck` 詞彙）

## 需求決定

| 項目 | 決定 |
|---|---|
| 檢查觸發 | 啟動時自動 + 設定頁手動按鈕 |
| 提醒頻率 | 每次啟動都提醒；可「跳過此版本」（被跳過後該版本不再提醒，更新版仍會提醒） |
| Release notes 顯示 | 目前版到最新版之間的所有累積（多個 release 串接） |
| Markdown 渲染 | `markdown_widget` 套件（`flutter_markdown` 已 deprecated） |
| Pre-release / draft | 過濾，只抓正式版 |
| 下載行為 | 「前往下載」→ `url_launcher` 開 release html_url；不做自動下載/安裝 chain |
| 已是最新版回饋 | 手動觸發 → Snackbar；啟動自動觸發 → 靜默 |
| 錯誤處理 | 手動 Snackbar；啟動自動靜默（debugPrint） |
| 自動檢查開關 | 不提供（YAGNI；可用「跳過此版本」迴避） |

## 架構總覽

```
services/app_release_checker.dart   純函式：打 GitHub API、過濾、版本比對、回 List<AppRelease>
state/app_release.dart              Riverpod Notifier：管 ReleaseCheckState、處理 skipped 偏好
widgets/dialogs/new_version_dialog.dart  Modal：列出累積 release notes + 三顆按鈕
services/settings_storage.dart      AppSettings 擴 skippedReleaseTag
data/app_repo.dart                  新增：repo 座標常數（owner / repo / githubUrl / apiBase）
```

啟動自動 + 手動兩入口共用同一個 notifier。觸發點：

- 啟動：`AppShell.initState` 內 `addPostFrameCallback` 呼叫 `check(manual: false)`
- 手動：設定頁「關於」按鈕呼叫 `check(manual: true)`

職責切分：

- `AppShell` 只 listen `ReleaseAvailable` → 開 dialog
- `SettingsPage` 只 listen `ReleaseUpToDate` / `ReleaseCheckFailed` → Snackbar

兩個 listener 互不搶 case。

## 詳細設計

### 1. Repo 座標常數

新檔 `lib/data/app_repo.dart`，集中專案 repo 資訊。未來 fork 給其他遊戲，改這兩行常數即可全專案搞定。

```dart
class AppRepo {
  const AppRepo._();
  static const String owner = 'GoneTone';
  static const String repo = 'genshin-impact-wish-gacha-analyzer';
  static const String githubUrl = 'https://github.com/$owner/$repo';
  static const String apiBase = 'https://api.github.com/repos/$owner/$repo';
}
```

同時：

- `lib/data/team_info.dart` 內舊的 `appGithubUrl` 常數移除，所有 reference 換成 `AppRepo.githubUrl`

### 2. Service 層（純函式 + 錯誤型別）

`lib/services/app_release_checker.dart`：

```dart
class AppRelease {
  final String tagName;          // "v1.1.0"
  final String version;          // "1.1.0"（剝掉 v）
  final String name;
  final String body;             // Markdown
  final String htmlUrl;
  final DateTime publishedAt;
}

sealed class ReleaseCheckError { const ReleaseCheckError(); }
class ReleaseCheckNetwork extends ReleaseCheckError { const ReleaseCheckNetwork(); }
class ReleaseCheckTimeout extends ReleaseCheckError { const ReleaseCheckTimeout(); }
class ReleaseCheckRateLimited extends ReleaseCheckError { const ReleaseCheckRateLimited(); }
class ReleaseCheckServer extends ReleaseCheckError { const ReleaseCheckServer(this.status); final int status; }
class ReleaseCheckFormat extends ReleaseCheckError { const ReleaseCheckFormat(); }

/// 抓 GitHub Releases API，過濾 prerelease/draft，
/// 回傳比 currentVersion 新的 release（新到舊）。空 list = 無更新。
Future<List<AppRelease>> fetchNewerReleases({
  required String currentVersion,
  required http.Client client,
});
```

實作細節：

- Endpoint：`${AppRepo.apiBase}/releases`（不用 `/releases/latest`，要多筆做累積 changelog）
- 過濾：`draft == false && prerelease == false`
- 版本比對：引入 `pub_semver`，用 `Version.parse`；正確處理 `1.1.0` vs `1.0.10` 與 pre-release/build metadata
- Tag 容錯：`v` 前綴剝掉再 parse；無法 parse 的 tag 直接跳過
- Timeout：`client.get(...).timeout(Duration(seconds: 10))`
- 錯誤對應：
  - `SocketException` / `http.ClientException` → `ReleaseCheckNetwork`
  - `TimeoutException` → `ReleaseCheckTimeout`
  - HTTP 403 + `X-RateLimit-Remaining: 0` → `ReleaseCheckRateLimited`
  - 其他非 200 → `ReleaseCheckServer(status)`
  - `FormatException` / JSON shape 錯 → `ReleaseCheckFormat`

i18n 留在 notifier 端，service 不認 `AppLocalizations` 保純函式 + 易測。

### 3. State Notifier

`lib/state/app_release.dart`：

```dart
sealed class ReleaseCheckState { const ReleaseCheckState(); }
class ReleaseIdle extends ReleaseCheckState { const ReleaseIdle(); }
class ReleaseChecking extends ReleaseCheckState { const ReleaseChecking(); }
class ReleaseUpToDate extends ReleaseCheckState { const ReleaseUpToDate(); }
class ReleaseAvailable extends ReleaseCheckState {
  const ReleaseAvailable(this.releases);
  final List<AppRelease> releases;  // 新到舊，[0] = 最新版
}
class ReleaseCheckFailed extends ReleaseCheckState {
  const ReleaseCheckFailed(this.reason);
  final String reason;              // 已 localize 的 user-readable 字串
}

class AppReleaseNotifier extends Notifier<ReleaseCheckState> {
  @override
  ReleaseCheckState build() => const ReleaseIdle();

  Future<void> check({required bool manual});
  Future<void> skipVersion(String tagName);
}

final appReleaseProvider =
    NotifierProvider<AppReleaseNotifier, ReleaseCheckState>(AppReleaseNotifier.new);
```

行為：

- `check(manual: bool)`：
  1. 設 `ReleaseChecking`
  2. 從 `appVersionProvider` 讀 currentVersion
  3. 從 `httpClientProvider`（新增）讀 client，呼叫 `fetchNewerReleases`
  4. 成功且空 list → `ReleaseUpToDate`
  5. 成功且非空：
     - `manual == false` 且 `releases.first.tagName == settings.skippedReleaseTag` → 維持 idle（不打擾）
     - 其他 → `ReleaseAvailable(releases)`
  6. 拋 `ReleaseCheckError`：
     - `manual == false` → 維持 idle、`debugPrint`
     - `manual == true` → `ReleaseCheckFailed(localized)`；i18n 在這裡解
- `skipVersion(tagName)`：呼叫 `settingsNotifier.setSkippedReleaseTag(tagName)`

新增 `httpClientProvider`（簡單 `Provider<http.Client>((_) => http.Client())`），測試可 override。

### 4. Settings 擴展

`lib/services/settings_storage.dart`：

- `AppSettings` 加欄位 `final String? skippedReleaseTag;`（預設 null）
- `SettingsStorage` 加 key `_kSkippedReleaseTag = 'pref.skippedReleaseTag'`
- `load` / `save` 對應讀寫
- `copyWith` 加 `String? skippedReleaseTag, bool clearSkippedReleaseTag = false` 參數

`lib/state/settings.dart`：

- `SettingsNotifier` 加 `Future<void> setSkippedReleaseTag(String? tag)`（null 代表清除）

### 5. UI

**`lib/widgets/dialogs/new_version_dialog.dart`**（新檔）

`AlertDialog`：

- Title：`Row` = `Icon(Icons.system_update)` + `l.updateTitle(latestTag)`（例：「有新版本 v1.2.0 可用」）
- Content：`SizedBox(width: 560)` 包 `SingleChildScrollView` 包 `Column`：
  - 每個 release 一張 `Card`：
    - Header：tag + `DateFormat('yyyy-MM-dd').format(publishedAt.toLocal())`
    - Body：`MarkdownBlock(data: release.body)`（`markdown_widget` 的 widget）
  - 多 release 之間 `SizedBox(height: AppSpacing.m)`
- Actions：
  - `TextButton`「跳過此版本」→ `notifier.skipVersion(latestTag)` + `Navigator.pop`
  - `TextButton`「稍後再說」→ `Navigator.pop`
  - `FilledButton.icon(Icons.download)`「前往下載」→ `launchUrl(Uri.parse(releases[0].htmlUrl), mode: LaunchMode.externalApplication)` + `Navigator.pop`

dialog 最大高度限 60% 螢幕高（`ConstrainedBox(maxHeight: MediaQuery.of(ctx).size.height * 0.6)`）避免長 changelog 撐爆。

**`lib/pages/app_shell.dart`**

新增啟動觸發 + dialog listener：

```dart
class _AppShellState extends ConsumerState<AppShell> {
  bool _dialogOpen = false;
  bool _releaseDialogOpen = false;   // 新增

  @override
  void initState() {                  // 新增
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appReleaseProvider.notifier).check(manual: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 既有：祈願記錄更新 dialog listener
    ref.listen<UpdateProgress?>(...);

    // 新增：版本更新 dialog listener
    ref.listen<ReleaseCheckState>(appReleaseProvider, (prev, next) {
      if (next is ReleaseAvailable && !_releaseDialogOpen) {
        _releaseDialogOpen = true;
        showDialog(
          context: context,
          builder: (_) => NewVersionDialog(releases: next.releases),
        ).whenComplete(() => _releaseDialogOpen = false);
      }
    });
    // ... 其餘 build 不變
  }
}
```

**`lib/pages/settings_page.dart`**

`_AboutContent` 內版本號旁加按鈕，並 listen state 顯示 Snackbar：

```dart
// 在 _AboutContent build 內
ref.listen<ReleaseCheckState>(appReleaseProvider, (prev, next) {
  if (next is ReleaseUpToDate) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.updateAlreadyLatest)),
    );
  } else if (next is ReleaseCheckFailed) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.updateCheckFailed(next.reason))),
    );
  }
});

final checking = ref.watch(appReleaseProvider) is ReleaseChecking;

OutlinedButton.icon(
  onPressed: checking
      ? null
      : () => ref.read(appReleaseProvider.notifier).check(manual: true),
  icon: checking
      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
      : const Icon(Icons.refresh, size: 18),
  label: Text(checking ? l.updateChecking : l.updateCheckButton),
);
```

### 6. i18n 新增字串

只在 template `app_zh_Hant.arb` 補上 key（含 `@metadata`）。其他 9 個語言 ARB 不放佔位，由 Crowdin 後續翻譯；缺 key 時 `gen_l10n` 會自動 fallback 到 template，不會 build error：

```
updateTitle              → "有新版本 {version} 可用"
updateReleasedAt         → "發布於 {date}"
updateButtonDownload     → "前往下載"
updateButtonSkip         → "跳過此版本"
updateButtonLater        → "稍後再說"
updateCheckButton        → "檢查更新"
updateChecking           → "檢查中…"
updateAlreadyLatest      → "已是最新版本"
updateCheckFailed        → "檢查更新失敗：{reason}"
updateErrorNetwork       → "無法連線，請檢查網路"
updateErrorTimeout       → "請求逾時"
updateErrorRateLimited   → "GitHub API 配額用盡，請稍後再試"
updateErrorServer        → "伺服器錯誤 (HTTP {status})"
updateErrorFormat        → "回應格式異常"
```

## 套件依賴

`pubspec.yaml` 新增：

```yaml
dependencies:
  pub_semver: ^2.2.0
  markdown_widget: ^2.3.2+8   # 採最新 stable；版本以 pub.dev 為準
```

`http` / `package_info_plus` / `shared_preferences` / `url_launcher` 已存在。

## 測試策略

`test/services/app_release_checker_test.dart`（純函式，最容易測，用 `package:http/testing.dart` 的 `MockClient`）：

1. 正常 3 筆 release、current = 1.0.0、最新 1.2.0 → 回傳 `[1.2.0, 1.1.0]`
2. 含 `prerelease: true` 與 `draft: true` 各一筆 → 兩筆被過濾
3. tag 格式錯（`weird-tag`）→ 該筆跳過，其他正常
4. current 與最新同版 → 空 list
5. 200 但 body 不是 JSON list → `ReleaseCheckFormat`
6. 503 → `ReleaseCheckServer(503)`
7. 403 + rate-limit header → `ReleaseCheckRateLimited`
8. `SocketException` → `ReleaseCheckNetwork`
9. 慢回應 + timeout → `ReleaseCheckTimeout`

`test/state/app_release_test.dart`（用 `ProviderContainer` + override `httpClientProvider` / `appVersionProvider` / `settingsProvider`）：

1. service 回 `[1.2.0]`、skippedReleaseTag = null → state 變 `ReleaseAvailable`
2. service 回 `[1.2.0]`、skippedReleaseTag = `v1.2.0`、`manual=false` → state 維持 `ReleaseIdle`
3. 同上 `manual=true` → state 變 `ReleaseAvailable`（手動觸發無視 skip）
4. service 拋 error、`manual=false` → state 維持 `ReleaseIdle`
5. service 拋 error、`manual=true` → state 變 `ReleaseCheckFailed`
6. service 回空 list、`manual=true` → state 變 `ReleaseUpToDate`

UI 不寫 widget test（與既有 `UpdateProgressDialog` 一致），人工驗證走 `flutter run -d windows`：

- 啟動時 modal 跳出、markdown 正常渲染
- 點「前往下載」開外部瀏覽器到正確 release URL
- 點「跳過此版本」後重啟不再跳；推 release 更新版會再跳
- 設定頁手動按鈕：已是最新 → Snackbar；網路斷 → Snackbar 錯誤訊息

## YAGNI 邊界（明確不做）

- 自動下載 / 安裝 chain
- 「不再提醒任何版本」總開關
- 版本檢查結果快取（每次啟動 1 次 API 呼叫，量極低）
- changelog 摺疊 UI（直接 scroll）
- 自製 i18n 化 release notes（GitHub release body 由 repo 作者決定語言）
