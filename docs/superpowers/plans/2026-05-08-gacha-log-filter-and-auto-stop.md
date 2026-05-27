# getGachaLog 過濾與命中後自動停止攔截 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 MITM handler 從「全攔全推」收斂成「只認 `*.hoyoverse.com` 的 `getGachaLog` 請求」；命中時 Rust 端自動停止整條 capture session、UI 顯示完整 URL。

**Architecture:** 改動集中在 `rust/src/mitm.rs`（加 `is_target` filter、`LogHandler` 新增 `Arc<AtomicBool>` fired guard、handle_request 重寫成 filter-first；移除 body collection）與 `lib/pages/poc_capture_page.dart`（state 從 `List<CapturedRequest>` 改成單值 `CapturedRequest?`、新增 stream `onDone` 觀察 Rust 自動停止）。`rust/src/api/capture.rs` 邏輯完全不動，handler 用 `std::thread::spawn(|| capture::stop_capture())` 委派至 OS thread 觸發 stop，避免 self-join 死鎖。FRB 公開 API 簽章未變，不需 codegen。

**Tech Stack:** Rust（hudsucker, tokio, std::sync::atomic）、Flutter / Dart、`flutter_rust_bridge` v2。

**Spec 來源:** `docs/superpowers/specs/2026-05-08-gacha-log-filter-and-auto-stop-design.md`

---

## 通用約定

- **每個 Task 結束做一個原子 commit**（imperative 英語短句，跟 repo 風格一致：`Filter ...`、`Stream ...`）
- **PoC 階段不寫單元測試**（spec §8 已決議：`is_target` 純函式由手動驗收 step 3、4、5 覆蓋三種情境）
- **不更動 FRB 公開 API**（capture.rs 的 `start_capture` / `stop_capture` / `cleanup_stale_proxy` 簽章不變），所以不需要 `flutter_rust_bridge_codegen generate`
- **Drop 順序保持** `Session { _proxy, _mitm }`（既有，不動）

---

## 檔案結構（最終樣貌）

| 路徑 | 角色 | 任務 |
|---|---|---|
| `rust/src/mitm.rs` | filter + auto-stop + 移除 body collection | T1 |
| `rust/Cargo.toml` | 移除不再使用的 `http-body-util` dep | T1 |
| `lib/pages/poc_capture_page.dart` | state 改單值、UI 三狀態、onDone 處理 | T2 |
| `rust/src/api/capture.rs` | **不動** | — |
| `rust/src/ca.rs` / `cert_store.rs` / `sys_proxy.rs` | **不動** | — |
| `lib/main.dart` | **不動** | — |

---

## Task 1：Rust mitm.rs 加 filter、fired guard、auto-stop；移除 body collection

**Files:**
- Modify: `rust/src/mitm.rs`（整檔重寫）
- Modify: `rust/Cargo.toml`（移除 `http-body-util` dependency）

- [ ] **Step 1.1：用以下完整內容覆寫 `rust/src/mitm.rs`**

