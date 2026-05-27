# getGachaLog 過濾與命中後自動停止攔截 設計

> **目的：** 在現有 HTTPS 攔截 PoC 的基礎上，把 MITM handler 從「全攔全推」收斂成「只認 hoyoverse.com 的 getGachaLog 請求」；命中後 Rust 端主動停止整條 capture session，UI 顯示完整 URL（含 authkey）。
>
> **範圍：** 仍只在 Windows 平台、僅本 iteration（PoC 收尾），不涉及 Android、不做 replay、不做卡池資料分析。
>
> **前置：** PoC `2026-05-08-https-capture-poc-design.md` 已驗證攔截通路可行。

## 1. 背景與目標

PoC 目前的 `LogHandler::handle_request` 對所有 HTTPS request 都：
1. 把 `(method, url, host, ts)` 推給 Dart sink
2. `body.collect().await` 印一行 body 預覽 log
3. 重組 request 放行下游

UI 因此會顯示**所有**經過系統 proxy 的請求。本 iteration 要：

- **過濾**：只要 host 為 `*.hoyoverse.com` 且 path 結尾為 `/getGachaLog`，才算命中
- **動作**：命中時取得完整 URL、推給 UI、Rust 端自動停止整條 session
- **UI**：攔截期間不列任何 URL，命中後顯示那一筆完整 URL，並標記「攔截已停止」

## 2. 關鍵決策（已對齊）

| 項目 | 決定 | 理由 |
|---|---|---|
| Host 比對 | `host == "hoyoverse.com" \|\| host.ends_with(".hoyoverse.com")` | 涵蓋 `hk4e-api-os.hoyoverse.com` 等 API 子網域；不涵蓋國服 mihoyo.com |
| Path 比對 | `uri.path().ends_with("/getGachaLog")` | 對應原神實際 path `/event/gacha_info/api/getGachaLog`；簡潔不誤判 |
| Filter 位置 | 寫在 Rust handler，不送到 Dart 過濾 | 集中一處、命中→停止延遲最短、Android 端複用 |
| UI 表現 | 攔截期間不顯示任何 URL；命中時顯示那一筆 | 使用者選擇「只顯示命中的一筆」 |
| Stop 觸發層級 | Rust `handle_response` 第一次命中後 `std::thread::spawn`（含 500ms sleep）呼叫 `stop_capture()` | 實測 hudsucker (`tokio_graceful`) **不等** outbound in-flight；event-driven 等上游 response 到才 schedule stop |
| 重新開始時的 UI | 清除上次命中卡片，回到「等待中」狀態 | 使用者選擇「清除，重新等待下一個命中」|
| 資料模型 | `CapturedRequest` 不新增欄位 | 命中後 sink 只送一筆，「有 event = 命中」已足夠 |
| Body 預覽 log | 移除 | getGachaLog 是 GET 沒 body；非命中流量不應付出 collect overhead |

## 3. 整體架構

```
┌─────────────────────────────────────────────────────────────┐
│  Dart (poc_capture_page.dart)                               │
│  - 開始：清空狀態、訂 stream、訂 onDone                       │
│  - 收到唯一一筆 event → 顯示完整 URL（SelectableText）        │
│  - 收到 stream onDone（Rust 已 drop sink）→ 按鈕回未攔截      │
└─────────────────────────────────────────────────────────────┘
                  ↑ Stream<CapturedRequest>（命中後 close）
┌─────────────────────────────────────────────────────────────┐
│  Rust mitm.rs::LogHandler                                    │
│  handle_request:                                             │
│   - filter: is_target(uri) = host_ok && path_ok              │
│   - 不命中 → 直接 RequestOrResponse::Request(req) 放行        │
│   - 命中 → fired guard → sink.add → 設 pending_stop          │
│  handle_response:                                            │
│   - pending_stop.swap(false) == true → spawn delayed stop    │
└─────────────────────────────────────────────────────────────┘
                  ↓ std::thread::spawn(|| { sleep 500ms; stop_capture() })
┌─────────────────────────────────────────────────────────────┐
│  Rust capture.rs::stop_capture()                              │
│  - 取走 SESSION                                              │
│  - drop _mitm 先：shutdown_tx.send + join hudsucker thread    │
│  - drop _proxy 後：還原系統 proxy + broadcast                  │
│  - hudsucker 結束 → handler 持有的 sink clone drop            │
│    → Dart Stream onDone 觸發                                 │
└─────────────────────────────────────────────────────────────┘
```

