# 「更新資料」按鈕立即回饋設計

- 日期：2026-05-11
- 範圍：
  - 修改 `lib/state/update_progress.dart`（新增 `Preparing` case）
  - 修改 `lib/state/wish_repository.dart`（立刻設定 progress、引入可中斷 client、新增 `cancelPreparing()`）
  - 修改 `lib/services/wish_fetcher.dart`（client 改為 per-call 參數，移除建構式注入）
  - 修改 `lib/widgets/update_progress_dialog.dart`（補上 `Preparing` 的 title / body / actions）
  - 修改 `lib/l10n/app_en.arb` / `app_zh.arb` / `app_zh_Hant.arb`（新增 2 個字串）
  - 修改 `test/services/wish_fetcher_test.dart`（適配新簽名）
  - 修改 `test/state/wish_repository_test.dart`（新增 preparing/cancel 測試）
- 不影響：MITM 攔截、`WaitingForCapture` / `FetchingBanner` / `UpdateCompleted` / `UpdateFailed` 既有行為、settings page、其他 page

## 目標

使用者按下「更新資料」按鈕後，UpdateProgressDialog **立刻**跳出，不再因為讀 cached URL 檔案 I/O 與 UID probe HTTP request 的等待時間（最壞情況數秒）造成「按了沒反應」的錯覺。

新增的「準備中」階段也支援取消，且取消會**真正中斷** in-flight HTTP request，而非等它跑完才丟棄結果。

## 根因

`lib/pages/app_shell.dart:28-42` 監聽 `WishState.progress`，只有 progress 從 null 變非 null 時才會 `showDialog`。但 `WishRepository._runUpdate()`（`lib/state/wish_repository.dart:119`）中，progress 第一次被設定的時機是：

- **無 cached URL 路徑**：進入 `_runMitm()` 時（第 201 行）才設定 `WaitingForCapture`
- **有 cached URL 路徑**：第一個 banner 第一頁 `onProgress` callback（第 246 行）才設定 `FetchingBanner`

兩條路徑都需先經過：
1. `await storage.loadCapturedUrl(...)`：檔案 I/O，數十 ms
2. `await fetcher.probeUid(url: url)`：HTTP request 數百 ms 至數秒

這段時間 progress 仍為 `null` → dialog 不會跳出。

## 非目標

- **`FetchingBanner` 階段不加取消按鈕**：fetching 已有可見進度（page index、新增筆數），不會感覺卡住。範圍若擴大需另外設計多 banner 取消後的部分寫入策略。
- **不做 cancel token 抽象層**：直接用 `dart:io HttpClient.close(force: true)` 即可，YAGNI。
- **不保留 `httpClientProvider`**：改動後沒有其他地方使用，移除以維持 YAGNI。
- **不改 MITM 取消邏輯**：`WaitingForCapture` 階段已透過 `cancelCapture()` → `stop_capture` 處理，行為不變。
- **不支援 web 平台**：app 為 Windows desktop only，`dart:io` 使用無平台限制。

## 異動檔案總覽

| 檔案 | 動作 | 說明 |
|---|---|---|
| `lib/state/update_progress.dart` | 修改 | 新增 `Preparing` sealed 子類別 |
| `lib/state/wish_repository.dart` | 修改 | `_runUpdate` 開頭設 `Preparing`；引入 dart:io `HttpClient` + `IOClient` 持有；catch `ClientException`；新增 `cancelPreparing()`；移除 `httpClientProvider` 引用 |
| `lib/services/wish_fetcher.dart` | 修改 | 建構式不再接 `http.Client`；`fetchPage` / `probeUid` / `fetchBannerWithMerge` 新增 `client` 參數 |
| `lib/widgets/update_progress_dialog.dart` | 修改 | `_Title` / `_Body` / `_actions` 三處 switch 補 `Preparing()` case |
| `lib/l10n/app_en.arb` / `app_zh.arb` / `app_zh_Hant.arb` | 修改 | 新增 `progressPreparing`、`progressPreparingHint` |
| `lib/l10n/generated/*` | 由 `flutter gen-l10n` 自動產出 | 不手寫 |
| `test/services/wish_fetcher_test.dart` | 修改 | 適配 client per-call 簽名 |
| `test/state/wish_repository_test.dart` | 修改 | 新增 preparing 立刻設定 + cancelPreparing 中斷測試 |

## 設計

### 1. `UpdateProgress` 新增 `Preparing`

`lib/state/update_progress.dart`：

```dart
class Preparing extends UpdateProgress {
  const Preparing();
}
```

Sealed class，順序放在 `WaitingForCapture` 之前。

