# MITM 捕獲拆除死鎖與取消無反應的防禦縱深修復 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal：** 讓 MITM 捕獲在任何卡死情況下都能在有界時間內被取消、關閉 dialog，且系統 proxy 必定還原。

**Architecture：** 三層防禦。L1（Rust）把 MITM runtime 拆除從無界 `h.join()` 改成 `shutdown_timeout(2s)` 強制有界；L2（Dart `cancelCapture`）為取消加上逾時逃生口與 best-effort proxy 還原；L3（Dart `_runMitm`）用 `Future.any([result, backstop])` 確保等待一定能被解開。Rust 綁定簽名不變，不需重跑 frb codegen。

**Tech Stack：** Flutter／Dart（Riverpod Notifier、`package:logging`、`flutter_test` ＋ `MockClient`）、Rust（tokio multi-thread runtime、`tokio::sync::watch`、hudsucker 0.24 graceful shutdown）。

**前置：** 分支 `fix/mitm-capture-teardown-deadlock` 已建立並已提交 spec。

---

## 檔案結構

| 檔案 | 責任 | 動作 |
|---|---|---|
| `lib/state/gacha_repository.dart` | 更新狀態機；L2／L3 兜底邏輯所在 | Modify |
| `test/state/gacha_repository_test.dart` | repository 單元測試 | Modify（新增 fake ＋ 2 個測試） |
| `rust/src/mitm.rs` | MITM proxy 啟停與有界拆除 | Modify |

> `rust/Cargo.toml` **不需**改動：新結構只用到 `tokio::sync::watch`（`sync` feature 已開）與 `Runtime::shutdown_timeout`（無需 `time` feature），未直接使用 `tokio::time`。以 `cargo check` 驗證即可。

---

## Task 1：Dart L2／L3 — 取消逃生口與等待 backstop（TDD）

**Files:**
- Modify: `lib/state/gacha_repository.dart`（import；`_runMitm` 約 309-322；fields 約 437-447；`cancelCapture` 約 455-461；測試輔助方法區約 1023-1027）
- Test: `test/state/gacha_repository_test.dart`（頂層 fake class 區約 21-40；`main()` 內新增測試）

- [ ] **Step 1：寫兩個失敗測試 ＋ 兩個 fake**

在 `test/state/gacha_repository_test.dart` 頂層（`_CountingCapture` 之後、`void main()` 之前）新增兩個 fake：

```dart
/// result 永不 complete、cancel 立即回 → 模擬「onDone 不觸發但取消正常」的情況。
/// 唯一能解開 _runMitm 等待的途徑就是 backstop。
class _HangingCapture implements GachaCapture {
  @override
  CaptureSession start() => CaptureSession(
    result: Completer<String?>().future, // 永不 complete
    cancel: () async {}, // 立即回
  );
}

/// cancel 回一個永不 complete 的 Future → 模擬 Rust stopCapture 卡死（L1 失效）的最壞情況。
class _HangingCancelCapture implements GachaCapture {
  @override
  CaptureSession start() => CaptureSession(
    result: Completer<String?>().future,
    cancel: () => Completer<void>().future, // 永不回
  );
}
```

在 `main()` 內（例如緊接 `clearProgress 把 progress 重設為 null` 測試之後）新增兩個測試：

