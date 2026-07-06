# Google Drive 雲端同步 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用者連結自己的 Google 帳號後，卡池記錄以手動匯出同格式（`AccountsBundle`）自動備份到 Google Drive `appDataFolder` 並雙向同步；同步合併出新記錄時自動補抓 HoYoWiki 物品資料。

**Architecture:** 沿用現有 `exportAccounts`／`importAccounts`／`BannerStorage.mergeWith` 資料路徑，新增三層：`GoogleAuthService`（OAuth＋token 安全儲存）→ `DriveSyncRemote`（appDataFolder 單檔下載／上傳）→ `runSyncRound`（下載→合併→上傳編排，純函式可測）。`CloudSyncNotifier`（Riverpod）管理連結狀態、四個觸發入口與 5 秒 debounce；同步合併出新記錄時 fire-and-forget 呼叫 `GachaRepository.fetchItemImagesForCloudSync()` 走既有 HoYoWiki 進度管線。程式碼高度平移自姐妹專案（鳴潮）已合併的最終實作（PR #45＋#47），只做本專案適配。

**Tech Stack:** Flutter（Windows only）、Riverpod 3.x NotifierProvider、`googleapis`（Drive v3＋oauth2 userinfo）、`googleapis_auth`（installed-app loopback 授權）、`flutter_secure_storage`（DPAPI 存 refresh token）、`synchronized` 語意由單飛旗標實現（不需新增鎖）。

**Spec:** `docs/superpowers/specs/2026-07-06-google-drive-cloud-sync-design.md`

## Global Constraints

- 所有 Flutter／Dart 指令優先透過 `fvm`（`fvm flutter test` 等）；找不到 fvm 才退回 `flutter`／`dart`。
- 每個 task 的 commit 前置條件：`fvm dart format lib/ test/`（勿對 `.` 跑）、`fvm flutter analyze` 輸出 `No issues found!`、`fvm flutter test` 輸出 `All tests passed!`。
- Commit message 一律英文、conventional commits；**絕不 `git push`**。
- 所有新宣告（class／method／field／top-level，含 private）要有一行 `///` dartdoc；Flutter override（`build()` 等）不寫。
- UI 文字只改 **9 個已有實體翻譯的 ARB**：`lib/l10n/app_zh.arb`（template，先寫）、`app_zh_Hans.arb`、`app_en.arb`、`app_ja.arb`、`app_es.arb`、`app_fr.arb`、`app_pt_BR.arb`、`app_th.arb`、`app_vi.arb`；其餘空殼 ARB 由 Crowdin 補，**勿動**。改完跑 `fvm flutter gen-l10n`。
- 中文文案用全形標點，但省略號一律 ASCII `...`；「祈願／卡池」術語對照各 ARB 既有翻譯（如 `gachaType301` 等 key）用詞。
- Dialog 一律用 `AppDialog`（透過既有 `confirm_dialog.dart` helper）。
- Logger 樹：`cloudsync.auth`、`cloudsync.sync`；UID 過 `sanitizeUid`（`lib/services/log_sanitize.dart`）；**絕不記 token 內容**。
- 狀態管理一律 `NotifierProvider`（Riverpod 3.x）。
- CI（workflow YAML 與其呼叫的 script）的 throw／Write-Host 訊息一律英文。
- 分支：`feat/cloud-sync`（已存在，spec 已在上面）。

## File Structure

| 檔案 | 動作 | 職責 |
|------|------|------|
| `lib/services/cloud_sync/cloud_sync_config.dart` | Create | dart-define 憑證常數、scopes、雲端檔名、`isCloudSyncConfigured` |
| `lib/services/cloud_sync/token_store.dart` | Create | `TokenStore` 介面＋`SecureTokenStore`（flutter_secure_storage） |
| `lib/services/cloud_sync/google_auth_service.dart` | Create | 登入（loopback consent＋scope 驗證）、restore（refresh token 續期）、登出（revoke） |
| `lib/services/cloud_sync/cloud_sync_remote.dart` | Create | `CloudSyncRemote` 介面＋`DriveSyncRemote`（Drive v3 appDataFolder 單檔） |
| `lib/services/cloud_sync/cloud_sync_service.dart` | Create | `runSyncRound`（下載→合併→上傳）、`syncFingerprint`、pendingRemovals 剔除、schema 保護 |
| `lib/state/cloud_sync.dart` | Create | `CloudSyncNotifier`＋phase 狀態＋services providers＋debounce 觸發＋補抓觸發 |
| `lib/state/gacha_repository.dart` | Modify | `importBundleForCloudSync`（靜默匯入）＋`fetchItemImagesForCloudSync`＋`CloudSyncBusyException` |
| `lib/services/settings_storage.dart` | Modify | `AppSettings` 加 4 個 cloud 欄位＋`SettingsStorage` 讀寫 |
| `lib/state/settings.dart` | Modify | `SettingsNotifier` 加 cloud setter 群 |
| `lib/widgets/cards/cloud_sync_section.dart` | Create | 設定頁「雲端同步」區塊＋授權完成頁 HTML |
| `lib/pages/settings_page.dart` | Modify | 插入雲端同步 `SectionCard` |
| `lib/widgets/dialogs/confirm_dialog.dart` | Modify | 打字確認 dialog 加選配 checkbox |
| `lib/widgets/cards/account_management.dart` | Modify | 刪帳號時「同時從雲端移除」勾選 |
| `lib/pages/app_shell.dart` | Modify | 啟動時 `cloudSyncProvider.notifier.start()` |
| `.gitignore`／`scripts/build_installer/build_release.ps1`／`.github/workflows/release-windows.yml` | Modify | 憑證 dart-define 注入 |
| `README.md`／`README_EN.md`／`README_JA-JP.md`／`README_ZH-HANS.md` | Modify | 功能條目、隱私敘述修正、憑證開發指引 |
| ARB 九檔 | Modify | 新增 cloudSync* 字串 |

---

### Task 1: 新依賴與 cloud sync 設定欄位

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/services/settings_storage.dart`
- Modify: `lib/state/settings.dart`
- Test: `test/state/settings_cloud_sync_test.dart`

**Interfaces:**
- Consumes: 既有 `AppSettings`／`SettingsStorage`／`SettingsNotifier`（`lib/state/settings.dart` 的 `settingsProvider`、`waitForLoad()`）。
- Produces（後續 task 依賴的確切簽名）:
  - `AppSettings.cloudAccountEmail: String?`（null = 未連結）
  - `AppSettings.cloudAutoSyncEnabled: bool`（預設 `true`）
  - `AppSettings.cloudLastSyncedAt: DateTime?`
  - `AppSettings.cloudPendingRemovals: List<String>`（預設 `const []`）
  - `SettingsNotifier.setCloudAccount(String email)`（設 email 並把 autoSync 重設為 true）
  - `SettingsNotifier.clearCloudAccount()`（清 email＋lastSyncedAt、autoSync 重設 true；**pendingRemovals 保留**）
  - `SettingsNotifier.setCloudAutoSyncEnabled(bool value)`
  - `SettingsNotifier.setCloudLastSyncedAt(DateTime at)`
  - `SettingsNotifier.addCloudPendingRemoval(String uid)`
  - `SettingsNotifier.removeCloudPendingRemovals(List<String> uids)`

- [ ] **Step 1: 加依賴**

```
fvm flutter pub add googleapis googleapis_auth flutter_secure_storage
```

Expected: `pubspec.yaml` dependencies 出現三個套件，`Got dependencies!`。

- [ ] **Step 2: 寫失敗測試**

建立 `test/state/settings_cloud_sync_test.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 建立已完成載入的 container。
  Future<ProviderContainer> makeContainer() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    return container;
  }

  test('預設值：未連結、autoSync=true、無同步時間、無待移除', () async {
    final container = await makeContainer();
    final s = container.read(settingsProvider);
    expect(s.cloudAccountEmail, isNull);
    expect(s.cloudAutoSyncEnabled, isTrue);
    expect(s.cloudLastSyncedAt, isNull);
    expect(s.cloudPendingRemovals, isEmpty);
  });

  test('setCloudAccount 寫入 email 並重設 autoSync=true，持久化', () async {
    final container = await makeContainer();
    final n = container.read(settingsProvider.notifier);
    await n.setCloudAutoSyncEnabled(false);
    await n.setCloudAccount('user@example.com');

    expect(
      container.read(settingsProvider).cloudAccountEmail,
      'user@example.com',
    );
    expect(container.read(settingsProvider).cloudAutoSyncEnabled, isTrue);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.cloudAccountEmail, 'user@example.com');
    expect(reloaded.cloudAutoSyncEnabled, isTrue);
  });

  test('clearCloudAccount 清 email 與 lastSyncedAt，保留 pendingRemovals', () async {
    final container = await makeContainer();
    final n = container.read(settingsProvider.notifier);
    await n.setCloudAccount('user@example.com');
    await n.setCloudLastSyncedAt(DateTime.utc(2026, 7, 6));
    await n.addCloudPendingRemoval('800000001');

    await n.clearCloudAccount();

    final s = container.read(settingsProvider);
    expect(s.cloudAccountEmail, isNull);
    expect(s.cloudLastSyncedAt, isNull);
    expect(s.cloudAutoSyncEnabled, isTrue);
    expect(s.cloudPendingRemovals, ['800000001']);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.cloudAccountEmail, isNull);
    expect(reloaded.cloudPendingRemovals, ['800000001']);
  });

  test('setCloudLastSyncedAt 持久化為 UTC', () async {
    final container = await makeContainer();
    final n = container.read(settingsProvider.notifier);
    await n.setCloudLastSyncedAt(DateTime.utc(2026, 7, 6, 12, 30));

    final reloaded = await SettingsStorage.load();
    expect(reloaded.cloudLastSyncedAt, DateTime.utc(2026, 7, 6, 12, 30));
  });

  test('addCloudPendingRemoval 去重、removeCloudPendingRemovals 移除', () async {
    final container = await makeContainer();
    final n = container.read(settingsProvider.notifier);
    await n.addCloudPendingRemoval('A');
    await n.addCloudPendingRemoval('A');
    await n.addCloudPendingRemoval('B');
    expect(container.read(settingsProvider).cloudPendingRemovals, ['A', 'B']);

    await n.removeCloudPendingRemovals(['A']);
    expect(container.read(settingsProvider).cloudPendingRemovals, ['B']);
    final reloaded = await SettingsStorage.load();
    expect(reloaded.cloudPendingRemovals, ['B']);
  });

  test('pendingRemovals 損毀 JSON → 回空 list', () async {
    SharedPreferences.setMockInitialValues({
      'pref.cloudPendingRemovals': 'not-json',
    });
    final reloaded = await SettingsStorage.load();
    expect(reloaded.cloudPendingRemovals, isEmpty);
  });
}
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `fvm flutter test test/state/settings_cloud_sync_test.dart`
Expected: 編譯失敗（`cloudAccountEmail` 等欄位不存在）。

- [ ] **Step 4: 實作 AppSettings 欄位**

`lib/services/settings_storage.dart` 的 `AppSettings`：

1. constructor 加參數（放在 `this.dataLanguageSeeded = false,` 後）：

```dart
    this.cloudAccountEmail,
    this.cloudAutoSyncEnabled = true,
    this.cloudLastSyncedAt,
    this.cloudPendingRemovals = const [],
```

2. 欄位宣告（放在 `dataLanguageSeeded` 欄位後）：

```dart
  /// 已連結的 Google 帳號 email；null 代表未連結雲端同步。
  final String? cloudAccountEmail;

  /// 是否啟用自動雲端同步（App 啟動與資料變動後自動跑一輪）。
  final bool cloudAutoSyncEnabled;

  /// 上次雲端同步成功時間（UTC）；null 代表尚未同步過。
  final DateTime? cloudLastSyncedAt;

  /// 待從雲端移除的 UID 清單（刪帳號勾「連雲端一起刪」時排入，同步成功後清除）。
  final List<String> cloudPendingRemovals;
```

3. `copyWith` 加參數與對應行（參數放 `dataLanguageSeeded` 後；賦值行放 `dataLanguageSeeded:` 後）：

```dart
    String? cloudAccountEmail,
    bool clearCloudAccountEmail = false,
    bool? cloudAutoSyncEnabled,
    DateTime? cloudLastSyncedAt,
    bool clearCloudLastSyncedAt = false,
    List<String>? cloudPendingRemovals,
```

```dart
    cloudAccountEmail: clearCloudAccountEmail
        ? null
        : (cloudAccountEmail ?? this.cloudAccountEmail),
    cloudAutoSyncEnabled: cloudAutoSyncEnabled ?? this.cloudAutoSyncEnabled,
    cloudLastSyncedAt: clearCloudLastSyncedAt
        ? null
        : (cloudLastSyncedAt ?? this.cloudLastSyncedAt),
    cloudPendingRemovals: cloudPendingRemovals ?? this.cloudPendingRemovals,
```

4. `SettingsStorage` 加 key 常數（放 `_kDataLanguage` 後）：

```dart
  /// SharedPreferences key：已連結的雲端帳號 email。
  static const _kCloudAccountEmail = 'pref.cloudAccountEmail';

  /// SharedPreferences key：自動雲端同步開關。
  static const _kCloudAutoSyncEnabled = 'pref.cloudAutoSyncEnabled';

  /// SharedPreferences key：上次雲端同步成功時間（ISO8601 UTC）。
  static const _kCloudLastSyncedAt = 'pref.cloudLastSyncedAt';

  /// SharedPreferences key：待雲端移除 UID 清單 JSON。
  static const _kCloudPendingRemovals = 'pref.cloudPendingRemovals';
```

5. `load()` 回傳的 `AppSettings(...)` 加：

```dart
      cloudAccountEmail: prefs.getString(_kCloudAccountEmail),
      cloudAutoSyncEnabled: prefs.getBool(_kCloudAutoSyncEnabled) ?? true,
      cloudLastSyncedAt: _parseUtcTime(prefs.getString(_kCloudLastSyncedAt)),
      cloudPendingRemovals: _parseOrder(prefs.getString(_kCloudPendingRemovals)),
```

（`_parseOrder` 直接複用既有 helper——同樣是 string list JSON。）

6. `save()` 加（放 `maskUidInUi` 寫入後、dataLanguage 區塊前後皆可）：

```dart
    if (s.cloudAccountEmail == null) {
      await prefs.remove(_kCloudAccountEmail);
    } else {
      await prefs.setString(_kCloudAccountEmail, s.cloudAccountEmail!);
    }
    await prefs.setBool(_kCloudAutoSyncEnabled, s.cloudAutoSyncEnabled);
    if (s.cloudLastSyncedAt == null) {
      await prefs.remove(_kCloudLastSyncedAt);
    } else {
      await prefs.setString(
        _kCloudLastSyncedAt,
        s.cloudLastSyncedAt!.toUtc().toIso8601String(),
      );
    }
    await prefs.setString(
      _kCloudPendingRemovals,
      jsonEncode(s.cloudPendingRemovals),
    );
```

7. 新增 private helper（放 `_parseOrder` 後）：

```dart
  /// 解析 ISO8601 時間字串為 UTC DateTime，null 或格式錯誤回 null。
  static DateTime? _parseUtcTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }
```

- [ ] **Step 5: 實作 SettingsNotifier setter 群**

`lib/state/settings.dart` 的 `SettingsNotifier`（放在 `applyImportedPreferences` 後）：

```dart
  /// 記錄已連結的雲端帳號 email，並把自動同步重設為預設開啟。
  Future<void> setCloudAccount(String email) async {
    state = state.copyWith(
      cloudAccountEmail: email,
      cloudAutoSyncEnabled: true,
    );
    await SettingsStorage.save(state);
    Logger('cloudsync.auth').info('cloud account linked');
  }

  /// 清除雲端帳號連結（email、上次同步時間），autoSync 重設為 true。
  ///
  /// 待移除清單刻意**保留**：刪帳號的意圖在重新連結後仍應補刪。
  Future<void> clearCloudAccount() async {
    state = state.copyWith(
      clearCloudAccountEmail: true,
      clearCloudLastSyncedAt: true,
      cloudAutoSyncEnabled: true,
    );
    await SettingsStorage.save(state);
    Logger('cloudsync.auth').info('cloud account unlinked');
  }

  /// 切換自動雲端同步開關並持久化。
  Future<void> setCloudAutoSyncEnabled(bool value) async {
    state = state.copyWith(cloudAutoSyncEnabled: value);
    await SettingsStorage.save(state);
    Logger('cloudsync.sync').info('autoSync toggled=$value');
  }

  /// 記錄上次雲端同步成功時間並持久化。
  Future<void> setCloudLastSyncedAt(DateTime at) async {
    state = state.copyWith(cloudLastSyncedAt: at.toUtc());
    await SettingsStorage.save(state);
  }

  /// 把 [uid] 排入待雲端移除清單（去重）並持久化。
  Future<void> addCloudPendingRemoval(String uid) async {
    if (state.cloudPendingRemovals.contains(uid)) return;
    state = state.copyWith(
      cloudPendingRemovals: List.unmodifiable([
        ...state.cloudPendingRemovals,
        uid,
      ]),
    );
    await SettingsStorage.save(state);
  }

  /// 從待雲端移除清單移除 [uids]（同步成功後呼叫）並持久化。
  Future<void> removeCloudPendingRemovals(List<String> uids) async {
    if (uids.isEmpty) return;
    final remove = uids.toSet();
    state = state.copyWith(
      cloudPendingRemovals: List.unmodifiable(
        state.cloudPendingRemovals.where((u) => !remove.contains(u)),
      ),
    );
    await SettingsStorage.save(state);
  }
```

（`state/settings.dart` 已 import `package:logging/logging.dart`，不需再加。）

- [ ] **Step 6: 跑測試確認通過**

Run: `fvm flutter test test/state/settings_cloud_sync_test.dart`
Expected: All tests passed!

- [ ] **Step 7: 全套驗證＋commit**

```
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
git add pubspec.yaml pubspec.lock lib/services/settings_storage.dart lib/state/settings.dart test/state/settings_cloud_sync_test.dart
git commit -m "feat(cloud-sync): add deps and cloud sync settings fields"
```

---

### Task 2: OAuth 設定常數、TokenStore 與 GoogleAuthService

**Files:**
- Create: `lib/services/cloud_sync/cloud_sync_config.dart`
- Create: `lib/services/cloud_sync/token_store.dart`
- Create: `lib/services/cloud_sync/google_auth_service.dart`
- Test: `test/services/cloud_sync/google_auth_service_test.dart`