**關鍵設計點：**

- **Event-driven stop 而非任意 timeout**：初版設計在 `handle_request` 命中後立即 spawn stop，實測 hudsucker 的 `tokio_graceful` 對 outbound HTTPS in-flight request **不等待**，會在上游 response 到達前就斷 connection。改成 `handle_request` 設 `pending_stop` flag、`handle_response` 第一次觸發後 spawn delayed stop（500ms 給 client socket write 完成）。
- **Stop 必須在 handler 之外的 thread 觸發**：handler 跑在 hudsucker 的 tokio runtime 上，`stop_capture` 內部會 `JoinHandle::join` 那條 hudsucker thread。同步呼叫會 self-join 死鎖。`std::thread::spawn` 把 stop 委派到別的 OS thread。
- **兩個 AtomicBool flag**：`fired` 防止同一條 hoyoverse `getGachaLog` 重複 sink.add；`pending_stop` 防止 `handle_response` 重複 spawn delayed stop。
- **Drop 順序：`_mitm` 先、`_proxy` 後**：先 hudsucker graceful shutdown 等 in-flight 完成（包含 client socket write），再還原系統 proxy + 廣播 SETTINGS_CHANGED。順序顛倒會讓遊戲 webview（CEF/WebView2 走 WinINet）收到 broadcast 時 abort 進行中的 fetch。
- **UI 不主動呼 stop**：依賴 stream `onDone` 偵測 Rust 端已結束，按鈕狀態靠這個 source of truth 收斂；避免兩端各持一份「是否在攔截」造成不一致。

## 4. Filter 細節與資料模型

### 4.1 Filter helper（`mitm.rs` 新增私有函式）

```rust
fn is_target(uri: &hyper::Uri) -> bool {
    let host_ok = uri
        .host()
        .map(|h| h == "hoyoverse.com" || h.ends_with(".hoyoverse.com"))
        .unwrap_or(false);
    let path_ok = uri.path().ends_with("/getGachaLog");
    host_ok && path_ok
}
```

設計選擇：
- **大小寫**：hyper `uri.host()` 已 normalize 為 lowercase，不需手動 `to_ascii_lowercase()`。
- **`ends_with(".hoyoverse.com")` 而非 `.contains("hoyoverse.com")`**：避免 `evil-hoyoverse.com.attacker.example` 這種 host suffix 誤判。
- **Path 用 `ends_with("/getGachaLog")` 而非 segment 切分**：對 `/event/gacha_info/api/getGachaLog` 等價於「最後一段為 getGachaLog」，實作最直接。
- **不檢查 scheme/method**：MITM 透過後 scheme 必為 https；method 規格沒要求過濾。

### 4.2 資料模型 — 完全不變

`CapturedRequest { method, url, host, timestamp_ms }` 既有 4 欄足夠。**不新增 `is_match` 欄位**，因為命中後 sink 只送這一筆，「有 event = 命中」隱含足夠資訊。

### 4.3 Handler 命中後流程

```rust
async fn handle_request(...) -> RequestOrResponse {
    let (parts, body) = req.into_parts();
    if !is_target(&parts.uri) {
        // 不命中：原樣放行，不讀 body、不送 sink、不 log
        return Request::from_parts(parts, body).into();
    }

    // 命中：AtomicBool 保證只觸發一次 sink.add
    if self.fired.swap(true, Ordering::SeqCst) {
        return Request::from_parts(parts, body).into();
    }

    let captured = CapturedRequest { /* method/url/host/timestamp_ms */ };
    tracing::info!(target: "mitm", "hit getGachaLog: {}", captured.url);
    let _ = self.sink.add(captured);

    // 暫不 spawn stop_capture：要等 response 從上游回來，避免 hudsucker 太早 shutdown 切斷 connection。
    self.pending_stop.store(true, Ordering::SeqCst);

    Request::from_parts(parts, body).into()
}

async fn handle_response(...) -> Response<Body> {
    if self.pending_stop.swap(false, Ordering::SeqCst) {
        tracing::info!(target: "mitm",
            "handle_response after hit: status {}, scheduling stop", res.status());

        // 在 mitm runtime 之外觸發 stop，避免 self-join 死鎖。
        // Sleep 500ms 給 hudsucker 把 response body stream 完整寫回 client socket。
        std::thread::spawn(|| {
            std::thread::sleep(std::time::Duration::from_millis(500));
            if let Err(e) = crate::api::capture::stop_capture() {
                tracing::error!(target: "mitm", "auto-stop after match failed: {e}");
            }
        });
    }
    res
}
```