```rust
use std::net::SocketAddr;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use anyhow::{Context, Result};
use hudsucker::{
    Proxy,
    Body, HttpContext, HttpHandler, RequestOrResponse,
    certificate_authority::RcgenAuthority,
    hyper::{Request, Response, Uri},
    rcgen::{Issuer, KeyPair},
    rustls::{ClientConfig, crypto::aws_lc_rs},
};
use hyper_rustls::{ConfigBuilderExt, HttpsConnectorBuilder};
use tokio::sync::oneshot;
use crate::api::capture::CapturedRequest;
use crate::frb_generated::StreamSink;

pub struct MitmServerGuard {
    shutdown_tx: Option<oneshot::Sender<()>>,
    handle: Option<std::thread::JoinHandle<()>>,
}

impl Drop for MitmServerGuard {
    fn drop(&mut self) {
        if let Some(tx) = self.shutdown_tx.take() {
            let _ = tx.send(());
        }
        if let Some(h) = self.handle.take() {
            let _ = h.join();
        }
    }
}

fn is_target(uri: &Uri) -> bool {
    let host_ok = uri
        .host()
        .map(|h| h == "hoyoverse.com" || h.ends_with(".hoyoverse.com"))
        .unwrap_or(false);
    let path_ok = uri.path().ends_with("/getGachaLog");
    host_ok && path_ok
}

#[derive(Clone)]
struct LogHandler {
    sink: StreamSink<CapturedRequest>,
    fired: Arc<AtomicBool>,
}

impl HttpHandler for LogHandler {
    async fn handle_request(
        &mut self,
        _ctx: &HttpContext,
        req: Request<Body>,
    ) -> RequestOrResponse {
        let (parts, body) = req.into_parts();

        if !is_target(&parts.uri) {
            return Request::from_parts(parts, body).into();
        }

        if self.fired.swap(true, Ordering::SeqCst) {
            return Request::from_parts(parts, body).into();
        }

        let method = parts.method.to_string();
        let url = parts.uri.to_string();
        let host = parts.uri.host().unwrap_or("").to_string();
        let timestamp_ms = chrono::Utc::now().timestamp_millis();

        tracing::info!(target: "mitm", "hit getGachaLog: {} {}", method, url);

        let _ = self.sink.add(CapturedRequest {
            method,
            url,
            host,
            timestamp_ms,
        });

        // 在 mitm runtime 之外觸發 stop，避免 self-join 死鎖
        std::thread::spawn(|| {
            if let Err(e) = crate::api::capture::stop_capture() {
                tracing::error!("auto-stop after match failed: {e}");
            }
        });

        Request::from_parts(parts, body).into()
    }

    async fn handle_response(
        &mut self,
        _ctx: &HttpContext,
        res: Response<Body>,
    ) -> Response<Body> {
        res
    }
}

pub fn start(
    addr: SocketAddr,
    cert_pem: &str,
    key_pem: &str,
    sink: StreamSink<CapturedRequest>,
) -> Result<MitmServerGuard> {
    let key_pair = KeyPair::from_pem(key_pem).context("rcgen KeyPair::from_pem failed")?;
    let issuer = Issuer::from_ca_cert_pem(cert_pem, key_pair)
        .context("Issuer::from_ca_cert_pem failed")?;

    let provider = aws_lc_rs::default_provider();
    let ca = RcgenAuthority::new(issuer, 1_000, provider);

    let tls_config = ClientConfig::builder_with_provider(Arc::new(aws_lc_rs::default_provider()))
        .with_safe_default_protocol_versions()
        .context("rustls ClientConfig: no supported protocol versions")?
        .with_webpki_roots()
        .with_no_client_auth();

    let https_connector = HttpsConnectorBuilder::new()
        .with_tls_config(tls_config)
        .https_or_http()
        .enable_http1()
        .enable_http2()
        .build();

    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();

    let handler = LogHandler {
        sink,
        fired: Arc::new(AtomicBool::new(false)),
    };

    let handle = std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("build tokio rt for mitm");

        rt.block_on(async move {
            let proxy = Proxy::builder()
                .with_addr(addr)
                .with_ca(ca)
                .with_http_connector(https_connector)
                .with_http_handler(handler)
                .with_graceful_shutdown(async move {
                    let _ = shutdown_rx.await;
                })
                .build()
                .expect("hudsucker proxy build failed");

            if let Err(e) = proxy.start().await {
                tracing::error!("mitm proxy stopped: {e}");
            }
        });
    });

    Ok(MitmServerGuard {
        shutdown_tx: Some(shutdown_tx),
        handle: Some(handle),
    })
}
```