**Interfaces:**
- Consumes: 無（僅外部套件）。
- Produces:
  - `isCloudSyncConfigured: bool`（getter）、`debugCloudSyncConfiguredOverride: bool?`（@visibleForTesting）、`cloudSyncFileName: String`、`cloudSyncScopes: List<String>`
  - `abstract class TokenStore { Future<String?> readRefreshToken(); Future<void> writeRefreshToken(String token); Future<void> deleteRefreshToken(); }`
  - `class SecureTokenStore implements TokenStore`
  - `class CloudReauthRequiredException implements Exception`
  - `class CloudScopeMissingException implements Exception`
  - `class CloudAuthSession { final AuthClient client; final String email; final String refreshToken; }`
  - `class GoogleAuthService { Future<CloudAuthSession> signIn(void Function(String url) openUrl, {String? postAuthPage}); Future<AuthClient?> restore(); Future<void> signOut(); Future<void> revokeToken(String refreshToken); }`（方法皆 virtual，測試可 subclass override）
  - top-level `bool isInvalidGrant(Object e)`、`bool isInsufficientScope(Object e)`、`bool hasRequiredCloudScopes(Iterable<String> granted)`、`AccessCredentials buildResumeCredentials(String refreshToken)`

- [ ] **Step 1: 寫失敗測試（純邏輯部分）**

建立 `test/services/cloud_sync/google_auth_service_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/google_auth_service.dart';

void main() {
  group('isInvalidGrant', () {
    test('訊息含 invalid_grant → true', () {
      expect(isInvalidGrant(Exception('Refresh failed: invalid_grant')), isTrue);
    });

    test('一般網路錯誤 → false', () {
      expect(isInvalidGrant(Exception('Connection refused')), isFalse);
    });
  });

  group('isInsufficientScope', () {
    test('insufficient_scope → true', () {
      expect(isInsufficientScope(Exception('401 insufficient_scope')), isTrue);
    });

    test('insufficient authentication scopes → true', () {
      expect(
        isInsufficientScope(
          Exception('Request had insufficient authentication scopes.'),
        ),
        isTrue,
      );
    });

    test('一般網路錯誤 → false', () {
      expect(isInsufficientScope(Exception('Connection refused')), isFalse);
    });
  });

  group('hasRequiredCloudScopes', () {
    test('含 drive.appdata → true', () {
      expect(
        hasRequiredCloudScopes([
          'https://www.googleapis.com/auth/drive.appdata',
          'email',
        ]),
        isTrue,
      );
    });

    test('漏勾 drive.appdata → false', () {
      expect(hasRequiredCloudScopes(['email']), isFalse);
    });
  });

  group('buildResumeCredentials', () {
    test('產出已過期的 UTC Bearer 種子憑證並保留 refresh token', () {
      final c = buildResumeCredentials('refresh-abc');
      expect(c.refreshToken, 'refresh-abc');
      expect(c.accessToken.type, 'Bearer');
      expect(c.accessToken.expiry.isUtc, isTrue);
      expect(c.accessToken.expiry.isBefore(DateTime.now().toUtc()), isTrue);
      expect(c.scopes, cloudSyncScopes);
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/services/cloud_sync/google_auth_service_test.dart`
Expected: 編譯失敗（檔案不存在）。

- [ ] **Step 3: 建立 cloud_sync_config.dart**

```dart
import 'package:flutter/foundation.dart';

/// Google Cloud Console「Desktop app」OAuth 用戶端 ID，建置時注入。
///
/// 以 `--dart-define-from-file=secrets/cloud_sync_defines.json`（本機，
/// git-ignored）或 CI 由 repo secrets 產生的同名檔注入；未注入時為空字串，
/// 雲端同步功能整體優雅停用（見 [isCloudSyncConfigured]）。
/// 不直接寫在原始碼：installed app 憑證雖依 Google 定義非機密，但會被
/// GitHub push protection 攔截。
const String cloudSyncClientId = String.fromEnvironment('CLOUD_SYNC_CLIENT_ID');

/// Google OAuth 用戶端 secret（Desktop app 類型），建置時注入（見
/// [cloudSyncClientId]）。
const String cloudSyncClientSecret = String.fromEnvironment(
  'CLOUD_SYNC_CLIENT_SECRET',
);

/// 測試用 override；null 時以憑證常數判斷。
@visibleForTesting
bool? debugCloudSyncConfiguredOverride;

/// 雲端同步是否已設定 OAuth 憑證；false 時設定頁顯示未設定提示、所有同步入口 no-op。
bool get isCloudSyncConfigured =>
    debugCloudSyncConfiguredOverride ??
    (cloudSyncClientId.isNotEmpty && cloudSyncClientSecret.isNotEmpty);

/// Google Drive appDataFolder 內的同步檔名，內容即 AccountsBundle JSON。
const String cloudSyncFileName = 'genshin_gacha_sync.json';

/// 要求的 OAuth scopes：appDataFolder 最小權限＋email（設定頁顯示已連結帳號）。
const List<String> cloudSyncScopes = [
  'https://www.googleapis.com/auth/drive.appdata',
  'email',
];
```

- [ ] **Step 4: 建立 token_store.dart**

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// refresh token 的安全儲存介面；抽象化以便測試注入 in-memory 實作。
abstract class TokenStore {
  /// 讀取已存的 refresh token；無則回 null。
  Future<String?> readRefreshToken();

  /// 寫入 refresh token。
  Future<void> writeRefreshToken(String token);

  /// 刪除已存的 refresh token。
  Future<void> deleteRefreshToken();
}

/// 以 flutter_secure_storage（Windows 底層 DPAPI）實作的 [TokenStore]。
class SecureTokenStore implements TokenStore {
  /// 底層安全儲存。
  static const _storage = FlutterSecureStorage();

  /// refresh token 的儲存 key。
  static const _kRefreshToken = 'cloudsync.refreshToken';

  /// 讀取已存的 refresh token。
  @override
  Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);

  /// 寫入 refresh token。
  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _kRefreshToken, value: token);

  /// 刪除已存的 refresh token。
  @override
  Future<void> deleteRefreshToken() => _storage.delete(key: _kRefreshToken);
}
```

- [ ] **Step 5: 建立 google_auth_service.dart**

（平移自姐妹專案最終版，僅換 package import。）

```dart
import 'package:googleapis/oauth2/v2.dart' as oauth2;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/token_store.dart';

/// refresh token 已失效（使用者於 Google 端撤銷授權），需要重新連結時拋出。
class CloudReauthRequiredException implements Exception {
  /// 建立 [CloudReauthRequiredException]。
  const CloudReauthRequiredException();

  @override
  String toString() => 'CloudReauthRequiredException';
}

/// 授權結果未包含必要的 Drive scope（使用者在 Google 逐項授權頁漏勾）時拋出。
class CloudScopeMissingException implements Exception {
  /// 建立 [CloudScopeMissingException]。
  const CloudScopeMissingException();

  @override
  String toString() => 'CloudScopeMissingException';
}

/// 判斷例外是否為 OAuth `invalid_grant`（refresh token 被撤銷／過期）。
bool isInvalidGrant(Object e) => e.toString().contains('invalid_grant');

/// 判斷例外是否為 API 回報的「token 缺必要權限」。
///
/// 覆蓋兩種真實錯誤表面：googleapis_auth 的 `AuthenticatedClient` 對帶
/// `www-authenticate` header 的回應直接拋 `insufficient_scope`（生產環境
/// 實測主要路徑）；無該 header 時 googleapis 走 `DetailedApiRequestError`，
/// 訊息為 `insufficient authentication scopes` 或結構化 reason。
bool isInsufficientScope(Object e) {
  final s = e.toString();
  return s.contains('insufficient_scope') ||
      s.contains('insufficient authentication scopes') ||
      s.contains('ACCESS_TOKEN_SCOPE_INSUFFICIENT');
}

/// 檢查實際授予的 [granted] scopes 是否含雲端同步必要的 `drive.appdata`。
///
/// 只檢查 Drive scope：email 即使漏授，Google 也可能以
/// `userinfo.email` 等別名回傳，且缺 email 會在取 userinfo 時另行失敗。
bool hasRequiredCloudScopes(Iterable<String> granted) =>
    granted.contains('https://www.googleapis.com/auth/drive.appdata');

/// 以既存 refresh token 建立「已過期」的種子憑證，供 refreshCredentials 換新 access token。
AccessCredentials buildResumeCredentials(String refreshToken) =>
    AccessCredentials(
      AccessToken(
        'Bearer',
        '',
        DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      ),
      refreshToken,
      cloudSyncScopes,
    );

/// 登入成功的授權會話：可用的 [AuthClient]、帳號 email 與 refresh token。
class CloudAuthSession {
  /// 建立 [CloudAuthSession]。
  const CloudAuthSession({
    required this.client,
    required this.email,
    required this.refreshToken,
  });

  /// 自動續期的授權 HTTP client；用畢由呼叫端 close。
  final AuthClient client;

  /// 已連結帳號的 email。
  final String email;

  /// 本次授權取得的 refresh token；由呼叫端決定是否持久化。
  final String refreshToken;
}

/// 包住 [AutoRefreshingAuthClient]，close 時連同自建的底層 base client 一併關閉。
class _OwningAuthClient extends http.BaseClient implements AuthClient {
  /// 建立 [_OwningAuthClient]。
  _OwningAuthClient(this._inner, this._base);

  /// 實際的自動續期授權 client。
  final AutoRefreshingAuthClient _inner;

  /// 自建的底層 client，close 時一併關閉。
  final http.Client _base;

  /// 目前的授權憑證（委派給內部 client）。
  @override
  AccessCredentials get credentials => _inner.credentials;

  /// 發送授權請求（委派給內部 client）。
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  /// 關閉授權 client 與底層 HTTP client。
  @override
  void close() {
    _inner.close();
    _base.close();
    super.close();
  }
}

/// Google OAuth 授權服務：登入（系統瀏覽器 loopback）、以 refresh token 還原、登出。
class GoogleAuthService {
  /// 建立 [GoogleAuthService]。
  GoogleAuthService({
    required this.tokenStore,
    required this.baseClientFactory,
  });

  /// refresh token 的安全儲存。
  final TokenStore tokenStore;

  /// 建立底層 HTTP client 的工廠（測試注入 MockClient 用）。
  final http.Client Function() baseClientFactory;

  /// Logger 實例（授權流程）。
  static final _log = Logger('cloudsync.auth');

  /// OAuth 用戶端識別。
  static final _clientId = ClientId(cloudSyncClientId, cloudSyncClientSecret);

  /// 走 installed-app loopback 流程登入：[openUrl] 收到授權頁 URL 時開啟系統瀏覽器。
  ///
  /// [postAuthPage] 為授權成功後瀏覽器顯示的自訂 HTML（null 用套件預設英文頁）；
  /// 失敗路徑的回應頁套件未開放自訂。
  /// 回傳的 session 帶著 refresh token，是否寫入 [tokenStore] 交由呼叫端決定
  /// （避免取消連結後遲到的授權結果覆蓋較新的 token；見 [CloudAuthSession]）。
  Future<CloudAuthSession> signIn(
    void Function(String url) openUrl, {
    String? postAuthPage,
  }) async {
    _log.info('signIn start');
    final client = await clientViaUserConsent(
      _clientId,
      cloudSyncScopes,
      openUrl,
      customPostAuthPage: postAuthPage,
    );
    try {
      final refresh = client.credentials.refreshToken;
      if (refresh == null) {
        throw StateError('OAuth flow returned no refresh token');
      }
      // Google 逐項授權（granular consent）允許使用者漏勾 Drive 權限並照樣發
      // token；此時當場 revoke 並拋出，讓使用者立刻得知要重新授權，
      // 而不是等第一輪同步 403 才發現。
      final granted = client.credentials.scopes;
      if (!hasRequiredCloudScopes(granted)) {
        _log.warning(
          'signIn: drive.appdata not granted (granted=${granted.join(' ')})',
        );
        await revokeToken(refresh);
        throw const CloudScopeMissingException();
      }
      final email = await _fetchEmail(client);
      _log.info('signIn ok');
      return CloudAuthSession(
        client: client,
        email: email,
        refreshToken: refresh,
      );
    } catch (e) {
      client.close();
      rethrow;
    }
  }

  /// 以已存的 refresh token 還原授權 client；無 token 回 null。
  ///
  /// token 已被撤銷（invalid_grant）時拋 [CloudReauthRequiredException]。
  Future<AuthClient?> restore() async {
    final refresh = await tokenStore.readRefreshToken();
    if (refresh == null) {
      _log.info('restore: no stored token');
      return null;
    }
    final base = baseClientFactory();
    try {
      final refreshed = await refreshCredentials(
        _clientId,
        buildResumeCredentials(refresh),
        base,
      );
      _log.info('restore ok');
      return _OwningAuthClient(
        autoRefreshingClient(_clientId, refreshed, base),
        base,
      );
    } catch (e) {
      base.close();
      if (isInvalidGrant(e)) {
        _log.warning('restore: invalid_grant, reauth required');
        throw const CloudReauthRequiredException();
      }
      rethrow;
    }
  }

  /// 登出：向 Google revoke（盡力而為，失敗不阻擋）並刪除本機 refresh token。
  Future<void> signOut() async {
    final refresh = await tokenStore.readRefreshToken();
    if (refresh != null) {
      await revokeToken(refresh);
    }
    await tokenStore.deleteRefreshToken();
    _log.info('signOut done');
  }

  /// 向 Google revoke 指定的 refresh token（盡力而為，失敗僅記警告不拋出；
  /// 絕不把 token 內容寫進 log）。
  Future<void> revokeToken(String refreshToken) async {
    final base = baseClientFactory();
    try {
      final res = await base.post(
        Uri.parse('https://oauth2.googleapis.com/revoke'),
        body: {'token': refreshToken},
      );
      if (res.statusCode == 200) {
        _log.info('revoke ok');
      } else {
        _log.warning('revoke failed (ignored): HTTP ${res.statusCode}');
      }
    } catch (e) {
      _log.warning('revoke failed (ignored): $e');
    } finally {
      base.close();
    }
  }

  /// 以 userinfo API 取得已授權帳號的 email。
  Future<String> _fetchEmail(http.Client client) async {
    final info = await oauth2.Oauth2Api(client).userinfo.get();
    final email = info.email;
    if (email == null || email.isEmpty) {
      throw StateError('userinfo returned no email');
    }
    return email;
  }
}
```

> 注意：`signIn`／`restore`／`signOut` 是外部套件的 thin wrapper，單元測試只覆蓋純邏輯（`isInvalidGrant`／`isInsufficientScope`／`hasRequiredCloudScopes`／`buildResumeCredentials`）；真實 OAuth 流程於 Task 11 手動驗證。若 `clientViaUserConsent`（含 `customPostAuthPage` 參數）／`refreshCredentials`／`autoRefreshingClient` 的實際簽名與此處不符（以裝好的 googleapis_auth 版本為準），依套件原始碼調整呼叫方式，對外介面（`signIn`／`restore`／`signOut`）不變。

- [ ] **Step 6: 跑測試確認通過**

Run: `fvm flutter test test/services/cloud_sync/google_auth_service_test.dart`
Expected: All tests passed!

- [ ] **Step 7: 全套驗證＋commit**

```
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
git add lib/services/cloud_sync/ test/services/cloud_sync/
git commit -m "feat(cloud-sync): add OAuth config, token store and Google auth service"
```

---

### Task 3: CloudSyncRemote 介面與 DriveSyncRemote

**Files:**
- Create: `lib/services/cloud_sync/cloud_sync_remote.dart`
- Test: `test/services/cloud_sync/drive_sync_remote_test.dart`

**Interfaces:**
- Consumes: `cloudSyncFileName`（Task 2）。
- Produces:
  - `abstract class CloudSyncRemote { Future<String?> download(); Future<void> upload(String json); }`
  - `class DriveSyncRemote implements CloudSyncRemote { DriveSyncRemote(http.Client client); }`

- [ ] **Step 1: 寫失敗測試**

建立 `test/services/cloud_sync/drive_sync_remote_test.dart`（用 `MockClient` 模擬 Drive REST）：

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_remote.dart';

/// 回傳 JSON 200 回應。
http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('download：雲端無檔 → null', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/drive/v3/files');
      return _json({'files': <Object>[]});
    });
    final remote = DriveSyncRemote(client);
    expect(await remote.download(), isNull);
  });

  test('download：有檔 → 回傳內容', () async {
    final client = MockClient((req) async {
      if (req.url.queryParameters['alt'] == 'media') {
        return http.Response('{"hello":1}', 200);
      }
      return _json({
        'files': [
          {'id': 'file-1'},
        ],
      });
    });
    final remote = DriveSyncRemote(client);
    expect(await remote.download(), '{"hello":1}');
  });

  test('upload：雲端無檔 → 走 create（POST /upload）', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path == '/drive/v3/files') return _json({'files': <Object>[]});
      return _json({'id': 'new-file'});
    });
    final remote = DriveSyncRemote(client);
    await remote.upload('{"a":1}');
    expect(calls.any((c) => c.startsWith('POST /upload/drive/v3/files')), isTrue);
  });

  test('upload：雲端已有檔 → 走 update（PATCH /upload/.../file-1）', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path == '/drive/v3/files') {
        return _json({
          'files': [
            {'id': 'file-1'},
          ],
        });
      }
      return _json({'id': 'file-1'});
    });
    final remote = DriveSyncRemote(client);
    await remote.upload('{"a":1}');
    expect(
      calls.any((c) => c.startsWith('PATCH /upload/drive/v3/files/file-1')),
      isTrue,
    );
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/services/cloud_sync/drive_sync_remote_test.dart`
Expected: 編譯失敗（檔案不存在）。

- [ ] **Step 3: 實作 cloud_sync_remote.dart**

（平移自姐妹專案最終版，僅換 package import 與檔名常數來源。）

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';

/// 雲端同步檔的遠端存取介面；抽象化以便測試注入 fake。
abstract class CloudSyncRemote {
  /// 下載同步檔內容；檔案不存在回 null。
  Future<String?> download();

  /// 上傳（覆蓋）同步檔內容。
  Future<void> upload(String json);
}

/// 以 Google Drive v3 appDataFolder 實作的 [CloudSyncRemote]，單一檔案
/// [cloudSyncFileName]。
class DriveSyncRemote implements CloudSyncRemote {
  /// 建立 [DriveSyncRemote]，[client] 需為已授權的 HTTP client。
  DriveSyncRemote(http.Client client) : _api = drive.DriveApi(client);

  /// Drive v3 API 入口。
  final drive.DriveApi _api;

  /// Logger 實例（同步遠端存取）。
  static final _log = Logger('cloudsync.sync');