### 2. `WishFetcher` 重構為 stateless 配置容器

把 `_client` 從建構式注入改為 per-call 參數。這讓 Repository 能為每次 update 建立短命且可中斷的 client，且 fetcher 本身變得更純粹（沒有可變狀態）。

`lib/services/wish_fetcher.dart`：

```dart
class WishFetcher {
  WishFetcher({
    this.rateLimit = const Duration(milliseconds: 600),
    this.retryBackoff = const Duration(seconds: 5),
    this.timeout = const Duration(seconds: 10),
  });
  // 移除 final http.Client _client;

  final Duration rateLimit;
  final Duration retryBackoff;
  final Duration timeout;

  Future<FetchedPage> fetchPage(Uri url, http.Client client) async {
    // 內部改用參數 client，不再用 this._client
  }

  Future<UidProbeResult> probeUid({
    required GachaUrl url,
    required http.Client client,
  }) async { ... }

  Future<List<WishRecord>> fetchBannerWithMerge({
    required GachaUrl url,
    required String gachaType,
    required List<WishRecord> existing,
    required FetchedPage? primer,
    required void Function(FetchProgress) onProgress,
    required http.Client client,
  }) async { ... }
}
```

`wishFetcherProvider` 不再讀 `httpClientProvider`：

```dart
final wishFetcherProvider = Provider<WishFetcher>((ref) => WishFetcher());
```

`httpClientProvider` 整個移除。

### 3. Repository 引入 cancellable client

`lib/state/wish_repository.dart`：

```dart
import 'dart:io' as io;
import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;

class WishRepository extends Notifier<WishState> {
  bool _isUpdating = false;
  Future<void> Function()? _activeCancel;
  io.HttpClient? _activeIoClient;

  Future<void> _runUpdate({required bool forceRecapture}) async {
    if (_isUpdating) return;
    _isUpdating = true;

    final ioClient = io.HttpClient();
    final client = IOClient(ioClient);
    _activeIoClient = ioClient;

    // 立刻設 Preparing → ref.listen 立刻觸發 dialog
    state = state.copyWith(progress: const Preparing());

    try {
      final initialActiveUid = state.activeUid;
      final storage = ref.read(wishStorageProvider);
      final fetcher = ref.read(wishFetcherProvider);

      if (forceRecapture && initialActiveUid != null) {
        await storage.deleteCapturedUrl(initialActiveUid);
        if (!ref.mounted) return;
      }

      String? capturedUrl;
      if (!forceRecapture && initialActiveUid != null) {
        capturedUrl = await storage.loadCapturedUrl(initialActiveUid);
        if (!ref.mounted) return;
      }

      if (capturedUrl == null) {
        capturedUrl = await _runMitm(isFallback: false);
        if (!ref.mounted) return;
        if (capturedUrl == null) {
          state = state.copyWith(clearProgress: true);
          return;
        }
      }

      try {
        await _fetchAllBanners(
          url: capturedUrl,
          fetcher: fetcher,
          storage: storage,
          client: client,
        );
      } on AuthExpiredException {
        // ...既有 fallback 流程，內部仍可能拋 ClientException，見下方處理
      } on http.ClientException catch (e) {
        if (!ref.mounted) return;
        if (_cancelTriggered) {
          state = state.copyWith(clearProgress: true);
        } else {
          state = state.copyWith(progress: UpdateFailed(_friendlyError(e)));
        }
      } catch (e) {
        if (!ref.mounted) return;
        state = state.copyWith(progress: UpdateFailed(_friendlyError(e)));
      }
    } finally {
      _activeIoClient = null;
      client.close();
      _cancelTriggered = false;
      _isUpdating = false;
    }
  }

  void cancelPreparing() {
    _cancelTriggered = true;
    _activeIoClient?.close(force: true);
  }

  // _fetchAllBanners 加 client 參數，傳給 fetcher.probeUid / fetchBannerWithMerge
}
```

**`ClientException` 攔截位置**：放在內層 `catch (e)` **之前**，與 `AuthExpiredException` 並列。理由：`_fetchAllBanners` 既有的內層 try 已涵蓋 probe + fetch 兩階段，把 `on http.ClientException` 加在這層比放外層更精準（避免被泛 `catch (e)` 先吃掉）。AuthExpiredException 的 fallback 內部會再呼叫 `_fetchAllBanners`，那一層也要套用同樣的 `on http.ClientException` 順序。

**為何不在 `Preparing` 階段顯式檢查 flag**：HTTP request 被 `force: true` 中斷後會立刻拋 `ClientException`，不需要額外的 polling flag。檔案 I/O（`loadCapturedUrl`）通常 <50ms 不值得處理；萬一真的在這 50ms 內按取消，會等讀完才進到 `probeUid` 拋 exception，使用者體感仍然秒回（因為 `close(force: true)` 是同步觸發 exception）。