關鍵差異對照（vs 既有版本）：
- 新增 `use std::sync::atomic::{AtomicBool, Ordering};`
- 新增 `use ... hyper::{Request, Response, Uri}`（Uri 用於 `is_target`）
- **移除** `use http_body_util::BodyExt;`
- 新增 `is_target(uri: &Uri) -> bool` 私有 helper
- `LogHandler` 加 `fired: Arc<AtomicBool>` 欄位
- `handle_request` 重寫：filter-first → fired guard → sink.add → spawn stop；不再 `body.collect().await`
- `start()` 內 `LogHandler` 建構加 `fired: Arc::new(AtomicBool::new(false))`

- [ ] **Step 1.2：用以下完整內容覆寫 `rust/Cargo.toml`**

```toml
[package]
name = "genshin_capture_core"
version = "0.1.0"
edition = "2021"
publish = false

[lib]
crate-type = ["cdylib", "staticlib"]

[dependencies]
flutter_rust_bridge = "=2.12.0"
anyhow = "1"
chrono = "0.4"
once_cell = "1"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
tokio = { version = "1", features = ["rt-multi-thread", "macros", "sync", "net"] }
hudsucker = { version = "0.24", default-features = false, features = ["decoder", "rcgen-ca", "rustls-client", "http2"] }
hyper-rustls = { version = "0.27", default-features = false, features = ["http1", "http2", "tls12", "webpki-tokio"] }
rcgen = "0.14"
pem = "3.0.6"
sha1 = "0.10"
hex = "0.4"

[dev-dependencies]
tempfile = "3.27.0"

[target.'cfg(windows)'.dependencies]
windows = { version = "0.62", features = [
    "Win32_Security_Cryptography",
    "Win32_Networking_WinInet",
    "Win32_System_Registry",
    "Win32_Foundation",
] }
```

唯一差異：移除第 20 行 `http-body-util = "0.1"`。

- [ ] **Step 1.3：在 `rust/` 目錄編譯**

Run: `cargo build`
Expected：
- 編譯成功
- 無 unused import 警告（`BodyExt` 已連同 import 一併移除）
- 無 unused dependency 提示
- 產出 `target/debug/genshin_capture_core.dll`

如果出現 `unused import` 警告或 trait bound 錯誤（hudsucker 0.24 對 `HttpHandler` 的 `Clone` 要求由 `derive(Clone)` 滿足，已包含），請 `npx ctx7@latest library hudsucker "HttpHandler trait Clone bound"` 確認當前 API 後再調整。

- [ ] **Step 1.4：Commit**

```bash
git add rust/src/mitm.rs rust/Cargo.toml rust/Cargo.lock
git commit -m "Filter MITM to hoyoverse getGachaLog and auto-stop on hit"
```

---

## Task 2：Dart UI 改寫成「等待 / 命中卡片」三狀態

**Files:**
- Modify: `lib/pages/poc_capture_page.dart`（整檔重寫）

- [ ] **Step 2.1：用以下完整內容覆寫 `lib/pages/poc_capture_page.dart`**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart' as rust_capture;

class PocCapturePage extends StatefulWidget {
  const PocCapturePage({super.key});

  @override
  State<PocCapturePage> createState() => _PocCapturePageState();
}