  /// 查找 appDataFolder 內同步檔的 file id；不存在回 null。
  ///
  /// orderBy 讓兩台電腦首次同步同時建檔時，後續各 client 穩定挑到同一個
  /// （最新的）檔案收斂，避免各自讀寫不同孤兒檔。
  Future<String?> _findFileId() async {
    final list = await _api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$cloudSyncFileName'",
      orderBy: 'modifiedTime desc',
      $fields: 'files(id)',
    );
    final files = list.files;
    if (files == null || files.isEmpty) return null;
    return files.first.id;
  }

  /// 下載 appDataFolder 內的同步檔內容；檔案不存在回 null。
  @override
  Future<String?> download() async {
    final id = await _findFileId();
    if (id == null) {
      _log.info('download: no remote file');
      return null;
    }
    final media =
        await _api.files.get(
              id,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      bytes.add(chunk);
    }
    _log.info('download: ${bytes.length} bytes');
    return utf8.decode(bytes.takeBytes());
  }

  /// 上傳（覆蓋）appDataFolder 內的同步檔；無檔時建立、有檔時更新。
  @override
  Future<void> upload(String json) async {
    final data = utf8.encode(json);
    final media = drive.Media(Stream.value(data), data.length);
    final id = await _findFileId();
    if (id == null) {
      await _api.files.create(
        drive.File()
          ..name = cloudSyncFileName
          ..parents = ['appDataFolder'],
        uploadMedia: media,
      );
      _log.info('upload: created, ${data.length} bytes');
    } else {
      await _api.files.update(drive.File(), id, uploadMedia: media);
      _log.info('upload: updated, ${data.length} bytes');
    }
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/services/cloud_sync/drive_sync_remote_test.dart`
Expected: All tests passed!（若 googleapis 實際 REST 路徑與 mock 斷言不符，以測試失敗訊息中的真實 method／path 修正**測試**斷言，實作不變。）

- [ ] **Step 5: 全套驗證＋commit**

```
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
git add lib/services/cloud_sync/cloud_sync_remote.dart test/services/cloud_sync/drive_sync_remote_test.dart
git commit -m "feat(cloud-sync): add Drive appDataFolder remote store"
```

---

### Task 4: 同步編排 runSyncRound 與 syncFingerprint

**Files:**
- Create: `lib/services/cloud_sync/cloud_sync_service.dart`
- Test: `test/services/cloud_sync/cloud_sync_service_test.dart`

**Interfaces:**
- Consumes: `CloudSyncRemote`（Task 3）、`importAccounts`／`AccountsBundle`／`UnsupportedSchemaVersionException`／`ForeignBundleException`（既有；注意本專案帳號欄位是 `a.data.uid`）。
- Produces:
  - `String syncFingerprint(String bundleJson)`——去除 `exported_at` 後的 SHA-256。
  - `sealed class CloudSyncOutcome`；`class CloudSyncSuccess extends CloudSyncOutcome { final String uploadedFingerprint; }`；`class CloudSyncSkippedSchemaTooNew extends CloudSyncOutcome`
  - `Future<CloudSyncOutcome> runSyncRound({ required CloudSyncRemote remote, required List<String> pendingRemovals, required Future<void> Function(AccountsBundle bundle) applyRemote, required String Function() exportLocal, required Future<void> Function(List<String> uids) clearPendingRemovals })`

**同步一輪的規則（測試即規格）：**
1. 雲端無檔 → 不合併，直接上傳本機。
2. 雲端有檔 → 解析＋剔除 pendingRemovals → `applyRemote` 合併 → 上傳本機 → 清 pendingRemovals。
3. 雲端 schema 過新 → 回 `CloudSyncSkippedSchemaTooNew`，**不合併、不上傳、不清 pendingRemovals**。
4. 雲端檔損毀（FormatException／ForeignBundle）→ 視為無檔（log severe），上傳本機自癒。
5. 剔除後帳號為空 → 跳過 `applyRemote`，仍上傳。

- [ ] **Step 1: 寫失敗測試**

建立 `test/services/cloud_sync/cloud_sync_service_test.dart`（帳號 JSON 用本專案格式：`uid`／`last_updated`／`banners`）：

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_remote.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_service.dart';

/// 記錄呼叫的 fake 遠端。
class _FakeRemote implements CloudSyncRemote {
  _FakeRemote({this.content});

  /// 目前雲端檔內容；null = 不存在。
  String? content;

  /// upload 被呼叫的次數。
  int uploads = 0;

  @override
  Future<String?> download() async => content;

  @override
  Future<void> upload(String json) async {
    uploads++;
    content = json;
  }
}

/// 產生多帳號的 bundle JSON（正確 app id；schema 可覆寫）。
String _bundleJson({List<String> uids = const ['800000001'], int? schema}) =>
    jsonEncode({
      'schema_version': schema ?? AccountsBundle.currentSchemaVersion,
      'app': accountsBundleAppId,
      'exported_at': '2026-07-06T00:00:00.000Z',
      'app_version': '1.6.0',
      'last_active_uid': uids.first,
      'accounts': [
        for (final uid in uids)
          {
            'uid': uid,
            'last_updated': '2026-07-01T00:00:00.000Z',
            'banners': {'301': <Object>[]},
          },
      ],
    });

/// 本機匯出內容（固定字串即可，內容真實性由整合層測試保證）。
String _localJson() => _bundleJson(uids: ['800000002']);

void main() {
  group('syncFingerprint', () {
    test('僅 exported_at 不同 → 指紋相同', () {
      final a = jsonDecode(_bundleJson()) as Map<String, dynamic>;
      final b = jsonDecode(_bundleJson()) as Map<String, dynamic>;
      b['exported_at'] = '2030-01-01T00:00:00.000Z';
      expect(syncFingerprint(jsonEncode(a)), syncFingerprint(jsonEncode(b)));
    });

    test('帳號內容不同 → 指紋不同', () {
      expect(
        syncFingerprint(_bundleJson(uids: ['1'])),
        isNot(syncFingerprint(_bundleJson(uids: ['2']))),
      );
    });
  });

  group('runSyncRound', () {
    test('雲端無檔 → 不合併、直接上傳本機', () async {
      final remote = _FakeRemote();
      var applied = false;
      final outcome = await runSyncRound(
        remote: remote,
        pendingRemovals: const [],
        applyRemote: (_) async => applied = true,
        exportLocal: _localJson,
        clearPendingRemovals: (_) async {},
      );
      expect(applied, isFalse);
      expect(remote.uploads, 1);
      expect(remote.content, _localJson());
      expect(outcome, isA<CloudSyncSuccess>());
      expect(
        (outcome as CloudSyncSuccess).uploadedFingerprint,
        syncFingerprint(_localJson()),
      );
    });

    test('雲端有檔 → 合併後上傳、清 pendingRemovals', () async {
      final remote = _FakeRemote(content: _bundleJson(uids: ['800000001']));
      AccountsBundle? appliedBundle;
      List<String>? cleared;
      await runSyncRound(
        remote: remote,
        pendingRemovals: const ['999'],
        applyRemote: (b) async => appliedBundle = b,
        exportLocal: _localJson,
        clearPendingRemovals: (uids) async => cleared = uids,
      );
      expect(appliedBundle, isNotNull);
      expect(appliedBundle!.accounts.single.data.uid, '800000001');
      expect(remote.uploads, 1);
      expect(cleared, ['999']);
    });

    test('pendingRemovals 剔除雲端帳號，避免剛刪的帳號復活', () async {
      final remote = _FakeRemote(
        content: _bundleJson(uids: ['800000001', '800000002']),
      );
      AccountsBundle? appliedBundle;
      await runSyncRound(
        remote: remote,
        pendingRemovals: const ['800000001'],
        applyRemote: (b) async => appliedBundle = b,
        exportLocal: _localJson,
        clearPendingRemovals: (_) async {},
      );
      expect(
        appliedBundle!.accounts.map((a) => a.data.uid),
        ['800000002'],
      );
    });

    test('剔除後帳號為空 → 跳過 applyRemote、仍上傳', () async {
      final remote = _FakeRemote(content: _bundleJson(uids: ['800000001']));
      var applied = false;
      await runSyncRound(
        remote: remote,
        pendingRemovals: const ['800000001'],
        applyRemote: (_) async => applied = true,
        exportLocal: _localJson,
        clearPendingRemovals: (_) async {},
      );
      expect(applied, isFalse);
      expect(remote.uploads, 1);
    });

    test('雲端 schema 過新 → 跳過整輪：不合併、不上傳、不清 pendingRemovals', () async {
      final remote = _FakeRemote(
        content: _bundleJson(schema: AccountsBundle.currentSchemaVersion + 1),
      );
      var applied = false;
      var cleared = false;
      final outcome = await runSyncRound(
        remote: remote,
        pendingRemovals: const ['999'],
        applyRemote: (_) async => applied = true,
        exportLocal: _localJson,
        clearPendingRemovals: (_) async => cleared = true,
      );
      expect(outcome, isA<CloudSyncSkippedSchemaTooNew>());
      expect(applied, isFalse);
      expect(remote.uploads, 0);
      expect(cleared, isFalse);
    });

    test('雲端檔損毀 → 視為無檔，上傳本機自癒', () async {
      final remote = _FakeRemote(content: 'not-json{{{');
      var applied = false;
      final outcome = await runSyncRound(
        remote: remote,
        pendingRemovals: const [],
        applyRemote: (_) async => applied = true,
        exportLocal: _localJson,
        clearPendingRemovals: (_) async {},
      );
      expect(applied, isFalse);
      expect(remote.uploads, 1);
      expect(outcome, isA<CloudSyncSuccess>());
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/services/cloud_sync/cloud_sync_service_test.dart`
Expected: 編譯失敗（檔案不存在）。

- [ ] **Step 3: 實作 cloud_sync_service.dart**

（平移自姐妹專案最終版；`_withoutUids` 以本專案的 `a.data.uid` 取代 `a.data.playerId`。）

```dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_remote.dart';

/// Logger 實例（同步編排）。
final _log = Logger('cloudsync.sync');

/// 計算 bundle JSON 的同步指紋：去除 `exported_at` 後的 SHA-256。
///
/// 用於「本機資料變動」觸發的跳過判斷——內容沒變（只有匯出時間戳會變）就不再跑一輪。
String syncFingerprint(String bundleJson) {
  final map = Map<String, dynamic>.from(
    jsonDecode(bundleJson) as Map<String, dynamic>,
  )..remove('exported_at');
  return sha256.convert(utf8.encode(jsonEncode(map))).toString();
}

/// 一輪同步的結果。
sealed class CloudSyncOutcome {
  /// 建立 [CloudSyncOutcome]。
  const CloudSyncOutcome();
}

/// 同步成功：已上傳本機資料。
class CloudSyncSuccess extends CloudSyncOutcome {
  /// 建立 [CloudSyncSuccess]。
  const CloudSyncSuccess({required this.uploadedFingerprint});

  /// 已上傳內容的 [syncFingerprint]，供後續變動觸發的跳過判斷。
  final String uploadedFingerprint;
}

/// 雲端檔 schema 比本機支援的新，整輪跳過（不合併、不上傳），提示使用者更新 App。
class CloudSyncSkippedSchemaTooNew extends CloudSyncOutcome {
  /// 建立 [CloudSyncSkippedSchemaTooNew]。
  const CloudSyncSkippedSchemaTooNew();
}

/// 執行一輪「下載 → 合併 → 上傳」同步。
///
/// - [pendingRemovals] 內的 UID 會先從下載的雲端 bundle 剔除（防止剛刪的帳號
///   被合併復活），上傳成功後經 [clearPendingRemovals] 清除。
/// - 雲端檔損毀（非 JSON／外來檔）視為不存在，直接以本機內容上傳自癒。
/// - [applyRemote] 拋出的例外（如更新進行中）原樣往外傳，由呼叫端重排。
Future<CloudSyncOutcome> runSyncRound({
  required CloudSyncRemote remote,
  required List<String> pendingRemovals,
  required Future<void> Function(AccountsBundle bundle) applyRemote,
  required String Function() exportLocal,
  required Future<void> Function(List<String> uids) clearPendingRemovals,
}) async {
  final sw = Stopwatch()..start();
  final remoteJson = await remote.download();

  if (remoteJson != null) {
    AccountsBundle? bundle;
    try {
      bundle = importAccounts(remoteJson);
    } on UnsupportedSchemaVersionException catch (e) {
      _log.warning('skip round: remote schema v${e.version} too new');
      return const CloudSyncSkippedSchemaTooNew();
    } on FormatException catch (e) {
      _log.severe('remote file corrupt (treated as absent): ${e.message}');
    } on ForeignBundleException {
      _log.severe('remote file foreign (treated as absent)');
    }
    if (bundle != null) {
      final filtered = _withoutUids(bundle, pendingRemovals.toSet());
      if (filtered.accounts.isNotEmpty) {
        await applyRemote(filtered);
      } else {
        _log.info('merge skipped: remote has no applicable accounts');
      }
    }
  }

  final localJson = exportLocal();
  await remote.upload(localJson);
  await clearPendingRemovals(pendingRemovals);
  _log.info(
    'round done in ${sw.elapsedMilliseconds}ms, '
    'remote=${remoteJson?.length ?? 0}B uploaded=${localJson.length}B '
    'pendingRemovalsCleared=${pendingRemovals.length}',
  );
  return CloudSyncSuccess(uploadedFingerprint: syncFingerprint(localJson));
}

/// 回傳剔除 [uids] 帳號後的新 bundle（其餘欄位不變）。
AccountsBundle _withoutUids(AccountsBundle bundle, Set<String> uids) {
  if (uids.isEmpty) return bundle;
  return AccountsBundle(
    exportedAt: bundle.exportedAt,
    appVersion: bundle.appVersion,
    lastActiveUid: bundle.lastActiveUid,
    accounts: bundle.accounts
        .where((a) => !uids.contains(a.data.uid))
        .toList(growable: false),
  );
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/services/cloud_sync/cloud_sync_service_test.dart`
Expected: All tests passed!

- [ ] **Step 5: 全套驗證＋commit**

```
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
git add lib/services/cloud_sync/cloud_sync_service.dart test/services/cloud_sync/cloud_sync_service_test.dart
git commit -m "feat(cloud-sync): add sync round orchestration and fingerprint"
```

---

### Task 5: GachaRepository 靜默匯入與同步後補抓入口

**Files:**
- Modify: `lib/state/gacha_repository.dart`
- Test: `test/state/gacha_repository_cloud_import_test.dart`

**Interfaces:**
- Consumes: 既有 private `_runImport(AccountsBundle)`（合併寫入＋偏好整併，不動 progress UI）、`_fetchHoYoWiki(client)`（HoYoWiki 三階段補抓）、`_isUpdating`／`_cancelTriggered`／`_activeCancellable` 互斥旗標群。
- Produces:
  - `class CloudSyncBusyException implements Exception`（定義於 `gacha_repository.dart` top-level）
  - `GachaRepository.importBundleForCloudSync(AccountsBundle bundle) → Future<ImportResult>`——不啟動 progress／不抓物品圖片；有更新或匯入進行中時拋 `CloudSyncBusyException`。
  - `GachaRepository.fetchItemImagesForCloudSync() → Future<void>`——雲端同步合併出新記錄後的補抓：走 `_fetchHoYoWiki` 進度管線，結束 emit `UpdateCompleted`（**不帶 importSummary**）；busy／bootstrap 中直接略過。

- [ ] **Step 1: 寫失敗測試**

建立 `test/state/gacha_repository_cloud_import_test.dart`（HoYoWiki mock 與 bootstrap helper 樣板抄自 `test/state/gacha_repository_import_with_hoyowiki_test.dart`）：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

/// 不會被觸發的 fake capture。
class _FakeCapture implements GachaCapture {
  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(null), cancel: () async {});
}

/// 建立模擬 HoYoWiki API 的 [MockClient]（search／entry_page／圖檔皆成功）。
http.Client _hoYoWikiMockClient() => MockClient((req) async {
  if (req.url.path.endsWith('/search')) {
    final kw = req.url.queryParameters['keyword']!;
    return http.Response(
      jsonEncode({
        'retcode': 0,
        'data': {
          'list': [
            {
              'name': kw,
              'entry_page_id': 'eid_$kw',
              'menu': {
                'sub_menus': [
                  {'id': 2},
                ],
              },
            },
          ],
        },
      }),
      200,
    );
  }
  if (req.url.path.endsWith('/entry_page')) {
    final id = req.url.queryParameters['entry_page_id']!;
    return http.Response(
      jsonEncode({
        'retcode': 0,
        'data': {
          'page': {
            'icon_url': 'https://x/${id}_icon.png',
            'header_img_url': 'https://x/${id}_header.png',
          },
        },
      }),
      200,
    );
  }
  return http.Response.bytes([1, 2, 3], 200);
});