### 4.4 移除既有 body collection

目前 handler 對**每個** request 都 `body.collect().await` 印 body 預覽。新需求下：
- 不命中的 request → 不需要讀 body，**直接原樣放行**，省掉 collect overhead，避免動到下游 streaming
- 命中的 request → body 預覽不再需要（getGachaLog 是 GET）

**決定：** 移除 body collection 邏輯，無論命不命中都不讀 body。原 PoC §7 step 5「印 body 摘要」對純 URL 攔截需求不再必要。

## 5. `LogHandler` 結構與 `capture.rs` 介面

### 5.1 LogHandler 加兩個 atomic flag

```rust
#[derive(Clone)]
struct LogHandler {
    sink: StreamSink<CapturedRequest>,
    // 命中 idempotency：handle_request 第一次命中後 sink.add，後續放行
    fired: Arc<AtomicBool>,
    // event-driven stop：命中時 set，handle_response 第一次觸發後 swap 並 spawn delayed stop
    pending_stop: Arc<AtomicBool>,
}
```

設計要點：
- **`Arc<AtomicBool>`**：`HttpHandler` trait 要求 `Clone`（hudsucker 內部會 clone handler 給每個 connection）。`Arc` 確保所有 clone 共享同一個 flag。直接用 `AtomicBool` clone 會各自獨立。
- **兩個 flag 各司其職**：`fired` 守護 sink.add（避免重複命中 race）；`pending_stop` 守護 spawn delayed stop（避免兩個 handle_response 並發各 spawn 一次）。合併成單一 flag 會混淆兩個 idempotency 邊界。
- **不放 `static` 全域**：handler 生命週期已綁 session（session drop → handler drop → flag 隨之回收），放 static 反而要處理「下一次 start 要 reset」這種額外狀態。
- **`SeqCst` 而非 `Relaxed`**：PoC 不在乎這點 overhead；強一致最不容易被未來改動咬到。

### 5.2 `capture.rs` 介面 — 不新增公開 API

`stop_capture() -> Result<()>` 既有簽章已 thread-safe（`Mutex<Option<Session>>`）。Rust handler 內 `std::thread::spawn(|| crate::api::capture::stop_capture())` 直接呼叫即可。

**capture.rs 邏輯完全不改，只是新增了一個呼叫者**。

### 5.3 `mitm::start` 簽章不變

`mitm::start(addr, cert_pem, key_pem, sink)` 內部建立 handler 時加兩個 flag：

```rust
let handler = LogHandler {
    sink,
    fired: Arc::new(AtomicBool::new(false)),
    pending_stop: Arc::new(AtomicBool::new(false)),
};
```

### 5.4 Drop 順序與 stream onDone 的關係

`Session` 欄位順序（**`_mitm` 在前、`_proxy` 在後**）：
```rust
struct Session {
    _mitm:  mitm::MitmServerGuard,    // 先 drop → graceful shutdown 等 in-flight 寫回 client
    _proxy: sys_proxy::SysProxyGuard, // 後 drop → 還原系統 proxy + 廣播 SETTINGS_CHANGED
}
```

順序設計理由：
- 遊戲內 webview（CEF / WebView2）監聽 Windows `WM_SETTINGSCHANGE`。`InternetSetOptionW(INTERNET_OPTION_SETTINGS_CHANGED)` 廣播會讓正在進行的 fetch 被 abort。
- 因此必須**先**等 hudsucker 完成 in-flight 的 client socket write（response body 寫回原神 webview），**再**還原系統 proxy 並廣播。
- 副作用：在 `_mitm` shutdown 與 `_proxy` 還原之間（< 1 秒），其他 app 仍透過已關閉 listener 的 hudsucker，新連線會 fail。對 PoC 可接受（命中是一次性事件）。

handler 觸發 stop 後的時序：
1. `SESSION.lock().take()` 拿走 `Session`
2. `_mitm` drop → `shutdown_tx.send()` → hudsucker graceful shutdown
   - 注意：`tokio_graceful` 對 outbound HTTP client 的 in-flight request **不等待**；本設計靠 `handle_response` + 500ms sleep 確保 client write 完成後才走到這步
