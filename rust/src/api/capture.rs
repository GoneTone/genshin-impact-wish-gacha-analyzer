use std::sync::Mutex;
use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use crate::{ca, cert_store, mitm, sys_proxy};
use crate::frb_generated::StreamSink;

const PROXY_ADDR: &str = "127.0.0.1:18080";

#[derive(Clone)]
#[frb]
pub struct CapturedRequest {
    pub method: String,
    pub url: String,
    pub host: String,
    pub timestamp_ms: i64,
}

struct Session {
    _proxy: sys_proxy::SysProxyGuard, // dropped first → restores Windows system proxy
    _mitm: mitm::MitmServerGuard,     // dropped second → shuts down MITM proxy
}

static SESSION: Lazy<Mutex<Option<Session>>> = Lazy::new(|| Mutex::new(None));

pub fn start_capture(sink: StreamSink<CapturedRequest>) -> Result<()> {
    let mut guard = SESSION.lock().unwrap();
    if guard.is_some() {
        return Err(anyhow!("capture already running"));
    }

    let _ = tracing_subscriber::fmt::try_init();

    let root = ca::load_or_generate()?;
    cert_store::install_to_current_user_root(&root.cert_der)?;

    let mitm = mitm::start(
        PROXY_ADDR.parse()?,
        &root.cert_pem,
        &root.key_pem,
        sink,
    )?;
    // mitm 起好後再切系統 proxy，避免 race
    let proxy = sys_proxy::apply(PROXY_ADDR)?;

    *guard = Some(Session { _proxy: proxy, _mitm: mitm });
    Ok(())
}

pub fn stop_capture() -> Result<()> {
    let mut guard = SESSION.lock().unwrap();
    *guard = None; // Drop 順序：_proxy 先（sys proxy 還原）→ _mitm（關 proxy server）
    Ok(())
}

pub fn cleanup_stale_proxy() -> Result<bool> {
    sys_proxy::cleanup_stale(PROXY_ADDR)
}
