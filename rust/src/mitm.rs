use std::net::SocketAddr;
use anyhow::{Context, Result};
use hudsucker::{
    Proxy,
    Body, HttpContext, HttpHandler, RequestOrResponse,
    certificate_authority::RcgenAuthority,
    hyper::{Request, Response},
    rcgen::{Issuer, KeyPair},
    rustls::crypto::aws_lc_rs,
};
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
        let method = req.method().to_string();
        let uri = req.uri();
        let url = uri.to_string();
        let host = uri.host().unwrap_or("").to_string();
        let ts = chrono::Utc::now().timestamp_millis();

        // 同步 log 一條，方便除錯
        tracing::info!(target: "mitm", "{} {}", method, url);

        // 不阻塞請求；sink 滿了就丟棄這筆
        let _ = self.sink.add(CapturedRequest {
            method,
            url,
            host,
            timestamp_ms: ts,
        });

        req.into()
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
                .with_rustls_connector(aws_lc_rs::default_provider())
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