3. `_proxy` drop → 系統 proxy 立刻還原 + broadcast
4. handler clone 持有的 `sink` 隨 hudsucker runtime 一起 drop
5. **最後一個 sink clone drop → Dart `Stream.onDone` 觸發**

UI 靠 `onDone` 收斂按鈕狀態，不需要 timer 或輪詢。

### 5.5 死鎖驗證

`stop_capture` 跑在 `std::thread::spawn` 出來的 OS thread A，handler 跑在 hudsucker tokio runtime worker thread B：
- B（執行 `handle_response`）spawn OS thread C
- C sleep 500ms 後呼叫 `stop_capture`
- C 拿 `SESSION` mutex → drop `Session` → drop `MitmServerGuard` → `shutdown_tx.send(())` → `JoinHandle::join()` 等 hudsucker thread 結束
- B 在 sleep 結束前已 return res、hudsucker 把 response 寫回 client → connection task 完成 → B 進 idle
- shutdown_rx 收到信號後 graceful shutdown → tokio runtime 退出 → C 上的 join 返回 ✅

只要 spawn 不是 inline 同步呼叫，沒有死鎖風險。

## 6. Dart UI 變更與 stream lifecycle

### 6.1 State 變更

```dart
class _PocCapturePageState extends State<PocCapturePage> {
  bool _capturing = false;
  String? _error;
  rust_capture.CapturedRequest? _hit;          // 命中那一筆，null = 尚未命中
  StreamSubscription<rust_capture.CapturedRequest>? _sub;
}
```

`_urls: List<...>` → `_hit: CapturedRequest?`：Rust 端只送一筆。不再需要計數 `Text('共 N 筆')`。

### 6.2 `_toggle` 流程

```dart
Future<void> _toggle() async {
  setState(() => _error = null);
  try {
    if (_capturing) {
      // 命中前手動取消
      await _sub?.cancel();
      _sub = null;
      await rust_capture.stopCapture();
      if (!mounted) return;
      setState(() => _capturing = false);
    } else {
      // 重新開始：清空上次命中
      setState(() {
        _hit = null;
        _capturing = true;
      });
      final stream = rust_capture.startCapture();
      _sub = stream.listen(
        (event) {
          if (!mounted) return;
          setState(() => _hit = event);
          // 不在這裡呼 stopCapture：Rust 端命中後會自己停，
          // 等 onDone 收尾即可，避免兩端各喊一次 stop。
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _error = '$e');
        },
        onDone: () {
          // Rust 端 sink drop（命中後自動停 / 或手動停）
          if (!mounted) return;
          setState(() {
            _capturing = false;
            _sub = null;
          });
        },
      );
    }
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _error = '$e';
      _capturing = false;
    });
  }
}
```

**關鍵設計點：**
- **單一 source of truth**：`_capturing = false` 只在兩處設：(1) 使用者手動取消、(2) `onDone`。命中時不在 listener 內提早改 false，避免 onDone 還沒到時 UI 就誤顯示「已停止」。
- **不在 Dart 側觸發 stop**：Rust 端命中後會 `std::thread::spawn(stop)`；Dart 只是被動觀察 stream 結束。少一次無謂呼叫。
- **手動取消路徑保留**：使用者點「停止攔截」（命中前）仍可主動停，UX 必要。
- **重新開始時 `_hit = null`**：對應「清除，重新等待下一個命中」。

### 6.3 UI 三種顯示狀態

| 狀態 | `_capturing` | `_hit` | 顯示 |
|---|---|---|---|
| 初始 / 未啟動 | false | null | 「尚未開始攔截」中央提示，按鈕「開始攔截」 |
| 攔截中、未命中 | true | null | `CircularProgressIndicator` + 「等待 getGachaLog 請求…」，按鈕「停止攔截」 |
| 已命中 | false | 非 null | 完整 URL 卡片 + 「✅ 已取得 getGachaLog URL，攔截已停止」，按鈕「開始攔截」 |

命中卡片：

```dart
Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('✅ 已取得 getGachaLog URL，攔截已停止',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Host: ${_hit!.host}'),
        const SizedBox(height: 8),
        SelectableText(
          _hit!.url,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ],
    ),
  ),
)
```

`SelectableText` 是刻意的：PoC 驗收要從 UI copy URL 出來貼到瀏覽器手動測試 replay。

### 6.4 Error 路徑