class _PocCapturePageState extends State<PocCapturePage> {
  bool _capturing = false;
  String? _error;
  rust_capture.CapturedRequest? _hit;
  StreamSubscription<rust_capture.CapturedRequest>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() => _error = null);
    try {
      if (_capturing) {
        await _sub?.cancel();
        _sub = null;
        await rust_capture.stopCapture();
        if (!mounted) return;
        setState(() => _capturing = false);
      } else {
        setState(() {
          _hit = null;
          _capturing = true;
        });
        final stream = rust_capture.startCapture();
        _sub = stream.listen(
          (event) {
            if (!mounted) return;
            setState(() => _hit = event);
          },
          onError: (e) {
            if (!mounted) return;
            setState(() => _error = '$e');
          },
          onDone: () {
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

  Widget _buildBody() {
    if (_hit != null) {
      return _HitCard(captured: _hit!);
    }
    if (_capturing) {
      return const _WaitingIndicator();
    }
    return const Center(child: Text('尚未開始攔截'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HTTPS 攔截 PoC')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: _toggle,
                  child: Text(_capturing ? '停止攔截' : '開始攔截'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

class _WaitingIndicator extends StatelessWidget {
  const _WaitingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('等待 getGachaLog 請求…'),
        ],
      ),
    );
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({required this.captured});

  final rust_capture.CapturedRequest captured;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '✅ 已取得 getGachaLog URL，攔截已停止',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('Method: ${captured.method}'),
              Text('Host: ${captured.host}'),
              const SizedBox(height: 8),
              SelectableText(
                captured.url,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

主要差異對照（vs 既有版本）：
- `_urls: List<CapturedRequest>` → `_hit: CapturedRequest?`
- 移除「共 N 筆」計數文字
- 移除 `ListView.separated`，改用三狀態 `_buildBody()`
- 新增 `onDone` callback 把 `_capturing` 設回 false（Rust 端命中後 sink drop 會觸發）
- 開始攔截時先 `setState(_hit = null)` 清空上次命中
- 拆出 `_WaitingIndicator` 與 `_HitCard` 兩個小元件，主 widget 更清晰

- [ ] **Step 2.2：靜態檢查**

Run: `flutter analyze`
Expected：no issues

- [ ] **Step 2.3：Commit**

```bash
git add lib/pages/poc_capture_page.dart
git commit -m "Stream single getGachaLog hit and observe stream onDone"
```

---

## Task 3：手動驗收（spec §7）

**Files:** 無檔案變動。

- [ ] **Step 3.1：啟動**

Run: `flutter run -d windows --release`
Expected：app 視窗打開、看到「尚未開始攔截」中央提示、按鈕「開始攔截」、無紅字錯誤

- [ ] **Step 3.2：開啟攔截，UI 進入等待狀態**

操作：點「開始攔截」
Expected：
- 中央區域變成 `CircularProgressIndicator` + 「等待 getGachaLog 請求…」
- 按鈕文字變「停止攔截」
- 系統 proxy 已被切到 `127.0.0.1:18080`（可由「Windows 設定 → 網路 → Proxy」確認，但此步不必開設定，下面會用負向驗收驗）

- [ ] **Step 3.3：負向驗收 — 非 hoyoverse 流量不該命中**

操作：開瀏覽器打 `https://example.com`
Expected：UI **完全無變化**，仍顯示等待提示（驗證 host 過濾生效，非命中流量被靜默放行）

- [ ] **Step 3.4：負向驗收 — hoyoverse 但路徑非 getGachaLog 不該命中**

操作：開瀏覽器打 `https://www.hoyoverse.com`
Expected：UI **完全無變化**（驗證 path 過濾生效）

- [ ] **Step 3.5：核心驗收 — 原神卡池歷史命中**

操作：開原神 → 進卡池介面 → 點「歷史紀錄」
Expected：
- UI 立刻切換成綠色 `✅ 已取得 getGachaLog URL，攔截已停止`
- 顯示 `Method: GET`、`Host: hk4e-api-os.hoyoverse.com`（國際版；國服 mihoyo.com 不會命中此 filter）
- 完整 URL（含 `authkey=...`）顯示在 monospace `SelectableText`
- 按鈕文字回到「開始攔截」
- 在執行 `flutter run` 的 console 看到 `INFO mitm: hit getGachaLog: GET https://...`

- [ ] **Step 3.6：自動還原系統 proxy**

操作：開「Windows 設定 → 網路 → Proxy」
Expected：「使用 Proxy 伺服器」已關（Rust 端命中後 `_proxy` 先 drop 還原）

- [ ] **Step 3.7：URL 完整可用**

操作：在 UI 上選取 `SelectableText` 整條 URL → 複製 → 貼到瀏覽器
Expected：返回 gacha log JSON（驗證 URL 完整、authkey 正確）

- [ ] **Step 3.8：可重複攔截**

操作：點「開始攔截」
Expected：
- 命中卡片消失，回到「等待 getGachaLog 請求…」狀態
- 按鈕回「停止攔截」

操作：再進原神卡池歷史 → 點刷新或切換池子
Expected：再次命中、UI 再次顯示綠色卡片

- [ ] **Step 3.9：負向驗收 — 命中前手動取消**

操作：點「開始攔截」→ 等待中 → 直接點「停止攔截」（不去原神）
Expected：
- 等待提示消失，回到「尚未開始攔截」
- 按鈕回「開始攔截」
- 系統 proxy 已還原

- [ ] **Step 3.10：依驗收結果決定下一步**

- 全部過 → 此 iteration PASS。
- step 3.5 攔不到（且 step 3.3 / 3.4 都過）→ 檢查原神實際走的 host 是否為 hoyoverse 而非 mihoyo（國服）；或 path 是否變過（如 `getGachaLogV2`）。
- step 3.3 或 3.4 失敗（不該命中卻命中）→ 檢查 `is_target` 邏輯，可能 host 比對寫成 `contains` 或 path 寫成 `contains`。
- step 3.6 proxy 沒還原 → 檢查 `Session` 欄位順序，必須是 `_proxy` 在前 `_mitm` 在後。
- 其他失敗 → 回對應 task 除錯。

PoC 階段不需要 commit「驗收完成」這種無檔案變動的 placeholder commit。

---

## Self-Review

**Spec coverage：**

| Spec 章節 | 對應 Task |
|---|---|
| §3 整體架構 | T1（Rust）、T2（Dart） |
| §4.1 is_target helper | T1（Step 1.1，函式定義） |
| §4.2 資料模型不變 | 無 task ✅（沒動 capture.rs，無工作） |
| §4.3 命中後流程 | T1（Step 1.1，handle_request 主體） |
| §4.4 移除 body collection | T1（Step 1.1 移除 BodyExt import + Step 1.2 移除 dep） |
| §5.1 LogHandler 加 fired | T1（Step 1.1，struct + start() 建構） |
| §5.2 capture.rs 不改 | 無 task ✅ |
| §5.3 mitm::start 簽章不變 | T1（Step 1.1 簽章保持） |
| §5.4 Drop 順序 | 無 task（既有 `Session { _proxy, _mitm }` 不動）✅ |
| §5.5 死鎖驗證 | T1（Step 1.1 用 `std::thread::spawn`） |
| §6.1 State 變更 | T2（Step 2.1） |
| §6.2 _toggle 流程 | T2（Step 2.1） |
| §6.3 三種顯示狀態 | T2（Step 2.1 `_buildBody` + `_HitCard` + `_WaitingIndicator`） |
| §6.4 Error 路徑 | T2（Step 2.1 catch / onError） |
| §7 手動驗收 | T3 step 3.1–3.9 |
| §8 Out of Scope | 計畫中無對應 task ✅ |
| §9 已知風險 | 風險本身不需 task；但 #3「path 改成 V2」與 #4「in-flight request」都靠 T3 step 3.5 驗證 |

無 spec 段落漏覆蓋。

**Placeholder 檢查：** 無 TBD/TODO；所有 code block 為可執行完整內容；唯一一處「以 ctx7 查證」是 hudsucker trait bound 的 fallback，且明確指出觸發條件而非當作預設動作。

**型別/簽章一致性：**
- `is_target(uri: &Uri) -> bool` 在 helper 定義與 handle_request 呼叫處一致 ✅
- `LogHandler { sink, fired }` struct 定義與 `start()` 內建構一致 ✅
- `CapturedRequest` 4 欄與既有 `rust/src/api/capture.rs` 完全一致 ✅
- `mitm::start(addr, cert_pem, key_pem, sink)` 簽章未變，capture.rs 呼叫處無需更動 ✅
- Dart `_hit: CapturedRequest?` 對應 Rust 端 sink 推送的 type ✅

審完無需修正。

---