```dart
test(
  'cancelCapture：result 永不 complete 但 cancel 正常 → backstop 解開等待、progress 清空',
  () async {
    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        gachaCaptureProvider.overrideWithValue(_HangingCapture()),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50)); // bootstrap

    final notifier = container.read(gachaRepositoryProvider.notifier);
    final updateFut = notifier.update();
    await Future<void>.delayed(const Duration(milliseconds: 30)); // 進入 WaitingForCapture

    expect(
      container.read(gachaRepositoryProvider).progress,
      isA<WaitingForCapture>(),
      reason: '無快取 URL ＋ 無 active UID → 應進入 MITM 等待階段',
    );

    await notifier.cancelCapture();
    await updateFut;

    expect(
      container.read(gachaRepositoryProvider).progress,
      isNull,
      reason: 'backstop 應解開永不 complete 的 result，使 _runMitm 回 null → clearProgress',
    );
  },
);

test(
  'cancelCapture：cancel 永不回 → 逾時分支清空 progress 並 severe-log',
  () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    addTearDown(() => Logger.root.clearListeners());

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        gachaCaptureProvider.overrideWithValue(_HangingCancelCapture()),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50)); // bootstrap

    final notifier = container.read(gachaRepositoryProvider.notifier);
    // 縮短逾時，避免真實掛鐘等待；只 await 完成、不做時間斷言 → 不 flaky。
    notifier.debugSetCancelTeardownTimeout(const Duration(milliseconds: 20));

    final updateFut = notifier.update();
    await Future<void>.delayed(const Duration(milliseconds: 30)); // 進入 WaitingForCapture
    expect(
      container.read(gachaRepositoryProvider).progress,
      isA<WaitingForCapture>(),
    );

    await notifier.cancelCapture();
    await updateFut;

    expect(
      container.read(gachaRepositoryProvider).progress,
      isNull,
      reason: 'cancel 卡死時應走逾時分支、用 backstop 解卡 → progress 清空',
    );
    expect(
      records.any(
        (r) =>
            r.loggerName == 'gacha.repo' &&
            r.level == Level.SEVERE &&
            r.message.contains('stopCapture exceeded'),
      ),
      isTrue,
      reason: '逾時應產生 severe log',
    );
  },
);
```

- [ ] **Step 2：跑測試確認失敗（RED）**

Run：`flutter test test/state/gacha_repository_test.dart`
Expected：**編譯失敗** — `The method 'debugSetCancelTeardownTimeout' isn't defined for the type 'GachaRepository'`（第二個測試引用了尚未實作的方法，整個檔案無法編譯）。這即是乾淨的 RED。

- [ ] **Step 3：加入 rust_capture import**

在 `lib/state/gacha_repository.dart`，於 `import '...services/gacha_storage.dart';`（約第 19 行）之後插入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart'
    as rust_capture;
```

- [ ] **Step 4：新增欄位**

在 `lib/state/gacha_repository.dart` 的私有欄位區，緊接 `_activeCancellable` 宣告（約第 447 行）之後新增：

```dart
  /// 取消／逾時時用來強制解開 [_runMitm] 等待的 backstop completer。
  Completer<String?>? _captureBackstop;

  /// `cancelCapture` 等待 Rust MITM 拆除回應的上限（比 L1 的 2 秒寬鬆）。
  Duration _cancelTeardownTimeout = const Duration(seconds: 8);
```

- [ ] **Step 5：改寫 `_runMitm`（L3 backstop）**

把 `_runMitm`（約 309-322）整段換成：

```dart
  /// 啟動 MITM 捕獲會話並等候 URL；[isFallback] 為 auth 過期後的二次捕獲。
  ///
  /// 等待用 `Future.any([session.result, backstop])`：正常經 onDone 由 `result`
  /// 回；若 onDone 失靈（Rust 拆除未 drop sink），則由 [cancelCapture] 完成的
  /// [_captureBackstop] 解開，確保等待一定有界、不會永久卡在 `WaitingForCapture`。
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

- [ ] **Step 6：改寫 `cancelCapture` ＋ 新增 best-effort proxy 還原（L2）**

把 `cancelCapture`（約 455-461）整段換成：

```dart
  /// 取消正在進行的 MITM 捕獲會話。
  ///
  /// 有界：最多等 [_cancelTeardownTimeout] 讓 Rust 拆除回應；逾時則 severe-log、
  /// best-effort 還原系統 proxy，並一律完成 [_captureBackstop] 解開 [_runMitm] 的
  /// 等待（即使 onDone 未觸發），確保 dialog 一定能關閉。
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
    final backstop = _captureBackstop;
    if (backstop != null && !backstop.isCompleted) {
      backstop.complete(null);
    }
  }

  /// best-effort 還原殘留的系統 proxy（取消逾時時呼叫），失敗只 warn-log，不拋。
  Future<void> _bestEffortStaleProxyCleanup() async {
    try {
      final cleared = await rust_capture.cleanupStaleProxy();
      _log.info('stale proxy cleanup after cancel timeout: cleared=$cleared');
    } catch (e, st) {
      _log.warning('stale proxy cleanup failed', e, st);
    }
  }
```

- [ ] **Step 7：新增測試用逾時 setter**

在 `lib/state/gacha_repository.dart` 的 `debugSetProgress`（約 1023-1027）之後新增：