- `startCapture()` throw（CA 安裝拒絕、port 佔用等）→ catch block 設 `_error`、`_capturing = false`
- Stream `onError` → 設 `_error`，但**不**改 `_capturing`（onDone 會接著來）
- 紅色文字直接放在按鈕下方，與既有 PoC 風格一致；不顯示 toast / dialog

## 7. 手動驗收步驟

依序跑完，全部 PASS 代表此 iteration 完成：

1. `flutter run -d windows --release` 啟動 → 看到「尚未開始攔截」中央提示、「開始攔截」按鈕
2. 點「開始攔截」→ 顯示 `CircularProgressIndicator` + 「等待 getGachaLog 請求…」，按鈕變「停止攔截」
3. 開瀏覽器打 `https://example.com` → **UI 完全無變化**（驗證非命中流量被過濾掉）
4. 開瀏覽器打 `https://www.hoyoverse.com` → **UI 完全無變化**（驗證 host 對但 path 不對也不命中）
5. 開原神 → 進卡池 → 點「歷史紀錄」→ UI 立刻切換成綠色「✅ 已取得 getGachaLog URL，攔截已停止」+ 完整 URL（含 `authkey=...`），按鈕回「開始攔截」
6. 開「Windows 設定 → 網路 → Proxy」→ 確認系統 proxy 已自動關閉
7. 從 UI 上選取（`SelectableText`）那條 URL → 貼到瀏覽器 → 應能取得 gacha log JSON（驗證 URL 完整可用）
8. 再點「開始攔截」→ 命中卡片消失、回到「等待中」狀態 → 重新進原神卡池歷史 → 可再次命中

**負向驗收：**

9. 點「開始攔截」→ 在命中發生前手動點「停止攔截」→ 進度提示消失、按鈕回「開始攔截」、proxy 還原 → 表示手動停止路徑仍正常

## 8. Out of Scope

| 項目 | 為什麼不做 |
|---|---|
| 命中後自動 replay 那條 URL 取卡池資料 | 是下一個 iteration 的事；本 iteration 只驗 filter + auto-stop |
| 顯示命中前看到的 hoyoverse 流量數量 | 需求是「不顯示」即不顯示，不偷加計數 |
| Body 預覽 / 顯示 | getGachaLog 是 GET 沒 body；同時移除既有 handler 對所有 request 的 `body.collect()` overhead |
| 國服 mihoyo.com filter | 已選擇「只比對 *.hoyoverse.com」 |
| 命中歷史紀錄（多次命中保留 list） | 已選擇「每次重新等待」 |
| 命中後額外的 telemetry / 持久化 | tracing log 印到 stdout 已足夠 PoC |
| 單元測試 `is_target` 純函式 | host/path 比對極簡單，手動驗收 step 3、4、5 已完整覆蓋三種情境（host 不對、path 不對、都對） |

## 9. 已知風險

| 風險 | 嚴重度 | 處理 |
|---|---|---|
| `std::thread::spawn(stop)` 在 app 即將退出時被 join 不到 | 低 | spawn 出來的 thread 跑完就消失；即使 app 在 stop 完成前被 kill，下一次啟動由 `cleanupStaleProxy` 兜底 |
| 同一連線在 stop 完成前又進來第二筆 hoyoverse `getGachaLog` | 低 | `fired.swap` 保證只送一筆 sink；`pending_stop.swap` 保證只 spawn 一次 stop |
| 原神某次更新後改 path（如改成 `/getGachaLogV2`） | 中 | `ends_with("/getGachaLog")` 不會誤命中 V2，但也攔不到。手動驗收 step 5 會立即發現；屆時調整 filter 字串 |
| `pending_stop` 觸發可能由非命中那條 response（同時有別的 in-flight）觸發 | 低 | 500ms sleep 給 client write buffer；命中那條 response 的 RTT 遠小於 500ms，多半也已寫回 |
| 命中 URL 超長（含 authkey）超出 UI 顯示寬度 | 低 | `SelectableText` 自動 wrap；卡片在 `Padding` 內可垂直延伸 |
| `Stream.onDone` 因 500ms delay 延遲約 0.5–1 秒 | 低 | 此期間 UI 已顯示「✅ 已取得 URL」綠卡，但按鈕仍是「停止攔截」。使用者誤點 stop — `stop_capture` 是 idempotent，無害 |
| `_mitm` shutdown 與 `_proxy` 還原之間，其他 app 新連線會 fail（< 1 秒） | 低 | 命中是一次性事件、視窗極短；正式產品階段若需要可改用 process-specific proxy 規避全系統影響 |
