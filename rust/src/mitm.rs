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
    // Arc-shared across handler clones so the first hit wins for the whole proxy.
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
                tracing::error!(target: "mitm", "auto-stop after match failed: {e}");
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
                tracing::error!(target: "mitm", "mitm proxy stopped: {e}");
            }
        });
    });

    Ok(MitmServerGuard {
        shutdown_tx: Some(shutdown_tx),
        handle: Some(handle),
    })
}