/// 單帳號 bundle（1 筆五星祈願記錄，gacha_type=301）。
AccountsBundle _bundle(String uid) => AccountsBundle.fromJson(
  jsonDecode(
        jsonEncode({
          'schema_version': AccountsBundle.currentSchemaVersion,
          'app': accountsBundleAppId,
          'exported_at': '2026-07-06T00:00:00.000Z',
          'app_version': '1.6.0',
          'last_active_uid': uid,
          'accounts': [
            {
              'uid': uid,
              'last_updated': '2026-07-01T00:00:00.000Z',
              'banners': {
                '301': [
                  {
                    'id': '1900000000000000001',
                    'uid': uid,
                    'gacha_type': '301',
                    'name': '測試角色',
                    'item_type': '角色',
                    'rank_type': 5,
                    'time': '2026-06-30 12:00:00',
                    'lang': 'zh-tw',
                  },
                ],
              },
            },
          ],
        }),
      )
      as Map<String, dynamic>,
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_import_test_');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 建立完成 bootstrap 的 container（含 HoYoWiki 依賴覆寫）。
  Future<ProviderContainer> makeContainer() async {
    final hoyowikiDir = Directory('${tempDir.path}/hoyowiki');
    await hoyowikiDir.create();
    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        gachaCaptureProvider.overrideWithValue(_FakeCapture()),
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(hoyowikiDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(hoyowikiDir),
        hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: _hoYoWikiMockClient(),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
    return container;
  }

  test('importBundleForCloudSync 合併進本機且不啟動 progress', () async {
    final container = await makeContainer();
    final repo = container.read(gachaRepositoryProvider.notifier);

    final result = await repo.importBundleForCloudSync(_bundle('800000001'));

    expect(result.successAccounts, 1);
    expect(result.addedRecords, 1);
    final state = container.read(gachaRepositoryProvider);
    expect(state.byUid.keys, contains('800000001'));
    expect(state.progress, isNull);
  });

  test('重複匯入同 bundle → 全數 duplicate', () async {
    final container = await makeContainer();
    final repo = container.read(gachaRepositoryProvider.notifier);

    await repo.importBundleForCloudSync(_bundle('800000001'));
    final second = await repo.importBundleForCloudSync(_bundle('800000001'));

    expect(second.addedRecords, 0);
    expect(second.duplicateRecords, 1);
  });

  test('progress 進行中 → importBundleForCloudSync 拋 CloudSyncBusyException', () async {
    final container = await makeContainer();
    final repo = container.read(gachaRepositoryProvider.notifier);
    repo.debugSetProgress(const Preparing());

    expect(
      () => repo.importBundleForCloudSync(_bundle('800000001')),
      throwsA(isA<CloudSyncBusyException>()),
    );
  });

  test('fetchItemImagesForCloudSync → 補抓並 emit UpdateCompleted 不帶 importSummary', () async {
    final container = await makeContainer();
    final repo = container.read(gachaRepositoryProvider.notifier);
    await repo.importBundleForCloudSync(_bundle('800000001'));

    await repo.fetchItemImagesForCloudSync();

    final progress = container.read(gachaRepositoryProvider).progress;
    expect(progress, isA<UpdateCompleted>());
    final completed = progress as UpdateCompleted;
    expect(completed.importSummary, isNull);
    expect(completed.totalNewRecords, 0);
    expect(completed.hoYoWikiImagesDownloaded, greaterThan(0));
  });

  test('fetchItemImagesForCloudSync：progress 進行中 → 直接略過', () async {
    final container = await makeContainer();
    final repo = container.read(gachaRepositoryProvider.notifier);
    repo.debugSetProgress(const Preparing());

    await repo.fetchItemImagesForCloudSync();

    expect(
      container.read(gachaRepositoryProvider).progress,
      isA<Preparing>(),
    );
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/state/gacha_repository_cloud_import_test.dart`
Expected: 編譯失敗（`importBundleForCloudSync` 不存在）。

- [ ] **Step 3: 實作**

`lib/state/gacha_repository.dart`：

1. 在 `_NoRecordsException` 附近（top-level）加：

```dart
/// 雲端同步請求匯入時，已有更新或匯入進行中而無法執行時拋出；呼叫端應稍後重試。
class CloudSyncBusyException implements Exception {
  /// 建立 [CloudSyncBusyException]。
  const CloudSyncBusyException();

  @override
  String toString() => 'CloudSyncBusyException';
}
```

2. `GachaRepository` 內加 logger（放 `_refreshMetaLog` 後）：

```dart
  /// Logger 實例（雲端同步觸發的匯入與補抓）。
  static final _cloudSyncLog = Logger('cloudsync.sync');
```

3. 在 `importAccountsAndFetchHoYoWiki` 方法後加兩個方法：

```dart
  /// 雲端同步專用的靜默匯入：純資料合併（寫入 storage＋整併偏好），
  /// 不啟動 progress UI、不抓物品圖片。
  ///
  /// 已有更新或匯入進行中時拋 [CloudSyncBusyException]，由雲端同步層重排。
  Future<ImportResult> importBundleForCloudSync(AccountsBundle bundle) async {
    if (state.progress != null || _isUpdating) {
      _cloudSyncLog.info('cloud import rejected: busy');
      throw const CloudSyncBusyException();
    }
    _isUpdating = true;
    try {
      _cloudSyncLog.info(
        'cloud import start, accounts=${bundle.accounts.length}',
      );
      return await _runImport(bundle);
    } finally {
      _isUpdating = false;
    }
  }

  /// 雲端同步合併出新記錄後的補抓：走與「更新物品資料」相同的
  /// [_fetchHoYoWiki] 進度管線，結束 emit [UpdateCompleted]（不帶
  /// importSummary，避免顯示成手動匯入的結果文案）。
  ///
  /// best-effort：更新／匯入進行中或 bootstrap 未完成時直接略過，缺圖留待
  /// 下次手動「更新」補齊；單筆失敗僅記 log、照常收尾；進度框可取消。
  Future<void> fetchItemImagesForCloudSync() async {
    if (state.progress != null) {
      _cloudSyncLog.info('post-sync item fetch skipped: progress in-flight');
      return;
    }
    if (_isUpdating || state.isBootstrapping) {
      _cloudSyncLog.info('post-sync item fetch skipped: busy or bootstrapping');
      return;
    }
    _isUpdating = true;
    _cancelTriggered = false;
    _cloudSyncLog.info('post-sync item fetch start');

    final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
    _activeCancellable = cancellable;
    state = state.copyWith(progress: const Preparing());

    try {
      var images = 0;
      try {
        final result = await _fetchHoYoWiki(cancellable.client);
        images = result.imagesDownloaded;
      } catch (e, st) {
        _cloudSyncLog.warning('post-sync hoyowiki stage threw (ignored)', e, st);
      }
      if (!ref.mounted) return;

      if (_cancelTriggered) {
        _cloudSyncLog.info('post-sync item fetch cancelled');
        state = state.copyWith(clearProgress: true);
        return;
      }
      _cloudSyncLog.info('post-sync item fetch done, images=$images');
      state = state.copyWith(
        progress: UpdateCompleted(
          totalNewRecords: 0,
          failedBanners: const [],
          updatedAt: DateTime.now().toUtc(),
          hoYoWikiImagesDownloaded: images,
        ),
      );
    } finally {
      _activeCancellable?.client.close();
      _activeCancellable = null;
      _cancelTriggered = false;
      _isUpdating = false;
    }
  }
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/state/gacha_repository_cloud_import_test.dart`
Expected: All tests passed!（若 `_bundle` 內 record JSON 欄位與 `GachaRecord.fromStorageJson` 實際 schema 不符導致解析失敗，打開 `lib/models/gacha_record.dart` 對齊欄位名，只改測試 fixture。）

- [ ] **Step 5: 全套驗證＋commit**

```
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
git add lib/state/gacha_repository.dart test/state/gacha_repository_cloud_import_test.dart
git commit -m "feat(cloud-sync): add silent import and post-sync item fetch to GachaRepository"
```

---

### Task 6: CloudSyncNotifier 狀態機

**Files:**
- Create: `lib/state/cloud_sync.dart`
- Create: `test/helpers/cloud_sync_fakes.dart`
- Test: `test/state/cloud_sync_test.dart`

**Interfaces:**
- Consumes: Task 1–5 全部產出＋`exportAccounts`（`lib/services/accounts_export.dart`）／`appVersionProvider`（`lib/app_info.dart`）／`settingsProvider`／`gachaRepositoryProvider`。
- Produces:
  - `enum CloudSyncPhase { idle, awaitingConsent, syncing, error, reauthRequired }`
  - `class CloudSyncState { final CloudSyncPhase phase; final String? errorToken; }`（errorToken ∈ `'network'`｜`'busy'`｜`'schemaTooNew'`｜`'authFailed'`｜`'scopeMissing'`）
  - `final cloudSyncProvider = NotifierProvider<CloudSyncNotifier, CloudSyncState>(...)`
  - `CloudSyncNotifier` 方法：`start()`、`link({String? postAuthPage})`、`cancelLink()`、`unlink()`、`setAutoSync(bool value)`、`syncNow({required bool manual, String trigger})`、`queueCloudRemoval(String uid)`
  - Providers：`tokenStoreProvider`、`googleAuthServiceProvider`、`cloudSyncRemoteFactoryProvider`（`CloudSyncRemote Function(http.Client)`）、`cloudSyncUrlOpenerProvider`（`void Function(String url)`）、`windowForegroundProvider`（`Future<void> Function()`）
  - 共用測試 fakes：`InMemoryTokenStore`、`FakeAuthService`、`FakeRemote`、`FakeCapture`（`test/helpers/cloud_sync_fakes.dart`）
  - UI 的「是否已連結／email／開關／上次同步時間」一律直接 watch `settingsProvider`，不在 CloudSyncState 重複持有。

- [ ] **Step 1: 建立共用測試 fakes**

建立 `test/helpers/cloud_sync_fakes.dart`：

```dart
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_remote.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/google_auth_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/token_store.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';

/// 測試用 in-memory token store。
class InMemoryTokenStore implements TokenStore {
  /// 目前存放的 token。
  String? token;

  /// 讀取目前存放的 token。
  @override
  Future<String?> readRefreshToken() async => token;

  /// 寫入 token。
  @override
  Future<void> writeRefreshToken(String t) async => token = t;

  /// 清除 token。
  @override
  Future<void> deleteRefreshToken() async => token = null;
}

/// 不發真請求的 fake AuthClient。
class FakeAuthClient extends http.BaseClient implements AuthClient {
  /// 憑證（測試不使用）。
  @override
  AccessCredentials get credentials => throw UnimplementedError();

  /// 發送請求（測試不使用）。
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();
}

/// 可程式化行為的 fake 授權服務。
class FakeAuthService extends GoogleAuthService {
  /// 建立 [FakeAuthService]。
  FakeAuthService(this.store)
    : super(tokenStore: store, baseClientFactory: http.Client.new);

  /// 供斷言的 token store。
  final InMemoryTokenStore store;

  /// restore 是否要拋 invalid_grant（reauth）。
  bool restoreThrowsReauth = false;

  /// 模擬登入：呼叫 openUrl 後直接回傳成功 session（refresh token 交由呼叫端寫入）。
  @override
  Future<CloudAuthSession> signIn(
    void Function(String url) openUrl, {
    String? postAuthPage,
  }) async {
    openUrl('https://accounts.google.com/consent');
    return CloudAuthSession(
      client: FakeAuthClient(),
      email: 'u@example.com',
      refreshToken: 'refresh-1',
    );
  }

  /// 模擬還原：依 [restoreThrowsReauth] 與 store 內容回傳。
  @override
  Future<AuthClient?> restore() async {
    if (restoreThrowsReauth) throw const CloudReauthRequiredException();
    if (store.token == null) return null;
    return FakeAuthClient();
  }

  /// 模擬登出：清除 store 內 token。
  @override
  Future<void> signOut() async => store.deleteRefreshToken();

  /// 模擬 revoke：no-op。
  @override
  Future<void> revokeToken(String refreshToken) async {}
}

/// 記錄呼叫的 fake 遠端。
class FakeRemote implements CloudSyncRemote {
  /// 雲端檔內容；null = 不存在。
  String? content;

  /// upload 次數。
  int uploads = 0;

  /// 回傳目前雲端檔內容。
  @override
  Future<String?> download() async => content;

  /// 記錄上傳並更新內容。
  @override
  Future<void> upload(String json) async {
    uploads++;
    content = json;
  }
}

/// 不會被觸發的 fake capture。
class FakeCapture implements GachaCapture {
  /// 回傳永遠無結果的 capture session。
  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(null), cancel: () async {});
}
```

- [ ] **Step 2: 寫失敗測試**

建立 `test/state/cloud_sync_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

import '../helpers/cloud_sync_fakes.dart';

/// 產生雲端側 bundle JSON；[withRecord] 為 true 時帶一筆 301 五星記錄。
String _cloudBundleJson(String uid, {bool withRecord = false}) => jsonEncode({
  'schema_version': AccountsBundle.currentSchemaVersion,
  'app': accountsBundleAppId,
  'exported_at': '2026-07-06T00:00:00.000Z',
  'app_version': '1.6.0',
  'last_active_uid': uid,
  'accounts': [
    {
      'uid': uid,
      'last_updated': '2026-07-01T00:00:00.000Z',
      'banners': {
        '301': withRecord
            ? [
                {
                  'id': '1900000000000000001',
                  'uid': uid,
                  'gacha_type': '301',
                  'name': '測試角色',
                  'item_type': '角色',
                  'rank_type': 5,
                  'time': '2026-06-30 12:00:00',
                  'lang': 'zh-tw',
                },
              ]
            : <Object>[],
      },
    },
  ],
});

void main() {
  late Directory tempDir;
  late InMemoryTokenStore tokenStore;
  late FakeAuthService authService;
  late FakeRemote remote;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_sync_test_');
    SharedPreferences.setMockInitialValues({});
    tokenStore = InMemoryTokenStore();
    authService = FakeAuthService(tokenStore);
    remote = FakeRemote();
    debugCloudSyncConfiguredOverride = true;
  });

  tearDown(() async {
    debugCloudSyncConfiguredOverride = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 建立完成載入的 container（HoYoWiki API 一律回 500，補抓 best-effort 空跑）。
  Future<ProviderContainer> makeContainer() async {
    final hoyowikiDir = Directory('${tempDir.path}/hoyowiki');
    await hoyowikiDir.create();
    final container = ProviderContainer(
      overrides: [
        appVersionProvider.overrideWithValue('1.6.0'),
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        gachaCaptureProvider.overrideWithValue(FakeCapture()),
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(hoyowikiDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(hoyowikiDir),
        hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('', 500)),
            cancel: () {},
          ),
        ),
        tokenStoreProvider.overrideWithValue(tokenStore),
        googleAuthServiceProvider.overrideWithValue(authService),
        cloudSyncRemoteFactoryProvider.overrideWithValue((_) => remote),
        cloudSyncUrlOpenerProvider.overrideWithValue((_) {}),
        windowForegroundProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    return container;
  }

  test('link 成功 → 寫 email、存 token、跑第一輪同步', () async {
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).link();

    expect(
      container.read(settingsProvider).cloudAccountEmail,
      'u@example.com',
    );
    expect(tokenStore.token, 'refresh-1');
    expect(remote.uploads, 1);
    expect(container.read(settingsProvider).cloudLastSyncedAt, isNotNull);
    expect(container.read(cloudSyncProvider).phase, CloudSyncPhase.idle);
  });

  test('syncNow 把雲端帳號合併進本機並上傳', () async {
    remote.content = _cloudBundleJson('800000001');
    final container = await makeContainer();
    await container.read(cloudSyncProvider.notifier).link();

    expect(
      container.read(gachaRepositoryProvider).byUid.keys,
      contains('800000001'),
    );
    final uploaded = jsonDecode(remote.content!) as Map<String, dynamic>;
    final uids = (uploaded['accounts'] as List)
        .map((a) => (a as Map<String, dynamic>)['uid'])
        .toList();
    expect(uids, contains('800000001'));
  });

  test('雲端 schema 過新 → error(schemaTooNew)、不上傳', () async {
    final map =
        jsonDecode(_cloudBundleJson('800000001')) as Map<String, dynamic>;
    map['schema_version'] = AccountsBundle.currentSchemaVersion + 1;
    remote.content = jsonEncode(map);
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).link();

    final s = container.read(cloudSyncProvider);
    expect(s.phase, CloudSyncPhase.error);
    expect(s.errorToken, 'schemaTooNew');
    expect(remote.uploads, 0);
  });

  test('start：token 失效 → reauthRequired、不跑同步', () async {
    SharedPreferences.setMockInitialValues({
      'pref.cloudAccountEmail': 'u@example.com',
    });
    authService.restoreThrowsReauth = true;
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).start();

    expect(
      container.read(cloudSyncProvider).phase,
      CloudSyncPhase.reauthRequired,
    );
    expect(remote.uploads, 0);
  });

  test('unlink → 清 email、刪 token、雲端檔保留', () async {
    remote.content = _cloudBundleJson('800000001');
    final container = await makeContainer();
    await container.read(cloudSyncProvider.notifier).link();

    await container.read(cloudSyncProvider.notifier).unlink();

    expect(container.read(settingsProvider).cloudAccountEmail, isNull);
    expect(tokenStore.token, isNull);
    expect(remote.content, isNotNull);
  });

  test('queueCloudRemoval → 上傳內容剔除該 UID、清 pendingRemovals', () async {
    remote.content = _cloudBundleJson('800000001');
    final container = await makeContainer();
    await container.read(cloudSyncProvider.notifier).link();
    // 模擬本機已刪：直接從 repo 移除
    await container
        .read(gachaRepositoryProvider.notifier)
        .removeUid('800000001');

    await container
        .read(cloudSyncProvider.notifier)
        .queueCloudRemoval('800000001');

    final uploaded = jsonDecode(remote.content!) as Map<String, dynamic>;
    final uids = (uploaded['accounts'] as List)
        .map((a) => (a as Map<String, dynamic>)['uid'])
        .toList();
    expect(uids, isNot(contains('800000001')));
    expect(container.read(settingsProvider).cloudPendingRemovals, isEmpty);
  });

  test('合併出新記錄 → 觸發補抓並 emit UpdateCompleted 不帶 importSummary', () async {
    remote.content = _cloudBundleJson('800000001', withRecord: true);
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).link();
    // fetchItemImagesForCloudSync 為 fire-and-forget，等它跑完
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final progress = container.read(gachaRepositoryProvider).progress;
    expect(progress, isA<UpdateCompleted>());
    expect((progress as UpdateCompleted).importSummary, isNull);
  });

  test('無新增記錄的同步輪 → 不觸發補抓', () async {
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).link();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(container.read(gachaRepositoryProvider).progress, isNull);
  });
}
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `fvm flutter test test/state/cloud_sync_test.dart`
Expected: 編譯失敗（`lib/state/cloud_sync.dart` 不存在）。

- [ ] **Step 4: 實作 lib/state/cloud_sync.dart**

（平移自姐妹專案最終版，換 package import；`fetchItemImagesForCloudSync` 觸發即姐妹 PR #47 行為。）

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_export.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_remote.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/google_auth_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/token_store.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

/// 雲端同步的即時狀態。
enum CloudSyncPhase {
  /// 閒置（未連結時也是此狀態，連結與否由 settings 的 email 判斷）。
  idle,

  /// 等待使用者在瀏覽器完成授權。
  awaitingConsent,

  /// 同步進行中。
  syncing,

  /// 最近一輪同步失敗（原因見 [CloudSyncState.errorToken]）。
  error,

  /// refresh token 已失效，需要重新連結。
  reauthRequired,
}

/// [CloudSyncNotifier] 的狀態快照。
@immutable
class CloudSyncState {
  /// 建立 [CloudSyncState]。
  const CloudSyncState({this.phase = CloudSyncPhase.idle, this.errorToken});

  /// 目前階段。
  final CloudSyncPhase phase;

  /// phase == error 時的原因 token
  /// （'network'｜'busy'｜'schemaTooNew'｜'authFailed'｜'scopeMissing'），
  /// UI 端解 i18n。
  final String? errorToken;
}

/// [TokenStore] provider，預設 DPAPI 安全儲存。
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// [GoogleAuthService] provider。
final googleAuthServiceProvider = Provider<GoogleAuthService>(
  (ref) => GoogleAuthService(
    tokenStore: ref.watch(tokenStoreProvider),
    baseClientFactory: http.Client.new,
  ),
);

/// 以授權 client 建立 [CloudSyncRemote] 的工廠 provider。
final cloudSyncRemoteFactoryProvider =
    Provider<CloudSyncRemote Function(http.Client)>(
      (ref) => DriveSyncRemote.new,
    );

/// 開啟授權頁 URL 的 provider（測試 override 成 no-op）。
final cloudSyncUrlOpenerProvider = Provider<void Function(String url)>(
  (ref) =>
      (url) => unawaited(launchUrl(Uri.parse(url))),
);