### 4. Dialog 對 `Preparing` 的呈現

`lib/widgets/update_progress_dialog.dart`：

**`_Title` switch**：
```dart
Preparing() => (
  Icons.hourglass_empty,
  tokens.textPrimary,
  l.progressPreparing,
),
```

**`_Body` switch**：
```dart
Preparing() => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    const LinearProgressIndicator(),
    const SizedBox(height: AppSpacing.l),
    Text(l.progressPreparingHint),
  ],
),
```

**`_actions` switch**：
```dart
Preparing() => [
  TextButton(
    onPressed: r.cancelPreparing,
    child: Text(l.actionCancel),
  ),
],
```

### 5. i18n 新字串

`lib/l10n/app_zh_Hant.arb`：
```json
"progressPreparing": "準備中…",
"progressPreparingHint": "正在準備資料來源…",
```

`lib/l10n/app_zh.arb`：
```json
"progressPreparing": "准备中…",
"progressPreparingHint": "正在准备数据源…",
```

`lib/l10n/app_en.arb`：
```json
"progressPreparing": "Preparing…",
"progressPreparingHint": "Preparing data source…",
```

執行 `flutter gen-l10n` 重新產出 `lib/l10n/generated/*`。

### 6. 邊界情境

| 情境 | 行為 |
|---|---|
| 按更新 → 立刻按取消（檔案 I/O 中） | I/O 完成後進 `probeUid`，第一個 HTTP request 立刻拋 `ClientException` → `clearProgress` |
| 按更新 → probe 中按取消 | in-flight HTTP request 被 `force:true` 中斷 → `ClientException` → `clearProgress` |
| 按更新 → 進到 MITM 後按取消 | MITM 階段 dialog 已切到 `WaitingForCapture`，行為走既有 `cancelCapture()`（不受本次改動影響）|
| 按更新 → 進到 fetching 後 | `_actions` 是空，沒有取消按鈕（既有行為）|
| 取消後立刻再按更新 | `_isUpdating` 仍可能為 true（極短窗口），會被 reentry guard 擋住；之後正常 |
| 已連線拋 socket error（非取消） | 內層 `on http.ClientException` 攔截後檢查 `_cancelTriggered`：false → `UpdateFailed`，true → `clearProgress` |

**關於 ClientException 雙重語意**：`http.ClientException` 同時涵蓋「使用者取消（`close(force:true)` 觸發）」與「真實網路錯誤（DNS 失敗、socket reset 等）」。用一個 `_cancelTriggered` boolean flag 區分：

- `cancelPreparing()` set flag = true 後 `close(force:true)`
- 內層 `on http.ClientException` 攔截後讀 flag → 為 true 走取消、為 false 走 UpdateFailed
- `finally` 重置 flag = false

§3 程式碼片段已採用此寫法。

`_friendlyError` 補一個 case：
```dart
http.ClientException(:final message) => UpdateErrorOther(message),
```

### 7. 測試策略

**`test/services/wish_fetcher_test.dart`**：
- 所有 `fetcher.fetchPage / probeUid / fetchBannerWithMerge` 呼叫都改為傳 mock client 參數
- 既有測試斷言不變

**`test/state/wish_repository_test.dart`**：
- 新增測試：呼叫 `update()` 後第一個 microtask 完成時 `state.progress is Preparing`
- 新增測試：preparing 階段呼叫 `cancelPreparing()` → probe HTTP request 拋 `ClientException` → `state.progress == null` 且 `state.activeData` 不變
- 新增測試：probe 階段真實網路錯誤（mock client 拋 `ClientException`，但**未**呼叫 `cancelPreparing`）→ `state.progress is UpdateFailed`

### 8. 提交前檢查

- `dart format lib/ test/`
- `flutter analyze` → No issues found!
- `flutter test` → All tests passed!

## 風險與權衡

| 風險 | 緩解 |
|---|---|
| `http.ClientException` 同時涵蓋「取消」與「真實網路錯誤」 | `_cancelTriggered` flag 區分（見 §6） |
| `dart:io HttpClient` 不能跨 web 平台 | 此 app 為 Windows desktop only，YAGNI |
| fetcher 簽名變動影響既有測試 | 範圍可控（fetcher 與 repository 兩個檔），統一替換 |
| `_isUpdating` 在取消後仍維持 true 直到 finally 結束 | 取消後 `close(force: true)` 同步觸發 ClientException → catch → finally 立刻釋放，視窗極小 |