```dart
  /// 測試用：縮短取消拆除逾時，避免真實掛鐘等待。生產勿用。
  @visibleForTesting
  void debugSetCancelTeardownTimeout(Duration timeout) {
    _cancelTeardownTimeout = timeout;
  }
```

- [ ] **Step 8：跑測試確認通過（GREEN）**

Run：`flutter test test/state/gacha_repository_test.dart`
Expected：`All tests passed!`（含兩個新測試）。

> 若第一個新測試卡住不結束：代表 backstop 沒接上 `_runMitm` 的 `Future.any`，回頭檢查 Step 5。

- [ ] **Step 9：品質檢查**

Run：`dart format lib/ test/`
Run：`flutter analyze`
Expected：`No issues found!`

> 若 `flutter analyze` 報 import 排序（`directives_ordering`），把 Step 3 的 import 調到正確字母序位置（`services/` 之後、`state/` 之前）。

- [ ] **Step 10：跑完整測試套件**

Run：`flutter test`
Expected：`All tests passed!`

- [ ] **Step 11：Commit**

```bash
git add lib/state/gacha_repository.dart test/state/gacha_repository_test.dart
git commit -m "fix(gacha): make capture cancel bounded and always unblock the wait

Add a backstop completer to _runMitm's wait (Future.any) and a timeout +
best-effort stale-proxy cleanup to cancelCapture, so the waiting-for-capture
dialog can always be cancelled and closed even when the MITM stream never
emits onDone.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2：Rust L1 — MITM runtime 有界拆除

**Files:**
- Modify: `rust/src/mitm.rs`（imports 約 1-15；`MitmServerGuard` ＋ `Drop` 約 17-31；`start()` 約 108-172）

- [ ] **Step 1：換 import**

在 `rust/src/mitm.rs`，把 `use tokio::sync::oneshot;`（約第 15 行）換成：

```rust
use std::time::Duration;
use tokio::sync::watch;
```

- [ ] **Step 2：改寫 `MitmServerGuard` 與 `Drop`**

把 `MitmServerGuard` 結構與其 `Drop`（約 17-31）整段換成：

```rust
pub struct MitmServerGuard {
    // 拆除訊號：drop 時 send(true)，同時觸發 hudsucker graceful shutdown 與 thread block_on。
    shutdown_tx: Option<watch::Sender<bool>>,
    handle: Option<std::thread::JoinHandle<()>>,
}

impl Drop for MitmServerGuard {
    fn drop(&mut self) {
        if let Some(tx) = self.shutdown_tx.take() {
            let _ = tx.send(true);
        }
        // join 現在有界：thread 收到訊號後以 shutdown_timeout(2s) 強制結束 runtime。
        if let Some(h) = self.handle.take() {
            tracing::info!(target: "mitm", "joining mitm runtime thread");
            let _ = h.join();
            tracing::info!(target: "mitm", "mitm runtime thread joined");
        }
    }
}
```

- [ ] **Step 3：改寫 `start()` 的 channel 與 thread 主體**

把 `start()` 內從 `let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();`（約第 136 行）到函式結尾 `Ok(MitmServerGuard { ... })`（約第 171 行）整段換成：

```rust
    // 單一拆除訊號：初值 false，drop 時 send(true)。graceful shutdown future 與
    // thread 的 block_on 各持一個 receiver clone，共用此訊號 → 一次觸發兩邊。
    let (shutdown_tx, shutdown_rx) = watch::channel(false);
    let mut graceful_rx = shutdown_rx.clone();
    let mut block_rx = shutdown_rx;

    let handler = LogHandler {
        sink,
        fired: Arc::new(AtomicBool::new(false)),
        pending_stop: Arc::new(AtomicBool::new(false)),
    };

    let handle = std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("build tokio rt for mitm");

        // proxy 當背景 task 跑：收到訊號 → hudsucker graceful shutdown 停止 accept、排空 in-flight。
        rt.spawn(async move {
            let proxy = Proxy::builder()
                .with_addr(addr)
                .with_ca(ca)
                .with_http_connector(https_connector)
                .with_http_handler(handler)
                .with_graceful_shutdown(async move {
                    let _ = graceful_rx.wait_for(|stop| *stop).await;
                })
                .build()
                .expect("hudsucker proxy build failed");

            if let Err(e) = proxy.start().await {
                tracing::error!(target: "mitm", "mitm proxy stopped: {e}");
            }
        });

        // block 在拆除訊號上；收到後強制有界關閉 runtime。
        rt.block_on(async move {
            let _ = block_rx.wait_for(|stop| *stop).await;
        });
        tracing::info!(target: "mitm", "mitm teardown requested, forcing runtime shutdown");
        // 給 graceful drain（含命中的 gacha response）最多 2 秒；逾時強制中斷殘餘連線、結束 runtime。
        // 這讓 thread 必定有界結束 → drop 的 h.join() 不會無限卡死。
        rt.shutdown_timeout(Duration::from_secs(2));
        tracing::info!(target: "mitm", "mitm runtime shut down");
    });

    Ok(MitmServerGuard {
        shutdown_tx: Some(shutdown_tx),
        handle: Some(handle),
    })