/// 把主視窗帶回前景（還原最小化＋show＋focus）的 provider（測試 override 成 no-op）。
///
/// Windows 防搶焦點政策可能把 focus 降級成工作列閃爍，屬預期行為。
/// 呼叫端 fire-and-forget，失敗只記 log，不讓例外流進 unhandled zone。
final windowForegroundProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      Logger('cloudsync.sync').warning('bring-to-foreground failed: $e');
    }
  },
);

/// [CloudSyncNotifier] 的 Riverpod provider。
final cloudSyncProvider = NotifierProvider<CloudSyncNotifier, CloudSyncState>(
  CloudSyncNotifier.new,
);

/// 雲端同步狀態管理：連結／登出、四個觸發入口、5 秒 debounce 與單飛鎖。
class CloudSyncNotifier extends Notifier<CloudSyncState> {
  /// Logger 實例（同步流程）。
  static final _log = Logger('cloudsync.sync');

  /// 目前的授權 client；null = 尚未還原或未連結。
  AuthClient? _client;

  /// 資料變動觸發的 debounce timer。
  Timer? _debounce;

  /// 單飛鎖：一輪同步進行中。
  bool _syncing = false;

  /// 進行中又被觸發 → 結束後補跑一輪。
  bool _pendingRerun = false;

  /// 上次上傳內容的指紋，供資料變動觸發的跳過判斷。
  String? _lastFingerprint;

  /// 授權流程世代號；cancelLink／unlink 時遞增以拋棄過期的授權結果。
  int _authGeneration = 0;

  @override
  CloudSyncState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _client?.close();
    });
    ref.listen(
      gachaRepositoryProvider.select((s) => s.byUid),
      (_, _) => _onLocalChange(),
    );
    ref.listen(
      settingsProvider.select((s) => s.uidAliases),
      (_, _) => _onLocalChange(),
    );
    return const CloudSyncState();
  }

  /// 是否已連結雲端帳號。
  bool get _linked => ref.read(settingsProvider).cloudAccountEmail != null;

  /// App 啟動入口：已連結則還原授權，開關開啟時靜默跑一輪。
  Future<void> start() async {
    if (!isCloudSyncConfigured) return;
    await ref.read(settingsProvider.notifier).waitForLoad();
    if (!ref.mounted || !_linked) return;
    // 沒等本機 bootstrap 完成就同步，byUid 會是空的，雲端內容會把本機檔案當「全新」覆蓋掉。
    await ref.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    if (!ref.mounted) return;
    try {
      await _ensureClient();
    } on CloudReauthRequiredException {
      state = const CloudSyncState(phase: CloudSyncPhase.reauthRequired);
      return;
    } catch (e) {
      _log.warning('startup restore failed: $e');
      state = const CloudSyncState(
        phase: CloudSyncPhase.error,
        errorToken: 'network',
      );
      return;
    }
    if (!ref.mounted) return;
    if (ref.read(settingsProvider).cloudAutoSyncEnabled) {
      await syncNow(manual: false, trigger: 'startup');
    }
  }

  /// 連結 Google 帳號：開瀏覽器授權，成功後存 email 並立即同步一輪。
  ///
  /// [postAuthPage] 為授權成功後瀏覽器顯示的自訂 HTML，由 UI 端以當前
  /// 語言產生（notifier 拿不到 AppLocalizations）。
  Future<void> link({String? postAuthPage}) async {
    if (!isCloudSyncConfigured) return;
    if (state.phase == CloudSyncPhase.awaitingConsent) return;
    final gen = ++_authGeneration;
    state = const CloudSyncState(phase: CloudSyncPhase.awaitingConsent);
    final auth = ref.read(googleAuthServiceProvider);
    final openUrl = ref.read(cloudSyncUrlOpenerProvider);
    try {
      final session = await auth.signIn(openUrl, postAuthPage: postAuthPage);
      if (!ref.mounted || gen != _authGeneration) {
        // 取消後在瀏覽器遲到完成的授權：拋棄 client、revoke 該次 grant，不寫入 token store。
        session.client.close();
        unawaited(auth.revokeToken(session.refreshToken));
        return;
      }
      await ref
          .read(tokenStoreProvider)
          .writeRefreshToken(session.refreshToken);
      _client?.close();
      _client = session.client;
      await ref.read(settingsProvider.notifier).setCloudAccount(session.email);
      if (!ref.mounted) return;
      state = const CloudSyncState();
      await syncNow(manual: true, trigger: 'link');
    } on CloudScopeMissingException {
      if (!ref.mounted || gen != _authGeneration) return;
      _log.warning('link failed: required Drive scope not granted');
      state = const CloudSyncState(
        phase: CloudSyncPhase.error,
        errorToken: 'scopeMissing',
      );
    } catch (e) {
      if (!ref.mounted || gen != _authGeneration) return;
      _log.warning('link failed: $e');
      state = const CloudSyncState(
        phase: CloudSyncPhase.error,
        errorToken: 'authFailed',
      );
    }
  }

  /// 取消進行中的授權等待（拋棄結果，回到閒置）。
  void cancelLink() {
    if (state.phase != CloudSyncPhase.awaitingConsent) return;
    _authGeneration++;
    state = const CloudSyncState();
    _log.info('link cancelled');
  }

  /// 中斷連結：revoke＋刪 token＋清 settings；本機與雲端資料皆保留。
  Future<void> unlink() async {
    _authGeneration++;
    _debounce?.cancel();
    await ref.read(googleAuthServiceProvider).signOut();
    if (!ref.mounted) return;
    _client?.close();
    _client = null;
    _lastFingerprint = null;
    await ref.read(settingsProvider.notifier).clearCloudAccount();
    if (!ref.mounted) return;
    state = const CloudSyncState();
  }

  /// 切換自動同步；開啟時立即補跑一輪。
  Future<void> setAutoSync(bool value) async {
    await ref.read(settingsProvider.notifier).setCloudAutoSyncEnabled(value);
    if (!ref.mounted) return;
    if (value && _linked) await syncNow(manual: false, trigger: 'autoSyncOn');
  }

  /// 把 [uid] 排入待雲端移除清單並立即同步（離線時清單留待下輪補刪）。
  Future<void> queueCloudRemoval(String uid) async {
    await ref.read(settingsProvider.notifier).addCloudPendingRemoval(uid);
    if (!ref.mounted) return;
    _debounce?.cancel();
    await syncNow(manual: false, trigger: 'removal');
  }

  /// 跑一輪同步。[manual] 僅影響 log 標記；[trigger] 為觸發來源標籤
  /// （startup／dataChange／removal／link／manual...，spec §10），
  /// 錯誤一律以狀態列呈現（spec §9）。
  ///
  /// reauthRequired 時直接返回：restore 保證失敗，重試只會空轉並讓狀態列閃爍，
  /// 只有重新連結（[link]）能離開此狀態。
  Future<void> syncNow({
    required bool manual,
    String trigger = 'manual',
  }) async {
    if (!isCloudSyncConfigured || !_linked) return;
    if (state.phase == CloudSyncPhase.reauthRequired) return;
    if (_syncing) {
      _pendingRerun = true;
      return;
    }
    _syncing = true;
    state = const CloudSyncState(phase: CloudSyncPhase.syncing);
    _log.info('sync round start trigger=$trigger manual=$manual');
    ImportResult? mergeResult;
    try {
      await _ensureClient();
      final settings = ref.read(settingsProvider);
      final pending = settings.cloudPendingRemovals;
      final outcome = await runSyncRound(
        remote: ref.read(cloudSyncRemoteFactoryProvider)(_client!),
        pendingRemovals: pending,
        applyRemote: (bundle) async {
          mergeResult = await ref
              .read(gachaRepositoryProvider.notifier)
              .importBundleForCloudSync(bundle);
        },
        exportLocal: _exportLocal,
        clearPendingRemovals: (uids) => ref
            .read(settingsProvider.notifier)
            .removeCloudPendingRemovals(uids),
      );
      if (!ref.mounted) return;
      switch (outcome) {
        case CloudSyncSuccess(:final uploadedFingerprint):
          _lastFingerprint = uploadedFingerprint;
          await ref
              .read(settingsProvider.notifier)
              .setCloudLastSyncedAt(DateTime.now().toUtc());
          if (!ref.mounted) return;
          state = const CloudSyncState();
          if ((mergeResult?.addedRecords ?? 0) > 0) {
            // 雲端合併出新記錄（如第二台電腦首次同步）→ 補抓缺漏的物品
            // 圖示與詳情，走進度對話框讓使用者看到狀態，結束顯示補圖摘要。
            unawaited(
              ref
                  .read(gachaRepositoryProvider.notifier)
                  .fetchItemImagesForCloudSync(),
            );
          }
        case CloudSyncSkippedSchemaTooNew():
          state = const CloudSyncState(
            phase: CloudSyncPhase.error,
            errorToken: 'schemaTooNew',
          );
      }
    } on CloudReauthRequiredException {
      if (!ref.mounted) return;
      state = const CloudSyncState(phase: CloudSyncPhase.reauthRequired);
    } on CloudSyncBusyException {
      if (!ref.mounted) return;
      _log.info('sync deferred: repository busy');
      state = const CloudSyncState(
        phase: CloudSyncPhase.error,
        errorToken: 'busy',
      );
      _scheduleDebounced();
    } catch (e, st) {
      if (!ref.mounted) return;
      if (isInsufficientScope(e)) {
        // 既存 token 缺 Drive 權限（早期授權漏勾）：重試必敗，比照授權失效
        // 進 reauthRequired 停止自動同步，狀態列指引使用者重新連結並勾選。
        _log.warning('sync round failed: insufficient scope, relink required');
        state = const CloudSyncState(
          phase: CloudSyncPhase.reauthRequired,
          errorToken: 'scopeMissing',
        );
        return;
      }
      _log.warning('sync round failed', e, st);
      state = const CloudSyncState(
        phase: CloudSyncPhase.error,
        errorToken: 'network',
      );
    } finally {
      _syncing = false;
      if (_pendingRerun && ref.mounted) {
        _pendingRerun = false;
        unawaited(syncNow(manual: false, trigger: 'rerun'));
      }
    }
  }

  /// 還原授權 client（已有就直接用）；無 token 視同需要重新連結。
  Future<void> _ensureClient() async {
    if (_client != null) return;
    final restored = await ref.read(googleAuthServiceProvider).restore();
    if (restored == null) throw const CloudReauthRequiredException();
    _client = restored;
  }

  /// 本機資料（byUid／別名）變動時排程 debounce 同步。
  ///
  /// reauthRequired 時不排程：只有重新連結（[link]）能離開此狀態。
  void _onLocalChange() {
    if (!isCloudSyncConfigured || !_linked) return;
    if (state.phase == CloudSyncPhase.reauthRequired) return;
    if (!ref.read(settingsProvider).cloudAutoSyncEnabled) return;
    if (ref.read(gachaRepositoryProvider).isBootstrapping) return;
    _scheduleDebounced();
  }

  /// 5 秒後跑一輪；到點時指紋沒變就跳過（避免同步自身的合併寫入造成空轉輪）。
  void _scheduleDebounced() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), () {
      if (!ref.mounted || !_linked) return;
      if (syncFingerprint(_exportLocal()) == _lastFingerprint) return;
      unawaited(syncNow(manual: false, trigger: 'dataChange'));
    });
  }

  /// 把本機全帳號打包成與手動匯出同格式的 bundle JSON。
  String _exportLocal() {
    final gacha = ref.read(gachaRepositoryProvider);
    final settings = ref.read(settingsProvider);
    return exportAccounts(
      byUid: gacha.byUid,
      uidOrder: settings.uidOrder,
      uidAliases: settings.uidAliases,
      lastActiveUid: gacha.activeUid,
      appVersion: ref.read(appVersionProvider),
      now: DateTime.now(),
    );
  }
}
```

- [ ] **Step 5: 跑測試確認通過**

Run: `fvm flutter test test/state/cloud_sync_test.dart`
Expected: All tests passed!（Riverpod `ref.listen` callback 的 `(_, _)` 萬用字元寫法需 Dart 3.7+ wildcard 支援；若 analyzer 報錯改成 `(_, __)`。）

- [ ] **Step 6: 全套驗證＋commit**

```
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
git add lib/state/cloud_sync.dart test/helpers/cloud_sync_fakes.dart test/state/cloud_sync_test.dart
git commit -m "feat(cloud-sync): add CloudSyncNotifier state machine with debounced triggers"
```

---

### Task 7: 設定頁「雲端同步」區塊與 ARB 字串（九語）

**Files:**
- Create: `lib/widgets/cards/cloud_sync_section.dart`
- Modify: `lib/pages/settings_page.dart`
- Modify: `lib/l10n/app_zh.arb`、`app_zh_Hans.arb`、`app_en.arb`、`app_ja.arb`、`app_es.arb`、`app_fr.arb`、`app_pt_BR.arb`、`app_th.arb`、`app_vi.arb`
- Test: `test/widgets/cloud_sync_section_test.dart`

**Interfaces:**
- Consumes: `cloudSyncProvider`／`CloudSyncPhase`／`windowForegroundProvider`（Task 6）、`settingsProvider` cloud 欄位（Task 1）、`isCloudSyncConfigured`、`RelativeTimeText`、`showConfirmDialog`、`SectionCard`、fakes（Task 6）。
- Produces: `class CloudSyncSection extends ConsumerWidget`（公開，供 settings page 與 widget test 使用）。

- [ ] **Step 1: 加 ARB 字串（先加 template，widget 才能編譯）**

`lib/l10n/app_zh.arb`（template；插在 `"settingsDataManagement"` 群組附近，帶 placeholder 的 key 要加 `@` metadata，格式照檔內既有 `@footerLastUpdated` 樣式）：

```json
"settingsCloudSync": "雲端同步",
"cloudSyncIntro": "連結 Google 帳號後，卡池記錄會自動備份到你的 Google 雲端硬碟，並在多台電腦間同步。",
"cloudSyncUnconfigured": "此建置未設定 Google OAuth 憑證，雲端同步無法使用。",
"cloudSyncLink": "連結 Google 帳號",
"cloudSyncAwaitingConsent": "已開啟瀏覽器，請在瀏覽器完成授權...",
"cloudSyncLinkedAs": "已連結：{email}",
"@cloudSyncLinkedAs": {"placeholders": {"email": {"type": "String"}}},
"cloudSyncAutoToggle": "自動同步",
"cloudSyncAutoToggleHint": "App 啟動與資料變動後自動同步；關閉後仍可手動同步。",
"cloudSyncNow": "立即同步",
"cloudSyncUnlink": "中斷連結",
"cloudSyncUnlinkConfirmTitle": "中斷連結",
"cloudSyncUnlinkConfirmBody": "中斷後將停止同步。本機資料與雲端已備份的資料都會保留。",
"cloudSyncLastSynced": "上次同步：{time}",
"@cloudSyncLastSynced": {"placeholders": {"time": {"type": "String"}}},
"cloudSyncNeverSynced": "尚未同步",
"cloudSyncErrorNetwork": "同步失敗：網路連線問題，稍後會自動重試。",
"cloudSyncErrorBusy": "同步暫緩：目前有更新或匯入進行中，稍後會自動重試。",
"cloudSyncErrorSchemaTooNew": "同步已跳過：雲端資料由較新版本的 App 建立，請先更新 App。",
"cloudSyncErrorAuthFailed": "授權失敗，請再試一次。",
"cloudSyncErrorScopeMissing": "未取得 Google 雲端硬碟權限，請重新連結並在授權頁勾選雲端硬碟的存取權限。",
"cloudSyncReauthRequired": "授權已失效，請重新連結 Google 帳號。",
"cloudSyncRemoveFromCloud": "同時從雲端同步資料移除此帳號",
"cloudSyncPostAuthTitle": "授權完成",
"cloudSyncPostAuthBody": "你可以關閉此頁面，回到 App 繼續操作。",
"cloudSyncPostAuthScopeMissingTitle": "缺少雲端硬碟權限",
"cloudSyncPostAuthScopeMissingBody": "這次授權未包含 Google 雲端硬碟的存取權限。請回到 App 重新連結，並在授權頁勾選雲端硬碟權限。"
```

然後：`fvm flutter gen-l10n`
Expected: 無錯誤（其他語系會以 template fallback，先不擋編譯）。

- [ ] **Step 2: 寫失敗 widget 測試**

建立 `test/widgets/cloud_sync_section_test.dart`（fakes 來自 Task 6 的 `test/helpers/cloud_sync_fakes.dart`）：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/cloud_sync_section.dart';

import '../helpers/cloud_sync_fakes.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_section_test_');
    SharedPreferences.setMockInitialValues({});
    debugCloudSyncConfiguredOverride = true;
  });

  tearDown(() async {
    debugCloudSyncConfiguredOverride = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 包裝待測 widget 與全部 provider 覆寫。
  Widget wrap(Directory hoyowikiDir) => ProviderScope(
    overrides: [
      appVersionProvider.overrideWithValue('1.6.0'),
      gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
      gachaCaptureProvider.overrideWithValue(FakeCapture()),
      hoyowikiIndexStorageProvider.overrideWithValue(
        HoYoWikiIndexStorage(hoyowikiDir),
      ),
      hoyowikiCacheDirProvider.overrideWithValue(hoyowikiDir),
      hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
      cancellableHttpClientFactoryProvider.overrideWithValue(
        () => CancellableHttpClient(
          client: MockClient((_) async => http.Response('', 500)),
          cancel: () {},
        ),
      ),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      cloudSyncRemoteFactoryProvider.overrideWithValue((_) => FakeRemote()),
      cloudSyncUrlOpenerProvider.overrideWithValue((_) {}),
      windowForegroundProvider.overrideWithValue(() async {}),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('en'),
      home: Scaffold(body: SingleChildScrollView(child: CloudSyncSection())),
    ),
  );

  /// 建立 hoyowiki 暫存目錄。
  Future<Directory> makeHoyowikiDir() async {
    final dir = Directory('${tempDir.path}/hoyowiki');
    await dir.create();
    return dir;
  }

  testWidgets('未連結：顯示說明與連結按鈕', (tester) async {
    await tester.pumpWidget(wrap(await makeHoyowikiDir()));
    await tester.pumpAndSettle();

    expect(find.text('Link Google account'), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
  });

  testWidgets('已連結：顯示 email、開關、立即同步與中斷連結', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pref.cloudAccountEmail': 'u@example.com',
    });
    await tester.pumpWidget(wrap(await makeHoyowikiDir()));
    await tester.pumpAndSettle();

    expect(find.textContaining('u@example.com'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Unlink'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('未設定憑證：只顯示未設定說明', (tester) async {
    debugCloudSyncConfiguredOverride = false;
    await tester.pumpWidget(wrap(await makeHoyowikiDir()));
    await tester.pumpAndSettle();

    expect(find.text('Link Google account'), findsNothing);
    expect(
      find.textContaining('cloud sync is unavailable'),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/cloud_sync_section_test.dart`
