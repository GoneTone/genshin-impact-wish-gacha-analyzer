# Spec：MITM 捕獲拆除死鎖與取消無反應的防禦縱深修復

- 日期：2026-06-05
- 分支：`master`
- 來源：使用者回報「有時候點擊更新資料時彈出『等待攔截』訊息，但進入（遊戲內）祈願歷史頁時載不進去，或者載入了但軟體這邊沒有開始抓資料，然後點擊取消按鈕也沒有反應。不是每次都這樣，只有少數情況。」無現場 log、難穩定重現，決定以靜態分析為準，對所有可能卡死點做防禦性補強（defense-in-depth）。

## 1. 背景

更新流程：點「更新資料」→ `GachaRepository._runUpdate` → `_runMitm` 設 `WaitingForCapture` → `start_capture()`（Rust 起 MITM proxy thread ＋ 設系統 proxy）→ Dart `RustGachaCapture.start()` `listen` 那條 stream，`_runMitm` 卡在 `await session.result` 等 →（使用者去遊戲開祈願歷史）→ 遊戲打 `/getGachaLog` 經 proxy → MITM `handle_request` 命中 → `sink.add(url)` → `handle_response` 延遲 500ms 後 spawn 一條 OS thread 呼叫 `stop_capture()` → drop `Session`：先 drop `MitmServerGuard`（送 graceful shutdown 訊號後 `h.join()` 等 thread 結束）→ 再 drop `SysProxyGuard`（還原系統 proxy）→ sink 被 drop → Dart stream `onDone` 觸發 → completer 完成 → 拿到 URL 開始抓。

取消路徑：`update_progress_dialog.dart` 的 `WaitingForCapture` 取消按鈕 → `GachaRepository.cancelCapture()` → `await _activeCancel()` → `await rust_capture.stopCapture()`，邏輯同上靠 drop 觸發 onDone。

### 根因（靜態分析）

`MitmServerGuard::drop`（`rust/src/mitm.rs:22-31`）用**無上限**的 `h.join()` 等 MITM thread 結束，而 thread 跑的是 hudsucker **graceful shutdown**——它會等所有「還開著的連線」收尾。遊戲 webview（WebView2／CEF 走 WinINet）是 **keep-alive 長連線**；少數情況那條連線卡著沒關（或頁面根本載不進去、連線半開），graceful shutdown 就無限期等 → `proxy.start().await` 不返回 → `block_on` 不返回 → thread 不結束 → `h.join()` 永遠 block → `stop_capture()` 整個卡死。

連鎖效應正好對上三個症狀：

| # | 症狀 | 機制 |
|---|---|---|
| 1 | 取消按鈕沒反應 | `cancelCapture` 的 `await stopCapture()` 卡在 `h.join()`，Future 永遠不回 |
| 2 | dialog 永遠關不掉 | `update_progress_dialog.dart` 是 `PopScope(canPop: false)`，只在 `progress` 變 `null` 時自動 pop；`_runMitm` 的 `await session.result` 無 timeout，onDone 不觸發就一直停在 `WaitingForCapture` |
| 3 | （最嚴重的潛在後果）整台電腦網路斷 | `Session` drop 順序是先 `_mitm`（join 卡住）後 `_proxy`（還原）；join 一旦卡死，**系統 proxy 永遠不被還原**，使用者全系統流量卡在指向已死的 `127.0.0.1:18080`，直到重開 App 靠 `cleanup_stale_proxy` 自救 |

問題本質：**MITM 拆除是無界操作，一旦某條連線卡住就連鎖卡死整條鏈，且沒有任何逃生口。**

## 2. 目標

在三個獨立層各放一道保險，任一層失手另一層接住：

| 層 | 改動位置 | 保證 |
|---|---|---|
| **L1 Rust 根因** | `rust/src/mitm.rs`（必要時 `rust/Cargo.toml`） | MITM 拆除一定在約 2 秒內完成 → port 釋放、系統 proxy 必還原 |
| **L2 Dart 逃生口** | `lib/state/gacha_repository.dart` `cancelCapture` | 取消一定在有界時間回應、關閉 dialog；逾時 best-effort 還原 proxy |
| **L3 Dart 兜底** | `lib/state/gacha_repository.dart` `_runMitm` | 等待改 `Future.any([result, backstop])`，onDone 失靈也能被解開 |

## 3. 非目標（YAGNI）

