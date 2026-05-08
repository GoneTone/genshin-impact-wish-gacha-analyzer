use std::net::SocketAddr;
use std::sync::Arc;
use anyhow::{Context, Result};
use http_body_util::BodyExt;
use hudsucker::{
    Proxy,
    Body, HttpContext, HttpHandler, RequestOrResponse,
    certificate_authority::RcgenAuthority,
    hyper::{Request, Response},
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

#[derive(Clone)]
struct LogHandler {
    sink: StreamSink<CapturedRequest>,
}

impl HttpHandler for LogHandler {
    async fn handle_request(
        &mut self,
        _ctx: &HttpContext,
        req: Request<Body>,
    ) -> RequestOrResponse {
        let (parts, body) = req.into_parts();

        let method = parts.method.to_string();
        let uri = &parts.uri;
        let url = uri.to_string();
        let host = uri.host().unwrap_or("").to_string();
        let ts = chrono::Utc::now().timestamp_millis();

        // 同步 log 一條，方便除錯
        tracing::info!(target: "mitm", "{} {}", method, url);

        // 收集 body bytes（用於 PoC 驗證）；失敗時 warn 並改用空 body
        let body_bytes = match body.collect().await {
            Ok(collected) => collected.to_bytes(),
            Err(e) => {
                tracing::warn!(target: "mitm", "body collection failed: {}", e);
                Default::default()
            }
        };

        // 印出 body 摘要：byte 長度 + 前 256 bytes 的 UTF-8 lossy 預覽（spec §7 step 5）
        let preview_len = body_bytes.len().min(256);
        let preview = String::from_utf8_lossy(&body_bytes[..preview_len]);
        tracing::info!(
            target: "mitm",
            "body summary: {} bytes, preview: {:?}",
            body_bytes.len(),
            preview,
        );

        // 不阻塞請求；sink 滿了就丟棄這筆
        let _ = self.sink.add(CapturedRequest {
            method,
            url,
            host,
            timestamp_ms: ts,
        });

        // 重建 request，讓下游仍能收到相同的 body
        Request::from_parts(parts, Body::from(body_bytes)).into()
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

    // Build an outbound TLS connector that advertises h2 + http/1.1 via ALPN.
    // Using with_http_connector instead of with_rustls_connector so we can
    // supply a ClientConfig with alpn_protocols set; this prevents
    // "peer doesn't support any known protocol" errors from h2-only servers.
    let mut tls_config = ClientConfig::builder_with_provider(Arc::new(aws_lc_rs::default_provider()))
        .with_safe_default_protocol_versions()
        .context("rustls ClientConfig: no supported protocol versions")?
        .with_webpki_roots()
        .with_no_client_auth();
    tls_config.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];

    let https_connector = HttpsConnectorBuilder::new()
        .with_tls_config(tls_config)
        .https_or_http()
        .enable_http1()
        .enable_http2()
        .build();

    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();

    let handler = LogHandler { sink };

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