Expected: 編譯失敗（`CloudSyncSection` 不存在）。

- [ ] **Step 4: 實作 CloudSyncSection**

建立 `lib/widgets/cards/cloud_sync_section.dart`（平移自姐妹專案最終版，換 package import 與 App 名稱語意）：

```dart
import 'dart:async' show unawaited;
import 'dart:convert' show HtmlEscape;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/relative_time_text.dart';

/// 產生授權成功後瀏覽器顯示的完成頁 HTML（依當前 UI 語言在地化）。
///
/// 頁面完全自足（inline style、隨系統深淺色），文案經 HTML escape。
/// OAuth 流程在 token 交換成功即回這頁，不管使用者有沒有勾雲端硬碟權限；
/// 幸好 Google 的回跳 URL 帶有實際授予的 `scope` 參數，頁內 JS 據此在
/// 缺 drive.appdata 時切換成「缺少權限」指引，避免誤報授權完成。
String _buildPostAuthPage(AppLocalizations l, String lang) {
  const esc = HtmlEscape();
  final title = esc.convert(l.cloudSyncPostAuthTitle);
  final body = esc.convert(l.cloudSyncPostAuthBody);
  final missingTitle = esc.convert(l.cloudSyncPostAuthScopeMissingTitle);
  final missingBody = esc.convert(l.cloudSyncPostAuthScopeMissingBody);
  return '''
<!DOCTYPE html>
<html lang="$lang">
<head>
<meta charset="utf-8">
<title>$title</title>
<style>
  body { margin: 0; min-height: 100vh; display: flex; align-items: center;
         justify-content: center; font-family: system-ui, sans-serif;
         background: #14161a; color: #e6e9ef; }
  @media (prefers-color-scheme: light) {
    body { background: #f5f6f8; color: #1c1e21; }
  }
  main { text-align: center; padding: 2.5rem 3rem; max-width: 32rem; }
  .mark { font-size: 3rem; }
  h1 { font-size: 1.4rem; margin: 0.75rem 0 0.5rem; }
  p { margin: 0; opacity: 0.75; }
</style>
</head>
<body>
<main id="ok">
  <div class="mark">&#9989;</div>
  <h1>$title</h1>
  <p>$body</p>
</main>
<main id="scope-missing" hidden>
  <div class="mark">&#9888;&#65039;</div>
  <h1>$missingTitle</h1>
  <p>$missingBody</p>
</main>
<script>
  // Google 回跳帶 scope=實際授予的權限清單；缺 drive.appdata 時切換文案。
  // 參數缺席時保守維持成功文案（app 端另有 scope 驗證兜底）。
  var scope = new URLSearchParams(location.search).get('scope');
  if (scope !== null && scope.indexOf('drive.appdata') === -1) {
    document.getElementById('ok').hidden = true;
    document.getElementById('scope-missing').hidden = false;
  }
</script>
</body>
</html>
''';
}

/// 以當前 context 的語言組出完成頁並發起連結。
void _linkWithLocalizedPage(BuildContext context, WidgetRef ref) {
  final l = AppLocalizations.of(context)!;
  final lang = Localizations.localeOf(context).toLanguageTag();
  unawaited(
    ref
        .read(cloudSyncProvider.notifier)
        .link(postAuthPage: _buildPostAuthPage(l, lang)),
  );
}

/// 設定頁「雲端同步」區塊：連結 Google 帳號、自動同步開關、立即同步與中斷連結。
class CloudSyncSection extends ConsumerWidget {
  /// 建立 [CloudSyncSection]。
  const CloudSyncSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    if (!isCloudSyncConfigured) {
      return Text(
        l.cloudSyncUnconfigured,
        style: TextStyle(color: tokens.textMuted),
      );
    }

    // 授權等待結束（成功、失敗、缺 scope 皆同）時把視窗帶回前景，
    // 使用者在瀏覽器按完「允許」不必自己切回 app 看結果。
    ref.listen(cloudSyncProvider, (prev, next) {
      final leftConsent =
          prev?.phase == CloudSyncPhase.awaitingConsent &&
          next.phase != CloudSyncPhase.awaitingConsent;
      if (leftConsent) unawaited(ref.read(windowForegroundProvider)());
    });

    final email = ref.watch(
      settingsProvider.select((s) => s.cloudAccountEmail),
    );
    final sync = ref.watch(cloudSyncProvider);

    if (email == null) {
      return _UnlinkedView(l: l, sync: sync);
    }
    return _LinkedView(l: l, email: email, sync: sync);
  }
}

/// 未連結狀態：說明文字＋連結按鈕（授權等待中顯示 spinner 與取消）。
class _UnlinkedView extends ConsumerWidget {
  /// 建立 [_UnlinkedView]。
  const _UnlinkedView({required this.l, required this.sync});

  /// 當前 i18n 字串實例。
  final AppLocalizations l;

  /// 當前同步狀態（含階段與錯誤 token）。
  final CloudSyncState sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).gacha;
    final awaiting = sync.phase == CloudSyncPhase.awaitingConsent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.cloudSyncIntro, style: TextStyle(color: tokens.textSecondary)),
        if (sync.phase == CloudSyncPhase.error) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            sync.errorToken == 'scopeMissing'
                ? l.cloudSyncErrorScopeMissing
                : l.cloudSyncErrorAuthFailed,
            style: TextStyle(color: tokens.stateDanger),
          ),
        ],
        const SizedBox(height: AppSpacing.m),
        if (awaiting)
          _AwaitingConsentRow(l: l)
        else
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _linkWithLocalizedPage(context, ref),
              icon: const Icon(Icons.link, size: 18),
              label: Text(l.cloudSyncLink),
            ),
          ),
      ],
    );
  }
}

/// 等待瀏覽器授權中的提示列：spinner＋說明＋取消，未連結與重連兩處共用。
class _AwaitingConsentRow extends ConsumerWidget {
  /// 建立 [_AwaitingConsentRow]。
  const _AwaitingConsentRow({required this.l});

  /// 當前 i18n 字串實例。
  final AppLocalizations l;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).gacha;
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: Text(
            l.cloudSyncAwaitingConsent,
            style: TextStyle(color: tokens.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => ref.read(cloudSyncProvider.notifier).cancelLink(),
          child: Text(l.actionCancel),
        ),
      ],
    );
  }
}

/// 已連結狀態：email、自動同步開關、同步狀態列、立即同步與中斷連結。
class _LinkedView extends ConsumerWidget {
  /// 建立 [_LinkedView]。
  const _LinkedView({required this.l, required this.email, required this.sync});

  /// 當前 i18n 字串實例。
  final AppLocalizations l;

  /// 已連結帳號 email。
  final String email;

  /// 當前同步狀態。
  final CloudSyncState sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).gacha;
    final autoSync = ref.watch(
      settingsProvider.select((s) => s.cloudAutoSyncEnabled),
    );
    final lastSyncedAt = ref.watch(
      settingsProvider.select((s) => s.cloudLastSyncedAt),
    );
    final syncing = sync.phase == CloudSyncPhase.syncing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.cloudSyncLinkedAs(email)),
        const SizedBox(height: AppSpacing.s),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.cloudSyncAutoToggle),
          subtitle: Text(
            l.cloudSyncAutoToggleHint,
            style: TextStyle(color: tokens.textMuted, fontSize: 12),
          ),
          value: autoSync,
          onChanged: (v) => ref.read(cloudSyncProvider.notifier).setAutoSync(v),
        ),
        const SizedBox(height: AppSpacing.s),
        // 重連（reauthRequired → link）等待授權期間顯示與未連結態相同的
        // 等待列，取代狀態列與動作鈕，避免按了重連卻看似沒反應。
        if (sync.phase == CloudSyncPhase.awaitingConsent) ...[
          _AwaitingConsentRow(l: l),
        ] else ...[
          _StatusLine(l: l, sync: sync, lastSyncedAt: lastSyncedAt),
          const SizedBox(height: AppSpacing.m),
          Wrap(
            spacing: AppSpacing.m,
            runSpacing: AppSpacing.s,
            children: [
              FilledButton.icon(
                onPressed: syncing
                    ? null
                    : () => ref
                          .read(cloudSyncProvider.notifier)
                          .syncNow(manual: true),
                icon: syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync, size: 18),
                label: Text(l.cloudSyncNow),
              ),
              if (sync.phase == CloudSyncPhase.reauthRequired)
                FilledButton.icon(
                  onPressed: () => _linkWithLocalizedPage(context, ref),
                  icon: const Icon(Icons.link, size: 18),
                  label: Text(l.cloudSyncLink),
                ),
              OutlinedButton.icon(
                onPressed: () => _confirmUnlink(context, ref),
                icon: const Icon(Icons.link_off, size: 18),
                label: Text(l.cloudSyncUnlink),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 彈出中斷連結確認框，確認後執行 unlink。
  Future<void> _confirmUnlink(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final ok = await showConfirmDialog(
      context: context,
      title: l.cloudSyncUnlinkConfirmTitle,
      body: l.cloudSyncUnlinkConfirmBody,
      cancelLabel: l.actionCancel,
      confirmLabel: l.cloudSyncUnlink,
      confirmIcon: Icons.link_off,
    );
    if (ok != true) return;
    await ref.read(cloudSyncProvider.notifier).unlink();
  }
}

/// 同步狀態列：依 phase 顯示上次同步時間或錯誤原因。
class _StatusLine extends StatelessWidget {
  /// 建立 [_StatusLine]。
  const _StatusLine({
    required this.l,
    required this.sync,
    required this.lastSyncedAt,
  });

  /// 當前 i18n 字串實例。
  final AppLocalizations l;

  /// 當前同步狀態。
  final CloudSyncState sync;

  /// 上次同步成功時間。
  final DateTime? lastSyncedAt;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    switch (sync.phase) {
      case CloudSyncPhase.reauthRequired:
        return Text(
          sync.errorToken == 'scopeMissing'
              ? l.cloudSyncErrorScopeMissing
              : l.cloudSyncReauthRequired,
          style: TextStyle(color: tokens.stateDanger),
        );
      case CloudSyncPhase.error:
        final text = switch (sync.errorToken) {
          'busy' => l.cloudSyncErrorBusy,
          'schemaTooNew' => l.cloudSyncErrorSchemaTooNew,
          'authFailed' => l.cloudSyncErrorAuthFailed,
          'scopeMissing' => l.cloudSyncErrorScopeMissing,
          _ => l.cloudSyncErrorNetwork,
        };
        return Text(text, style: TextStyle(color: tokens.stateDanger));
      case CloudSyncPhase.idle:
      case CloudSyncPhase.syncing:
      case CloudSyncPhase.awaitingConsent:
        final at = lastSyncedAt;
        if (at == null) {
          return Text(
            l.cloudSyncNeverSynced,
            style: TextStyle(color: tokens.textMuted),
          );
        }
        return RelativeTimeText(
          time: at,
          templateBuilder: l.cloudSyncLastSynced,
          style: TextStyle(color: tokens.textMuted),
        );
    }
  }
}
```

- [ ] **Step 5: settings_page 掛載**

`lib/pages/settings_page.dart`：在「資料管理」`SectionCard`（`_DataManagement`）之後、「物品資料」`SectionCard`（`_ItemDataSection`）之前插入：

```dart
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsCloudSync,
                icon: Icons.cloud_sync_outlined,
                child: const CloudSyncSection(),
              ),
```