- 不替 `FetchingBanner` / `FetchingHoYoWiki` 階段補取消按鈕：它們的 HTTP 請求本就有 `GachaFetcher.timeout`（10 秒）保護，不是本次卡死的成因。
- 不做「等待攔截」自動逾時：等待是使用者驅動（需要時間去開遊戲祈願頁），自動逾時誤殺風險高。
- 不做 proxy 健康檢查（主動驗證系統 proxy 是否真的生效）。
- 不改動 `handle_response` 既有的 500ms in-flight 排空延遲與整體 auto-stop 設計。
- 不重構 drop 順序：`_mitm` 先、`_proxy` 後的順序是刻意的（避免 broadcast `SETTINGS_CHANGED` 中斷遊戲正在處理的 fetch），L1 讓 `_mitm` 拆除變有界後此順序自然安全。

## 4. 設計

### 4.1 L1 — Rust 有界拆除（核心）

把 MITM thread 從「`block_on(proxy.start())` 等 graceful 排空完才返回 → `h.join()` 無界等」改成**有界強制拆除**：

- proxy 改用 `rt.spawn(...)` 當 task 跑，thread 改 `block_on` 一個 shutdown 訊號。
- shutdown 訊號用 `tokio::sync::watch`（單一 sender、可 clone 多個 receiver），讓「hudsucker graceful shutdown future」與「thread 的 `block_on`」共用同一個訊號：
  - graceful future：`rx.wait_for(|v| *v).await`（訊號為 true 時 hudsucker 停止 accept、排空 in-flight）。
  - thread block：`rt.block_on(async { rx.wait_for(|v| *v).await })`。
- 訊號觸發、`block_on` 返回後 → `rt.shutdown_timeout(Duration::from_secs(2))`：給 in-flight（命中的 gacha response，`handle_response` 本就先給 500ms 排空）最多 2 秒收尾，逾時**強制中斷**所有殘餘連線、結束 runtime。
- `MitmServerGuard` 改持有 `watch::Sender<bool>` ＋ `JoinHandle`。`drop` 中 `send(true)` 後 `h.join()`：此時 thread 必在約 2 秒內結束，join 一定有界。
- drop 順序維持不變（先 `_mitm` 後 `_proxy`）：`_mitm` 拆除有界後，`_proxy` 還原必定執行 → 修掉症狀 3。
- 拆除每步補 `tracing`：送訊號、進入強制中斷、join 完成（對齊既有 `target: "mitm"`）。

實作注意（plan 階段驗證）：

- `watch::Receiver::wait_for` 需 tokio ≥ 1.27（`sync` feature 已開）。
- 確認 `Runtime::shutdown_timeout` 與 hudsucker 內部 time driver 的 feature 需求；若需要，於 `rust/Cargo.toml` 給 tokio 補 `time` feature。
- `stop_capture()` 與 `cleanup_stale_proxy()` 對外簽名不變（已有 Dart binding）。

### 4.2 L2 / L3 — Dart 逃生口與兜底

放在 **repository 層**（可用既有 `ProviderContainer` ＋ `GachaCapture` mock 測試）；`RustGachaCapture` 維持薄薄一層只轉 stream，不放兜底邏輯（它呼叫真 FFI，難測）。

新增欄位：

```dart
/// 取消／逾時時用來強制解開 _runMitm 等待的 backstop completer。
Completer<String?>? _captureBackstop;

/// cancelCapture 等 Rust 拆除的上限（比 L1 的 2 秒寬鬆）。
static const _cancelTeardownTimeout = Duration(seconds: 8);
```

`_runMitm` 等待改為 race：

```dart
Future<String?> _runMitm({required bool isFallback}) async {
  state = state.copyWith(progress: WaitingForCapture(isFallback: isFallback));
  final session = ref.read(gachaCaptureProvider).start();
  _activeCancel = session.cancel;
  final backstop = Completer<String?>();
  _captureBackstop = backstop;
  _log.info('MITM ${isFallback ? "fallback" : "primary"} session started');
  try {
    final result = await Future.any([session.result, backstop.future]);
    _log.info('MITM session done, hasUrl=${result != null}');
    return result;
  } finally {
    _activeCancel = null;
    _captureBackstop = null;
  }
}
```

`cancelCapture` 改為有界、且必定解開等待：