```

> 實作注意：若 borrow checker 對 `graceful_rx` / `block_rx` 的可變借用有意見，在各自的 `async move` 區塊內 `let mut rx = rx;` 重新綁定即可。`watch::Receiver::wait_for` 需 tokio ≥ 1.27（`tokio = "1"` 解析為最新 1.x，已滿足）。

- [ ] **Step 4：編譯驗證**

Run（在 `rust/` 目錄，需 Rust toolchain）：`cargo check`
Expected：編譯通過、無 error（可能有既存 warning，但不得有新 error）。

> 若環境無獨立 cargo，改用 `flutter build windows --debug` 觸發 cargokit 編譯 Rust。

- [ ] **Step 5：Commit**

```bash
git add rust/src/mitm.rs
git commit -m "fix(mitm): bound the proxy teardown so cancel never deadlocks

Run the hudsucker proxy as a spawned task and drive shutdown through a
shared watch signal, then force-abort the runtime with shutdown_timeout(2s).
The guard's join is now bounded, so stop_capture always returns, the listen
port is freed, and the system proxy is always restored even when a game
keep-alive connection refuses to drain.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3：端對端手動驗證

> Rust MITM 拆除涉及真 socket、cert 與 `StreamSink`，難以穩定自動化單元測試；以實機驗證收尾。

**Files:** 無（純驗證）

- [ ] **Step 1：建置並啟動 App**

Run：`flutter run -d windows`（或既有的 run 腳本）。

- [ ] **Step 2：驗證取消逃生口（核心症狀）**

1. 點「更新資料」→ 出現「等待攔截」dialog。
2. **不要**開遊戲祈願頁，直接按「取消」。
3. 預期：dialog **立即**（約 2 秒內）關閉，progress 清空。
4. 開瀏覽器確認網路正常（系統 proxy 已還原，未卡在 `127.0.0.1:18080`）。
5. 匯出 log 確認有 `mitm teardown requested...` → `mitm runtime shut down` → `mitm runtime thread joined` 序列。

- [ ] **Step 3：驗證 happy path 未壞**

1. 點「更新資料」→「等待攔截」。
2. 開原神 → 祈願 → 歷史記錄。
3. 預期：App 正常擷取到 URL、進入抓取階段、完成更新（與修改前行為一致）。

- [ ] **Step 4：（可選）壓力驗證取消後可立即再更新**

取消後立刻再按一次「更新資料」→ 預期能正常再次進入「等待攔截」（port 已釋放、無 `capture already running` 錯誤）。

---

## Self-Review（撰寫者已核對）

**Spec coverage：**
- L1 Rust 有界拆除 → Task 2 ✓
- L2 Dart 取消逃生口（timeout ＋ best-effort proxy 還原）→ Task 1 Step 6 ✓
- L3 Dart 等待 backstop → Task 1 Step 5 ✓
- 測試（backstop 解卡、逾時分支、Rust 驗證、手動驗證）→ Task 1 Step 1／Task 2 Step 4／Task 3 ✓
- 非目標（不碰 FetchingBanner 取消、不做自動逾時、不重排 drop 順序）→ 計畫未涉入 ✓

**Placeholder scan：** 無 TBD／TODO；每個 code step 皆為完整可貼上的程式碼。

**Type consistency：** `_captureBackstop`（`Completer<String?>?`）、`_cancelTeardownTimeout`（`Duration`）、`debugSetCancelTeardownTimeout`、`_bestEffortStaleProxyCleanup`、`rust_capture.cleanupStaleProxy()`、`watch::Sender<bool>` 全程一致；Rust 訊號 predicate `|stop| *stop` 兩處一致。