並加 import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/cloud_sync_section.dart';
```

- [ ] **Step 6: 跑測試確認通過**

Run: `fvm flutter test test/widgets/cloud_sync_section_test.dart test/state/cloud_sync_test.dart`
Expected: All tests passed!

- [ ] **Step 7: 補其餘八語 ARB**

依下列內容把同一組 key（含帶 placeholder key 的 `@` metadata，僅 template 以外的檔案照該檔既有慣例——本專案非 template ARB 亦帶 `@` metadata 時才加，否則只加字串 key；以各檔現況為準）加進各 ARB。**翻譯「祈願／卡池」詞彙時，先查該檔既有 key（如 `gachaType301`、`navOverview` 等）的用詞對齊。**

`app_zh_Hans.arb`：

```json
"settingsCloudSync": "云端同步",
"cloudSyncIntro": "关联 Google 账号后，卡池记录会自动备份到你的 Google 云端硬盘，并在多台电脑间同步。",
"cloudSyncUnconfigured": "此构建未配置 Google OAuth 凭据，云端同步无法使用。",
"cloudSyncLink": "关联 Google 账号",
"cloudSyncAwaitingConsent": "已打开浏览器，请在浏览器中完成授权...",
"cloudSyncLinkedAs": "已关联：{email}",
"cloudSyncAutoToggle": "自动同步",
"cloudSyncAutoToggleHint": "App 启动与数据变动后自动同步；关闭后仍可手动同步。",
"cloudSyncNow": "立即同步",
"cloudSyncUnlink": "取消关联",
"cloudSyncUnlinkConfirmTitle": "取消关联",
"cloudSyncUnlinkConfirmBody": "取消后将停止同步。本机数据与云端已备份的数据都会保留。",
"cloudSyncLastSynced": "上次同步：{time}",
"cloudSyncNeverSynced": "尚未同步",
"cloudSyncErrorNetwork": "同步失败：网络连接问题，稍后会自动重试。",
"cloudSyncErrorBusy": "同步暂缓：当前有更新或导入进行中，稍后会自动重试。",
"cloudSyncErrorSchemaTooNew": "同步已跳过：云端数据由较新版本的 App 创建，请先更新 App。",
"cloudSyncErrorAuthFailed": "授权失败，请再试一次。",
"cloudSyncErrorScopeMissing": "未获得 Google 云端硬盘权限，请重新关联并在授权页勾选云端硬盘的访问权限。",
"cloudSyncReauthRequired": "授权已失效，请重新关联 Google 账号。",
"cloudSyncRemoveFromCloud": "同时从云端同步数据中移除此账号",
"cloudSyncPostAuthTitle": "授权完成",
"cloudSyncPostAuthBody": "你可以关闭此页面，回到 App 继续操作。",
"cloudSyncPostAuthScopeMissingTitle": "缺少云端硬盘权限",
"cloudSyncPostAuthScopeMissingBody": "本次授权未包含 Google 云端硬盘的访问权限。请回到 App 重新关联，并在授权页勾选云端硬盘权限。"
```

`app_en.arb`：

```json
"settingsCloudSync": "Cloud sync",
"cloudSyncIntro": "Link your Google account to automatically back up wish records to your Google Drive and keep multiple computers in sync.",
"cloudSyncUnconfigured": "This build has no Google OAuth credentials configured; cloud sync is unavailable.",
"cloudSyncLink": "Link Google account",
"cloudSyncAwaitingConsent": "Browser opened. Please finish authorization in your browser...",
"cloudSyncLinkedAs": "Linked: {email}",
"cloudSyncAutoToggle": "Auto sync",
"cloudSyncAutoToggleHint": "Syncs automatically on app start and after data changes; manual sync stays available when off.",
"cloudSyncNow": "Sync now",
"cloudSyncUnlink": "Unlink",
"cloudSyncUnlinkConfirmTitle": "Unlink",
"cloudSyncUnlinkConfirmBody": "Syncing will stop. Both local data and the cloud backup are kept.",
"cloudSyncLastSynced": "Last synced: {time}",
"cloudSyncNeverSynced": "Not synced yet",
"cloudSyncErrorNetwork": "Sync failed: network problem. Will retry automatically.",
"cloudSyncErrorBusy": "Sync deferred: an update or import is in progress. Will retry automatically.",
"cloudSyncErrorSchemaTooNew": "Sync skipped: the cloud data was created by a newer app version. Please update the app first.",
"cloudSyncErrorAuthFailed": "Authorization failed. Please try again.",
"cloudSyncErrorScopeMissing": "Google Drive permission was not granted. Please relink and check Google Drive access on the consent page.",
"cloudSyncReauthRequired": "Authorization expired. Please relink your Google account.",
"cloudSyncRemoveFromCloud": "Also remove this account from cloud sync data",
"cloudSyncPostAuthTitle": "Authorization complete",
"cloudSyncPostAuthBody": "You can close this page and return to the app.",
"cloudSyncPostAuthScopeMissingTitle": "Google Drive permission missing",
"cloudSyncPostAuthScopeMissingBody": "This authorization did not include Google Drive access. Return to the app, relink, and check the Drive permission on the consent page."
```

`app_ja.arb`：

```json
"settingsCloudSync": "クラウド同期",
"cloudSyncIntro": "Google アカウントを連携すると、祈願履歴が自動的に Google ドライブへバックアップされ、複数の PC 間で同期されます。",
"cloudSyncUnconfigured": "このビルドには Google OAuth 認証情報が設定されていないため、クラウド同期は利用できません。",
"cloudSyncLink": "Google アカウントを連携",
"cloudSyncAwaitingConsent": "ブラウザを開きました。ブラウザで認可を完了してください...",
"cloudSyncLinkedAs": "連携中：{email}",
"cloudSyncAutoToggle": "自動同期",
"cloudSyncAutoToggleHint": "アプリ起動時とデータ変更後に自動同期します。オフでも手動同期は可能です。",
"cloudSyncNow": "今すぐ同期",
"cloudSyncUnlink": "連携を解除",
"cloudSyncUnlinkConfirmTitle": "連携を解除",
"cloudSyncUnlinkConfirmBody": "解除すると同期は停止します。ローカルとクラウドのデータはどちらも保持されます。",
"cloudSyncLastSynced": "前回の同期：{time}",
"cloudSyncNeverSynced": "まだ同期していません",
"cloudSyncErrorNetwork": "同期に失敗しました：ネットワークの問題です。後で自動的に再試行します。",
"cloudSyncErrorBusy": "同期を保留しました：更新またはインポートが進行中です。後で自動的に再試行します。",
"cloudSyncErrorSchemaTooNew": "同期をスキップしました：クラウドのデータは新しいバージョンのアプリで作成されています。先にアプリを更新してください。",
"cloudSyncErrorAuthFailed": "認可に失敗しました。もう一度お試しください。",
"cloudSyncErrorScopeMissing": "Google ドライブの権限が付与されていません。再連携し、認可ページでドライブへのアクセスにチェックを入れてください。",
"cloudSyncReauthRequired": "認可が失効しました。Google アカウントを再連携してください。",
"cloudSyncRemoveFromCloud": "クラウド同期データからもこのアカウントを削除する",
"cloudSyncPostAuthTitle": "認可が完了しました",
"cloudSyncPostAuthBody": "このページを閉じてアプリに戻ってください。",
"cloudSyncPostAuthScopeMissingTitle": "Google ドライブの権限がありません",
"cloudSyncPostAuthScopeMissingBody": "今回の認可には Google ドライブへのアクセスが含まれていません。アプリに戻って再連携し、認可ページでドライブの権限にチェックを入れてください。"
```

`app_es.arb`：

```json
"settingsCloudSync": "Sincronización en la nube",
"cloudSyncIntro": "Vincula tu cuenta de Google para respaldar automáticamente los registros de deseos en tu Google Drive y mantenerlos sincronizados entre varios equipos.",
"cloudSyncUnconfigured": "Esta compilación no tiene credenciales de Google OAuth configuradas; la sincronización en la nube no está disponible.",
"cloudSyncLink": "Vincular cuenta de Google",
"cloudSyncAwaitingConsent": "Se abrió el navegador. Completa la autorización en el navegador...",
"cloudSyncLinkedAs": "Vinculada: {email}",
"cloudSyncAutoToggle": "Sincronización automática",
"cloudSyncAutoToggleHint": "Se sincroniza automáticamente al iniciar la app y tras cambios de datos; con la opción desactivada aún puedes sincronizar manualmente.",
"cloudSyncNow": "Sincronizar ahora",
"cloudSyncUnlink": "Desvincular",
"cloudSyncUnlinkConfirmTitle": "Desvincular",
"cloudSyncUnlinkConfirmBody": "La sincronización se detendrá. Se conservarán tanto los datos locales como la copia en la nube.",
"cloudSyncLastSynced": "Última sincronización: {time}",
"cloudSyncNeverSynced": "Aún no sincronizado",
"cloudSyncErrorNetwork": "Error de sincronización: problema de red. Se reintentará automáticamente.",
"cloudSyncErrorBusy": "Sincronización pospuesta: hay una actualización o importación en curso. Se reintentará automáticamente.",
"cloudSyncErrorSchemaTooNew": "Sincronización omitida: los datos en la nube fueron creados por una versión más reciente de la app. Actualiza la app primero.",
"cloudSyncErrorAuthFailed": "Falló la autorización. Inténtalo de nuevo.",
"cloudSyncErrorScopeMissing": "No se otorgó el permiso de Google Drive. Vuelve a vincular y marca el acceso a Google Drive en la página de autorización.",
"cloudSyncReauthRequired": "La autorización expiró. Vuelve a vincular tu cuenta de Google.",
"cloudSyncRemoveFromCloud": "Eliminar también esta cuenta de los datos de sincronización en la nube",
"cloudSyncPostAuthTitle": "Autorización completada",
"cloudSyncPostAuthBody": "Puedes cerrar esta página y volver a la app.",
"cloudSyncPostAuthScopeMissingTitle": "Falta el permiso de Google Drive",
"cloudSyncPostAuthScopeMissingBody": "Esta autorización no incluyó el acceso a Google Drive. Vuelve a la app, vincula de nuevo y marca el permiso de Drive en la página de autorización."
```

`app_fr.arb`：

```json
"settingsCloudSync": "Synchronisation cloud",
"cloudSyncIntro": "Associez votre compte Google pour sauvegarder automatiquement l'historique des vœux sur votre Google Drive et le synchroniser entre plusieurs ordinateurs.",
"cloudSyncUnconfigured": "Cette version ne contient pas d'identifiants Google OAuth ; la synchronisation cloud est indisponible.",
"cloudSyncLink": "Associer un compte Google",
"cloudSyncAwaitingConsent": "Navigateur ouvert. Terminez l'autorisation dans le navigateur...",
"cloudSyncLinkedAs": "Associé : {email}",
"cloudSyncAutoToggle": "Synchronisation automatique",
"cloudSyncAutoToggleHint": "Synchronise automatiquement au démarrage de l'app et après chaque modification des données ; la synchronisation manuelle reste possible si désactivée.",
"cloudSyncNow": "Synchroniser maintenant",
"cloudSyncUnlink": "Dissocier",
"cloudSyncUnlinkConfirmTitle": "Dissocier",
"cloudSyncUnlinkConfirmBody": "La synchronisation s'arrêtera. Les données locales et la sauvegarde cloud seront conservées.",
"cloudSyncLastSynced": "Dernière synchronisation : {time}",
"cloudSyncNeverSynced": "Pas encore synchronisé",
"cloudSyncErrorNetwork": "Échec de la synchronisation : problème réseau. Nouvel essai automatique.",
"cloudSyncErrorBusy": "Synchronisation reportée : une mise à jour ou une importation est en cours. Nouvel essai automatique.",
"cloudSyncErrorSchemaTooNew": "Synchronisation ignorée : les données cloud ont été créées par une version plus récente de l'app. Mettez d'abord l'app à jour.",
"cloudSyncErrorAuthFailed": "Échec de l'autorisation. Veuillez réessayer.",
"cloudSyncErrorScopeMissing": "L'accès à Google Drive n'a pas été accordé. Associez à nouveau votre compte et cochez l'accès à Google Drive sur la page d'autorisation.",
"cloudSyncReauthRequired": "L'autorisation a expiré. Veuillez associer à nouveau votre compte Google.",
"cloudSyncRemoveFromCloud": "Supprimer aussi ce compte des données de synchronisation cloud",
"cloudSyncPostAuthTitle": "Autorisation terminée",
"cloudSyncPostAuthBody": "Vous pouvez fermer cette page et revenir à l'application.",
"cloudSyncPostAuthScopeMissingTitle": "Autorisation Google Drive manquante",
"cloudSyncPostAuthScopeMissingBody": "Cette autorisation n'inclut pas l'accès à Google Drive. Revenez à l'application, associez à nouveau votre compte et cochez l'autorisation Drive."
```

`app_pt_BR.arb`：

```json
"settingsCloudSync": "Sincronização na nuvem",
"cloudSyncIntro": "Vincule sua conta do Google para fazer backup automático dos registros de desejos no seu Google Drive e sincronizá-los entre vários computadores.",
"cloudSyncUnconfigured": "Esta compilação não tem credenciais do Google OAuth configuradas; a sincronização na nuvem está indisponível.",
"cloudSyncLink": "Vincular conta do Google",
"cloudSyncAwaitingConsent": "Navegador aberto. Conclua a autorização no navegador...",
"cloudSyncLinkedAs": "Vinculada: {email}",
"cloudSyncAutoToggle": "Sincronização automática",
"cloudSyncAutoToggleHint": "Sincroniza automaticamente ao iniciar o app e após alterações nos dados; com a opção desligada, a sincronização manual continua disponível.",
"cloudSyncNow": "Sincronizar agora",
"cloudSyncUnlink": "Desvincular",
"cloudSyncUnlinkConfirmTitle": "Desvincular",
"cloudSyncUnlinkConfirmBody": "A sincronização será interrompida. Os dados locais e o backup na nuvem serão mantidos.",
"cloudSyncLastSynced": "Última sincronização: {time}",
"cloudSyncNeverSynced": "Ainda não sincronizado",
"cloudSyncErrorNetwork": "Falha na sincronização: problema de rede. Nova tentativa automática.",
"cloudSyncErrorBusy": "Sincronização adiada: há uma atualização ou importação em andamento. Nova tentativa automática.",
"cloudSyncErrorSchemaTooNew": "Sincronização ignorada: os dados na nuvem foram criados por uma versão mais recente do app. Atualize o app primeiro.",
"cloudSyncErrorAuthFailed": "Falha na autorização. Tente novamente.",
"cloudSyncErrorScopeMissing": "A permissão do Google Drive não foi concedida. Vincule novamente e marque o acesso ao Google Drive na página de autorização.",
"cloudSyncReauthRequired": "A autorização expirou. Vincule novamente sua conta do Google.",
"cloudSyncRemoveFromCloud": "Remover também esta conta dos dados de sincronização na nuvem",
"cloudSyncPostAuthTitle": "Autorização concluída",
"cloudSyncPostAuthBody": "Você pode fechar esta página e voltar ao app.",
"cloudSyncPostAuthScopeMissingTitle": "Permissão do Google Drive ausente",
"cloudSyncPostAuthScopeMissingBody": "Esta autorização não incluiu o acesso ao Google Drive. Volte ao app, vincule novamente e marque a permissão do Drive na página de autorização."
```

`app_th.arb`：

```json
"settingsCloudSync": "การซิงค์ผ่านคลาวด์",
"cloudSyncIntro": "เชื่อมโยงบัญชี Google เพื่อสำรองประวัติการอธิษฐานไปยัง Google ไดรฟ์ของคุณโดยอัตโนมัติ และซิงค์ระหว่างคอมพิวเตอร์หลายเครื่อง",
"cloudSyncUnconfigured": "บิลด์นี้ไม่ได้ตั้งค่าข้อมูลรับรอง Google OAuth จึงใช้การซิงค์ผ่านคลาวด์ไม่ได้",
"cloudSyncLink": "เชื่อมโยงบัญชี Google",
"cloudSyncAwaitingConsent": "เปิดเบราว์เซอร์แล้ว โปรดทำการอนุญาตให้เสร็จในเบราว์เซอร์...",
"cloudSyncLinkedAs": "เชื่อมโยงแล้ว: {email}",
"cloudSyncAutoToggle": "ซิงค์อัตโนมัติ",
"cloudSyncAutoToggleHint": "ซิงค์อัตโนมัติเมื่อเปิดแอปและหลังข้อมูลมีการเปลี่ยนแปลง หากปิดไว้ยังซิงค์ด้วยตนเองได้",
"cloudSyncNow": "ซิงค์ตอนนี้",
"cloudSyncUnlink": "ยกเลิกการเชื่อมโยง",
"cloudSyncUnlinkConfirmTitle": "ยกเลิกการเชื่อมโยง",
"cloudSyncUnlinkConfirmBody": "การซิงค์จะหยุดลง ข้อมูลในเครื่องและข้อมูลสำรองบนคลาวด์จะยังคงอยู่",
"cloudSyncLastSynced": "ซิงค์ล่าสุด: {time}",
"cloudSyncNeverSynced": "ยังไม่เคยซิงค์",
"cloudSyncErrorNetwork": "ซิงค์ไม่สำเร็จ: ปัญหาเครือข่าย จะลองใหม่โดยอัตโนมัติ",
"cloudSyncErrorBusy": "เลื่อนการซิงค์: มีการอัปเดตหรือการนำเข้ากำลังดำเนินอยู่ จะลองใหม่โดยอัตโนมัติ",
"cloudSyncErrorSchemaTooNew": "ข้ามการซิงค์: ข้อมูลบนคลาวด์ถูกสร้างโดยแอปเวอร์ชันใหม่กว่า โปรดอัปเดตแอปก่อน",
"cloudSyncErrorAuthFailed": "การอนุญาตล้มเหลว โปรดลองอีกครั้ง",
"cloudSyncErrorScopeMissing": "ไม่ได้รับสิทธิ์ Google ไดรฟ์ โปรดเชื่อมโยงใหม่และเลือกสิทธิ์การเข้าถึง Google ไดรฟ์ในหน้าอนุญาต",
"cloudSyncReauthRequired": "การอนุญาตหมดอายุแล้ว โปรดเชื่อมโยงบัญชี Google อีกครั้ง",
"cloudSyncRemoveFromCloud": "ลบบัญชีนี้ออกจากข้อมูลซิงค์บนคลาวด์ด้วย",
"cloudSyncPostAuthTitle": "การอนุญาตเสร็จสมบูรณ์",
"cloudSyncPostAuthBody": "คุณสามารถปิดหน้านี้แล้วกลับไปที่แอปได้",
"cloudSyncPostAuthScopeMissingTitle": "ขาดสิทธิ์ Google ไดรฟ์",
"cloudSyncPostAuthScopeMissingBody": "การอนุญาตครั้งนี้ไม่ได้รวมสิทธิ์การเข้าถึง Google ไดรฟ์ โปรดกลับไปที่แอป เชื่อมโยงใหม่ และเลือกสิทธิ์ไดรฟ์ในหน้าอนุญาต"
```

`app_vi.arb`：

```json
"settingsCloudSync": "Đồng bộ đám mây",
"cloudSyncIntro": "Liên kết tài khoản Google để tự động sao lưu lịch sử Cầu Nguyện lên Google Drive của bạn và đồng bộ giữa nhiều máy tính.",
"cloudSyncUnconfigured": "Bản dựng này chưa cấu hình thông tin xác thực Google OAuth nên không dùng được đồng bộ đám mây.",
"cloudSyncLink": "Liên kết tài khoản Google",
"cloudSyncAwaitingConsent": "Đã mở trình duyệt. Vui lòng hoàn tất uỷ quyền trong trình duyệt...",
"cloudSyncLinkedAs": "Đã liên kết: {email}",
"cloudSyncAutoToggle": "Tự động đồng bộ",
"cloudSyncAutoToggleHint": "Tự động đồng bộ khi mở ứng dụng và sau khi dữ liệu thay đổi; tắt đi vẫn có thể đồng bộ thủ công.",
"cloudSyncNow": "Đồng bộ ngay",
"cloudSyncUnlink": "Huỷ liên kết",
"cloudSyncUnlinkConfirmTitle": "Huỷ liên kết",
"cloudSyncUnlinkConfirmBody": "Đồng bộ sẽ dừng lại. Dữ liệu trên máy và bản sao lưu trên đám mây đều được giữ nguyên.",
"cloudSyncLastSynced": "Đồng bộ lần cuối: {time}",
"cloudSyncNeverSynced": "Chưa đồng bộ",
"cloudSyncErrorNetwork": "Đồng bộ thất bại: sự cố mạng. Sẽ tự động thử lại.",
"cloudSyncErrorBusy": "Hoãn đồng bộ: đang có cập nhật hoặc nhập dữ liệu. Sẽ tự động thử lại.",
"cloudSyncErrorSchemaTooNew": "Đã bỏ qua đồng bộ: dữ liệu trên đám mây được tạo bởi phiên bản ứng dụng mới hơn. Vui lòng cập nhật ứng dụng trước.",
"cloudSyncErrorAuthFailed": "Uỷ quyền thất bại. Vui lòng thử lại.",
"cloudSyncErrorScopeMissing": "Chưa được cấp quyền Google Drive. Vui lòng liên kết lại và đánh dấu quyền truy cập Google Drive trên trang uỷ quyền.",
"cloudSyncReauthRequired": "Uỷ quyền đã hết hạn. Vui lòng liên kết lại tài khoản Google.",
"cloudSyncRemoveFromCloud": "Đồng thời xoá tài khoản này khỏi dữ liệu đồng bộ trên đám mây",
"cloudSyncPostAuthTitle": "Uỷ quyền hoàn tất",
"cloudSyncPostAuthBody": "Bạn có thể đóng trang này và quay lại ứng dụng.",
"cloudSyncPostAuthScopeMissingTitle": "Thiếu quyền Google Drive",
"cloudSyncPostAuthScopeMissingBody": "Lần uỷ quyền này không bao gồm quyền truy cập Google Drive. Vui lòng quay lại ứng dụng, liên kết lại và đánh dấu quyền Drive trên trang uỷ quyền."
```

然後：`fvm flutter gen-l10n`
Expected: 無錯誤。

- [ ] **Step 8: 全套驗證＋commit**

```
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
git add lib/widgets/cards/cloud_sync_section.dart lib/pages/settings_page.dart lib/l10n/ test/widgets/cloud_sync_section_test.dart
git commit -m "feat(cloud-sync): add settings page cloud sync section with i18n"
```

---

### Task 8: 刪帳號「同時從雲端移除」勾選

**Files:**
- Modify: `lib/widgets/dialogs/confirm_dialog.dart`
- Modify: `lib/widgets/cards/account_management.dart`
- Test: `test/widgets/dialogs/confirm_dialog_checkbox_test.dart`

**Interfaces:**
- Consumes: `cloudSyncProvider.notifier.queueCloudRemoval(String uid)`（Task 6）、`settingsProvider` 的 `cloudAccountEmail`、`l.cloudSyncRemoveFromCloud`（Task 7）。
- Produces:
  - `class ConfirmTypeResult { final bool confirmed; final bool checkboxChecked; }`
  - `Future<ConfirmTypeResult?> showConfirmTypeDialogWithCheckbox({...同 showConfirmTypeDialog 參數..., required String checkboxLabel})`
  - 既有 `showConfirmTypeDialog` 簽名與行為不變（回傳 `Future<bool?>`）。

- [ ] **Step 1: 寫失敗測試**

建立 `test/widgets/dialogs/confirm_dialog_checkbox_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';