```dart
Future<void> cancelCapture() async {
  final cancel = _activeCancel;
  if (cancel == null) return;
  _cancelTriggered = true;
  try {
    await cancel().timeout(_cancelTeardownTimeout);
  } on TimeoutException {
    _log.severe(
      'cancelCapture: stopCapture exceeded '
      '${_cancelTeardownTimeout.inSeconds}s; forcing cleanup',
    );
    unawaited(_bestEffortStaleProxyCleanup());
  }
  // 無論成功或逾時，都解開 _runMitm 的等待（onDone 失靈也不會卡死）。
  if (!(_captureBackstop?.isCompleted ?? true)) {
    _captureBackstop!.complete(null);
  }
}
```

`_bestEffortStaleProxyCleanup` 包一層 try/catch 呼叫 `rust_capture.cleanupStaleProxy()`，失敗只 warn-log，不拋。

行為與不變式：

- happy path（`cancel()` 正常）：stopCapture 觸發 onDone → `session.result` 回 null → `Future.any` 回 → `_runUpdate` 既有邏輯 `clearProgress`。backstop 即使之後 complete 也無人 await，無副作用。
- 卡死 path（`cancel()` 逾時或 onDone 不觸發）：逾時分支 severe-log ＋ best-effort 還原 proxy，再 `backstop.complete(null)` → `_runMitm` 回 null → dialog 關閉、`_runUpdate` 的 `finally` 清 `_isUpdating`。
- re-entrancy 安全：仍走 `_runMitm` → `_runUpdate` 正常回傳路徑，`_isUpdating` 由既有 `finally` 管理，不會提早放行下一次 update。L2 的 8 秒寬於 L1 的 2 秒，正常情況 Rust 早已拆完，backstop 只是最後一道。

## 5. 測試

### 5.1 Dart（`test/state/gacha_repository_test.dart`，沿用既有 `ProviderContainer` ＋ Fake 模式）

- **取消能解開永不回的等待**：`_HangingCapture`（`result` 為永不 complete 的 `Completer`，`cancel` 立即回）→ 觸發 update 進入 `WaitingForCapture` → `cancelCapture()` → 斷言 `progress` 變 `null`（backstop 解卡）、既有資料保留。
- **cancel 本身卡住走逾時分支**：`_HangingCancelCapture`（`cancel` 回一個永不 complete 的 Future）→ 用 **`fake_async`** 推進 `_cancelTeardownTimeout` → 斷言走 `TimeoutException` 分支、`progress` 清空、有 `gacha.repo` severe log（避免真實掛鐘 flaky，對齊既有 fake_async 慣例）。
- **happy path**：`cancel` 正常、`result` 經（模擬的）onDone 回 null → 斷言 progress 清空。

### 5.2 Rust（`rust/src/mitm.rs` 或 `rust/tests/`）

- smoke test：在一個 port 起 MITM、無任何連線時 drop `MitmServerGuard`（或呼叫 `stop_capture()`），斷言能即時返回（驗證有界拆除的正常路徑）。
- 「卡住的連線」case 難穩定自動化（需真 socket ＋ 半開連線），誠實標註為**手動驗證**：實機跑一次更新 → 等待攔截階段按取消 → 確認 dialog 立即關閉、系統 proxy 已還原。

### 5.3 提交前品質檢查

`dart format lib/ test/`、`flutter analyze`（`No issues found!`）、`flutter test`（`All tests passed!`）。Rust 端 `cargo test`（若新增 Rust 測試）。

## 6. 影響檔案

| 檔案 | 改動 |
|---|---|
| `rust/src/mitm.rs` | L1：`MitmServerGuard` 改持 `watch::Sender`、thread 改 spawn proxy ＋ `block_on` 訊號 ＋ `shutdown_timeout`、drop 有界 join、補 tracing |
| `rust/Cargo.toml` | 必要時給 tokio 補 `time` feature |
| `lib/state/gacha_repository.dart` | L2／L3：新增 `_captureBackstop` 欄位與常數、改 `_runMitm` 等待、改 `cancelCapture`、新增 `_bestEffortStaleProxyCleanup` |
| `test/state/gacha_repository_test.dart` | 新增 3 個 Dart 測試 ＋ Hanging fake |
| `rust/src/mitm.rs`（或 `rust/tests/`） | 新增 smoke test |

> Rust 綁定簽名不變，**不需重跑 frb codegen**。
