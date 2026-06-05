use crate::api::capture::CapturedRequest;
use crate::frb_generated::StreamSink;
use anyhow::{Context, Result};
use hudsucker::{
    certificate_authority::RcgenAuthority,
    hyper::{Request, Response, Uri},
    rcgen::{Issuer, KeyPair},
    rustls::{crypto::aws_lc_rs, ClientConfig},
    Body, HttpContext, HttpHandler, Proxy, RequestOrResponse,
};
use hyper_rustls::{ConfigBuilderExt, HttpsConnectorBuilder};
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::watch;

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

fn is_target(uri: &Uri) -> bool {
    let host_ok = uri
        .host()
        .map(|h| h == "hoyoverse.com" || h.ends_with(".hoyoverse.com"))
        .unwrap_or(false);
    let path = uri.path();
    let path_ok = path.ends_with("/getGachaLog") || path.ends_with("/getBeyondGachaLog");
    host_ok && path_ok
}

#[derive(Clone)]
struct LogHandler {
    sink: StreamSink<CapturedRequest>,
    // Arc-shared across handler clones so the first hit wins for the whole proxy.
    fired: Arc<AtomicBool>,
    // 命中後 set true；handle_response 第一次看到後 swap 為 false 並 spawn delayed stop。
    // 不能在 handle_request 內直接 spawn stop：那時上游 response 還沒回來，
    // hudsucker graceful shutdown 不等 outbound in-flight request，會直接切斷 connection。
    pending_stop: Arc<AtomicBool>,
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

        tracing::info!(target: "mitm", "hit gacha endpoint: {} {}", method, url);

        let _ = self.sink.add(CapturedRequest {
            method,
            url,
            host,
            timestamp_ms,
        });

        // 暫不 spawn stop_capture：要等 response 從上游回來，避免 hudsucker 太早 shutdown 切斷 connection。
        self.pending_stop.store(true, Ordering::SeqCst);

        Request::from_parts(parts, body).into()
    }

    async fn handle_response(&mut self, _ctx: &HttpContext, res: Response<Body>) -> Response<Body> {
        if self.pending_stop.swap(false, Ordering::SeqCst) {
            tracing::info!(target: "mitm", "handle_response after hit: status {}, scheduling stop", res.status());

            // 在 mitm runtime 之外觸發 stop，避免 self-join 死鎖。
            // 延遲 500ms 給 hudsucker 把 response body stream 完整寫回 client socket
            // （handle_response 觸發 = 上游 headers 已到，body 仍在 stream）。
            std::thread::spawn(|| {
                std::thread::sleep(std::time::Duration::from_millis(500));
                if let Err(e) = crate::api::capture::stop_capture() {
                    tracing::error!(target: "mitm", "auto-stop after match failed: {e}");
                }
            });
        }
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
    let issuer =
        Issuer::from_ca_cert_pem(cert_pem, key_pair).context("Issuer::from_ca_cert_pem failed")?;

    let provider = aws_lc_rs::default_provider();
    let ca = RcgenAuthority::new(issuer, 1_000, provider);

    // with_http_connector lets us supply a ClientConfig with ALPN h2 + http/1.1
    // (the default with_rustls_connector skips ALPN, breaking h2-only servers).
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

        // 在 task 外建好 proxy：build 失敗的 panic 會在本 thread 浮現，而非被 spawned task 靜默吞掉。
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

        // proxy 當背景 task 跑：收到訊號 → hudsucker graceful shutdown 停止 accept、排空 in-flight。
        rt.spawn(async move {
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
}