void main() {
  /// 打開帶 checkbox 的打字確認 dialog 並回傳結果讀取函式。
  Future<ConfirmTypeResult? Function()> open(WidgetTester tester) async {
    ConfirmTypeResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showConfirmTypeDialogWithCheckbox(
                context: context,
                title: '確認',
                body: '刪除帳號 800000001？',
                expectedText: '800000001',
                cancelLabel: '取消',
                confirmLabel: '刪除',
                confirmIcon: Icons.delete_outline,
                checkboxLabel: '同時從雲端移除',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('打字正確＋勾選 → confirmed=true, checked=true', (tester) async {
    final read = await open(tester);
    await tester.enterText(find.byType(TextField), '800000001');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();

    final result = read();
    expect(result, isNotNull);
    expect(result!.confirmed, isTrue);
    expect(result.checkboxChecked, isTrue);
  });

  testWidgets('不勾選＋取消 → confirmed=false, checked=false', (tester) async {
    final read = await open(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final result = read();
    expect(result!.confirmed, isFalse);
    expect(result.checkboxChecked, isFalse);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/dialogs/confirm_dialog_checkbox_test.dart`
Expected: 編譯失敗（`ConfirmTypeResult` 不存在）。

- [ ] **Step 3: 實作 confirm_dialog.dart**

1. 加 result 類別與新入口（放檔案 top-level、`showConfirmTypeDialog` 前）：

```dart
/// [showConfirmTypeDialogWithCheckbox] 的結果。
class ConfirmTypeResult {
  /// 建立 [ConfirmTypeResult]。
  const ConfirmTypeResult({
    required this.confirmed,
    required this.checkboxChecked,
  });

  /// 使用者是否按下確認（打字閘通過）。
  final bool confirmed;

  /// 附加 checkbox 是否勾選。
  final bool checkboxChecked;
}

/// 顯示帶附加 checkbox 的打字確認 dialog。
/// 回傳 null = 系統 dismiss；否則見 [ConfirmTypeResult]。
Future<ConfirmTypeResult?> showConfirmTypeDialogWithCheckbox({
  required BuildContext context,
  required String title,
  required String body,
  required String expectedText,
  required String cancelLabel,
  required String confirmLabel,
  required IconData confirmIcon,
  required String checkboxLabel,
}) {
  return showDialog<ConfirmTypeResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ConfirmDialog(
      title: title,
      body: body,
      expectedText: expectedText,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      confirmIcon: confirmIcon,
      checkboxLabel: checkboxLabel,
    ),
  );
}
```

2. 既有 `showConfirmTypeDialog` 改為內部走同一 dialog、對外簽名不變：

```dart
Future<bool?> showConfirmTypeDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String expectedText,
  required String cancelLabel,
  required String confirmLabel,
  required IconData confirmIcon,
}) async {
  final result = await showDialog<ConfirmTypeResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ConfirmDialog(
      title: title,
      body: body,
      expectedText: expectedText,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      confirmIcon: confirmIcon,
      checkboxLabel: null,
    ),
  );
  return result?.confirmed;
}
```

3. `_ConfirmDialog` constructor 加 `required this.checkboxLabel`；欄位：

```dart
  /// 附加 checkbox 的標籤；null 代表不顯示 checkbox。
  final String? checkboxLabel;
```

4. `_ConfirmDialogState` 加：

```dart
  /// 附加 checkbox 目前是否勾選。
  bool _checked = false;
```

5. `build` 的 content `Column` 在 `TextField` 後加：

```dart
          if (widget.checkboxLabel != null) ...[
            const SizedBox(height: AppSpacing.m),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(widget.checkboxLabel!),
              value: _checked,
              onChanged: (v) => setState(() => _checked = v ?? false),
            ),
          ],
```

6. 兩顆按鈕的 pop 改為：

```dart
// 取消（TextButton.icon 的 onPressed）：
() => Navigator.of(context).pop(
  const ConfirmTypeResult(confirmed: false, checkboxChecked: false),
)
// 確認（FilledButton.icon 的 onPressed，維持 matches 才可按）：
matches
    ? () => Navigator.of(context).pop(
        ConfirmTypeResult(confirmed: true, checkboxChecked: _checked),
      )
    : null
```

- [ ] **Step 4: 跑測試確認通過（含既有 dialog 測試不退步）**

Run: `fvm flutter test test/widgets/dialogs/`
Expected: All tests passed!（既有 `confirm_dialog_test.dart` 走 `showConfirmTypeDialog` 包裝路徑，行為不變必須仍綠。）

- [ ] **Step 5: account_management 接線**

`lib/widgets/cards/account_management.dart` 的 `_remove` 改為：

```dart
  /// 彈出打字確認 dialog（已連結雲端時附「同時從雲端移除」勾選），
  /// 確認後刪除本機帳號，勾選時再把 UID 排入雲端移除佇列。
  Future<void> _remove(BuildContext ctx, WidgetRef ref, String uid) async {
    final l = AppLocalizations.of(ctx)!;
    final linked = ref.read(settingsProvider).cloudAccountEmail != null;

    if (!linked) {
      final ok = await showConfirmTypeDialog(
        context: ctx,
        title: l.confirmTitle,
        body: l.confirmClearActiveBody(uid),
        expectedText: uid,
        cancelLabel: l.actionCancel,
        confirmLabel: l.confirmDelete,
        confirmIcon: Icons.delete_outline,
      );
      if (ok != true) return;
      await ref.read(gachaRepositoryProvider.notifier).removeUid(uid);
      return;
    }

    final result = await showConfirmTypeDialogWithCheckbox(
      context: ctx,
      title: l.confirmTitle,
      body: l.confirmClearActiveBody(uid),
      expectedText: uid,
      cancelLabel: l.actionCancel,
      confirmLabel: l.confirmDelete,
      confirmIcon: Icons.delete_outline,
      checkboxLabel: l.cloudSyncRemoveFromCloud,
    );
    if (result == null || !result.confirmed) return;
    await ref.read(gachaRepositoryProvider.notifier).removeUid(uid);
    if (result.checkboxChecked) {
      await ref.read(cloudSyncProvider.notifier).queueCloudRemoval(uid);
    }
  }
```

加 import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
```

- [ ] **Step 6: 全套驗證＋commit**

```
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
git add lib/widgets/dialogs/confirm_dialog.dart lib/widgets/cards/account_management.dart test/widgets/dialogs/confirm_dialog_checkbox_test.dart
git commit -m "feat(cloud-sync): add remove-from-cloud checkbox to account deletion"
```

---

### Task 9: 啟動接線與憑證注入機制

**Files:**
- Modify: `lib/pages/app_shell.dart`
- Modify: `.gitignore`
- Modify: `scripts/build_installer/build_release.ps1`
- Modify: `.github/workflows/release-windows.yml`

**Interfaces:**
- Consumes: `cloudSyncProvider.notifier.start()`（Task 6）、`cloudSyncClientId`／`cloudSyncClientSecret` 的 `String.fromEnvironment` 名稱 `CLOUD_SYNC_CLIENT_ID`／`CLOUD_SYNC_CLIENT_SECRET`（Task 2）。
- Produces: App 啟動自動觸發同步；本機與 CI 建置可注入 OAuth 憑證。

- [ ] **Step 1: app_shell 啟動接線**

`lib/pages/app_shell.dart` 的 `initState` 內 `addPostFrameCallback`，在 `ref.read(appReleaseProvider.notifier).check(manual: false);` 之後加：

```dart
      ref.read(cloudSyncProvider.notifier).start();
```

加 import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
```

（`start()` 回傳 Future，這裡 fire-and-forget，與上一行 `check(manual: false)` 同模式；若 analyzer 報 unawaited future，包 `unawaited(...)` 並確認已 import `dart:async`。）

- [ ] **Step 2: .gitignore 加 secrets 目錄**

`.gitignore` 檔尾（`# FVM Version Cache` 區塊後）加：

```
# Local build-time secrets (dart-define-from-file inputs; CI writes its own from repo secrets)
/secrets/
```

- [ ] **Step 3: build_release.ps1 注入 dart-define**

`scripts/build_installer/build_release.ps1` 的「--- 3. Flutter build ---」段，把：

```powershell
Write-Host ""
Write-Host "==> flutter build windows --release" -ForegroundColor Green
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }
```

改成：

```powershell
Write-Host ""
Write-Host "==> flutter build windows --release" -ForegroundColor Green

# 雲端同步 OAuth 憑證不進 repo（會被 GitHub push protection 攔），改由建置時
# dart-define 注入：本機放 git-ignored 的 secrets/cloud_sync_defines.json，
# CI 於建置前由 repo secrets 產生同一路徑檔案。檔案不存在時照常建置，
# 僅雲端同步功能停用（isCloudSyncConfigured = false）。
$BuildArgs = @('build', 'windows', '--release')
$CloudSyncDefines = Join-Path $ProjectRoot 'secrets/cloud_sync_defines.json'
if (Test-Path $CloudSyncDefines) {
    Write-Host "cloud sync defines: $CloudSyncDefines" -ForegroundColor DarkGray
    $BuildArgs += "--dart-define-from-file=$CloudSyncDefines"
} else {
    Write-Host "cloud sync defines not found; cloud sync will be disabled in this build" -ForegroundColor Yellow
}
flutter @BuildArgs
if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }
```

- [ ] **Step 4: release workflow 寫入 secrets 檔**

`.github/workflows/release-windows.yml` 的 `# === D. Build ===` 區段內、`- name: Build Windows installer` 步驟**之前**插入：

```yaml
      # Cloud sync OAuth credentials are not committed; write the
      # dart-define-from-file input from repo secrets before building
      # (skipped when secrets are absent; only that feature is disabled).
      - name: Write cloud sync defines from secrets
        shell: pwsh
        env:
          CLOUD_SYNC_CLIENT_ID: ${{ secrets.CLOUD_SYNC_CLIENT_ID }}
          CLOUD_SYNC_CLIENT_SECRET: ${{ secrets.CLOUD_SYNC_CLIENT_SECRET }}
        run: |
          if ($env:CLOUD_SYNC_CLIENT_ID -and $env:CLOUD_SYNC_CLIENT_SECRET) {
            New-Item -ItemType Directory -Force secrets | Out-Null
            @{
              CLOUD_SYNC_CLIENT_ID     = $env:CLOUD_SYNC_CLIENT_ID
              CLOUD_SYNC_CLIENT_SECRET = $env:CLOUD_SYNC_CLIENT_SECRET
            } | ConvertTo-Json | Set-Content secrets/cloud_sync_defines.json -Encoding UTF8
            Write-Host "cloud sync defines written"
          } else {
            Write-Host "::warning::CLOUD_SYNC_CLIENT_ID/SECRET secrets not set; cloud sync will be disabled in this release build"
          }
```

- [ ] **Step 5: 全套驗證＋commit**

```
fvm dart format lib/ test/
fvm flutter analyze
fvm flutter test
git add lib/pages/app_shell.dart .gitignore scripts/build_installer/build_release.ps1 .github/workflows/release-windows.yml
git commit -m "feat(cloud-sync): wire startup trigger and credential injection"
```

---

### Task 10: README 四語更新

**Files:**
- Modify: `README.md`
- Modify: `README_EN.md`
- Modify: `README_JA-JP.md`
- Modify: `README_ZH-HANS.md`

**Interfaces:**
- Consumes: 無（純文件）。
- Produces: 功能清單含雲端同步條目、隱私敘述不再與新功能矛盾、fork 者知道如何自備憑證。

- [ ] **Step 1: README.md（繁中）**

1. 「功能與特色」清單新增條目（放在既有功能條目群內、隱私條目之前）：

```markdown
- 雲端同步（選擇性）：連結自己的 Google 帳號後，卡池記錄會自動備份到您自己的 Google 雲端硬碟，並在多台電腦間雙向同步；刪除帳號時可勾選一併從雲端移除
```

2. 修正隱私條目——把：

```markdown
- 所有資料留在本機，不上傳
```

改為：

```markdown
- 所有資料預設留在本機；雲端同步為選擇性功能，啟用後也只會備份到您自己的 Google 雲端硬碟
```

3. 開發／建置指引區塊（README 內描述如何建置處；若無明確建置章節，加在文件後段「開發」相關內容附近）新增小節：

```markdown
### 雲端同步憑證（開發者）

雲端同步的 Google OAuth 憑證不隨 repo 發佈，fork 後需自備才能啟用此功能：

1. 到 [Google Cloud Console](https://console.cloud.google.com/) 建立專案並啟用 **Google Drive API**。
2. 設定 OAuth 同意畫面（scopes：`.../auth/drive.appdata` 與 `email`），並建立「電腦版應用程式（Desktop app）」類型的 OAuth 用戶端 ID。
3. 在專案根目錄建立 git-ignored 的 `secrets/cloud_sync_defines.json`：

    ```json
    {
      "CLOUD_SYNC_CLIENT_ID": "<your-client-id>",
      "CLOUD_SYNC_CLIENT_SECRET": "<your-client-secret>"
    }
    ```

4. 建置腳本（`scripts/build_installer/build_release.ps1`）會自動帶入；直接 `flutter run` 時加 `--dart-define-from-file=secrets/cloud_sync_defines.json`。未設定時 App 照常運作，僅雲端同步區塊顯示未設定提示。

Release CI 由 repo Actions secrets `CLOUD_SYNC_CLIENT_ID`／`CLOUD_SYNC_CLIENT_SECRET` 產生同一檔案。
```

- [ ] **Step 2: README_EN.md**

同樣三處，英文文案：

功能條目：

```markdown
- Cloud sync (optional): link your own Google account to automatically back up gacha records to your own Google Drive and keep multiple computers in sync; account deletion can optionally remove the account from the cloud as well
```

隱私條目改為：

```markdown
- All data stays local by default; cloud sync is opt-in and only backs up to your own Google Drive
```

開發小節：

```markdown
### Cloud sync credentials (for developers)

The Google OAuth credentials for cloud sync are not shipped in the repo. Forks need their own to enable the feature:

1. Create a project in [Google Cloud Console](https://console.cloud.google.com/) and enable the **Google Drive API**.
2. Configure the OAuth consent screen (scopes: `.../auth/drive.appdata` and `email`) and create a **Desktop app** OAuth client ID.
3. Create a git-ignored `secrets/cloud_sync_defines.json` in the project root:

    ```json
    {
      "CLOUD_SYNC_CLIENT_ID": "<your-client-id>",
      "CLOUD_SYNC_CLIENT_SECRET": "<your-client-secret>"
    }
    ```

4. The build script (`scripts/build_installer/build_release.ps1`) picks it up automatically; for `flutter run`, add `--dart-define-from-file=secrets/cloud_sync_defines.json`. Without it the app still works, only the cloud sync section shows an unconfigured notice.

Release CI writes the same file from the repo Actions secrets `CLOUD_SYNC_CLIENT_ID` / `CLOUD_SYNC_CLIENT_SECRET`.
```

- [ ] **Step 3: README_JA-JP.md**

功能條目：

```markdown
- クラウド同期（任意）：自分の Google アカウントを連携すると、祈願履歴が自分の Google ドライブへ自動バックアップされ、複数の PC 間で双方向に同期されます。アカウント削除時にはクラウドからの削除も選択できます
```

隱私條目改為：

```markdown
- すべてのデータは既定でローカルに保存されます。クラウド同期はオプトインで、有効にしても自分の Google ドライブにのみバックアップされます
```

開發小節（標題「### クラウド同期の認証情報（開発者向け）」，內容比照英文版翻譯，JSON 範例與路徑相同）。

- [ ] **Step 4: README_ZH-HANS.md**

功能條目：

```markdown
- 云端同步（可选）：关联自己的 Google 账号后，卡池记录会自动备份到您自己的 Google 云端硬盘，并在多台电脑间双向同步；删除账号时可勾选一并从云端移除
```

隱私條目改為：

```markdown
- 所有数据默认留在本机；云端同步为可选功能，启用后也只会备份到您自己的 Google 云端硬盘
```

開發小節（標題「### 云端同步凭据（开发者）」，內容比照繁中版轉簡體，JSON 範例與路徑相同）。

- [ ] **Step 5: commit**

（純文件，不需跑測試，但仍跑 analyze 確保沒動到程式碼。）

```
fvm flutter analyze
git add README.md README_EN.md README_JA-JP.md README_ZH-HANS.md
git commit -m "docs: add cloud sync to README features and dev guide"
```

---

### Task 11: 手動驗證（需維護者操作，無法自動化）

**Files:** 無（驗證程序）。

**Interfaces:**
- Consumes: Task 1–10 全部完成。
- Produces: 實機驗證過的完整功能。

- [ ] **Step 1: 建立 OAuth 憑證**（維護者 GoneTone 操作；已定案為**另建一組**、不與鳴潮專案共用）

1. [Google Cloud Console](https://console.cloud.google.com/) 為本專案**新建專案** → 「API 和服務」啟用 **Google Drive API**。
2. 「OAuth 同意畫面」：External、填 App 名稱（原神祈願卡池分析）與聯絡信箱；scopes 加 `.../auth/drive.appdata` 與 `email`（皆為非敏感，不需審查）；發布狀態先用 Testing＋加自己為測試使用者，正式發佈前再 Publish。
3. 「憑證」→ 建立 OAuth 用戶端 ID → 應用程式類型選 **電腦版應用程式（Desktop app）**。
4. 把產出的 client id／secret 填入本機 git-ignored 的 `secrets/cloud_sync_defines.json`（格式見 Task 10 README 小節）。
5. 在 repo Settings → Secrets and variables → Actions 新增 `CLOUD_SYNC_CLIENT_ID`／`CLOUD_SYNC_CLIENT_SECRET`。

- [ ] **Step 2: 實機流程驗證**（`fvm flutter run -d windows --dart-define-from-file=secrets/cloud_sync_defines.json`）

1. 設定頁「雲端同步」→「連結 Google 帳號」→ 瀏覽器完成授權 → 授權完成頁顯示當前 UI 語言文案 → App 視窗自動回前景 → 顯示 email、自動跑第一輪、顯示上次同步時間。
2. 重啟 App → 啟動自動靜默同步（看 log `cloudsync.sync`，trigger=startup）。
3. 跑一次「更新資料」抓新記錄 → 5 秒 debounce 後自動同步（trigger=dataChange）。
4. 模擬第二台電腦：暫時改名 `%APPDATA%`（applicationSupport）下的 `gacha_data/` 目錄後啟動、連結同帳號 → 雲端資料自動合併下來，且**自動跳出補抓物品資料的進度框**，結束顯示物品資料摘要（PR #47 行為）。
5. 刪一個測試帳號勾「同時從雲端移除」→ 同步後把步驟 4 改名的目錄還原再啟動同步，確認該帳號未從雲端「復活」（pendingRemovals 已生效）。
6. 「中斷連結」→ email 清除；重連 → 資料從雲端合併回來。
7. 授權頁故意**不勾**雲端硬碟權限 → 完成頁就地顯示「缺少權限」指引、App 端顯示 scopeMissing 錯誤且不寫入連結狀態。
8. 匯出 log 檢查 `cloudsync.auth`／`cloudsync.sync` 節點內容齊全且無 token 洩漏、UID 已脫敏。

---

## Self-Review 紀錄

- **Spec 覆蓋**：§2 雲端佈局／憑證（Task 2、3、9）、§3 演算法＋合併細節＋schema 保護（Task 4、5；`last_active_uid` 與別名的本機優先由既有 `_runImport` 天然滿足——`_runImport` 對 lastActiveUid 採 local-wins、別名採本機優先）、§4 同步後補抓（Task 5 `fetchItemImagesForCloudSync`＋Task 6 觸發＋測試）、§5 觸發四入口（Task 6、9）、§6 登入登出 token（Task 2、6）、§7 刪帳號（Task 8）、§8 UI 含授權完成頁與視窗回前景（Task 7）＋i18n 九語（Task 7 Step 1／7）、§9 錯誤分流（Task 6 狀態＋Task 7 狀態列）、§10 logging（各 task 內嵌，`cloudsync.auth`／`cloudsync.sync`）、§11 落點（File Structure）、§12 README（Task 10）、§13 測試（各 task TDD＋Task 11 手動）、§14 合併前注意（Task 11 Step 1）。
- **佔位符**：無 TBD／TODO；README 開發小節的 `<your-client-id>` 為給使用者的填空範例，屬文件內容而非計畫佔位。
- **型別一致性**：`importBundleForCloudSync`／`fetchItemImagesForCloudSync`／`runSyncRound`／`syncFingerprint`／`queueCloudRemoval`／`ConfirmTypeResult`／`CloudAuthSession(refreshToken)` 等簽名已跨 task 對齊 Interfaces 區塊；本專案帳號欄位一律 `a.data.uid`（非姐妹專案的 `playerId`）、bundle JSON 一律 `uid`／`last_updated`／`banners` 格式。
- **已知外部 API 風險**：`googleapis_auth`／`googleapis` 的實際簽名以裝好的版本為準（Task 2 Step 5、Task 3 Step 4 已註明調整原則：內部呼叫可調、對外介面不變）；Riverpod `ref.listen` 萬用字元參數寫法見 Task 6 Step 5 註記。

