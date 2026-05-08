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
    // Drop 順序刻意：_mitm 先 drop → graceful shutdown 等 in-flight response 回 client；
    // _proxy 後 drop → 此時客戶端已拿到 response，broadcast SETTINGS_CHANGED 不會 abort
    // 遊戲 webview（CEF/WebView2 走 WinINet）正在處理的 fetch。
    _mitm: mitm::MitmServerGuard,
    _proxy: sys_proxy::SysProxyGuard,
}

static SESSION: Lazy<Mutex<Option<Session>>> = Lazy::new(|| Mutex::new(None));

pub fn start_capture(sink: StreamSink<CapturedRequest>) -> Result<()> {
    let mut guard = SESSION.lock().unwrap_or_else(|e| e.into_inner());
    if guard.is_some() {
        return Err(anyhow!("capture already running"));
    }

    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"))
        )
        .try_init();

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

    *guard = Some(Session { _mitm: mitm, _proxy: proxy });
    Ok(())
}

pub fn stop_capture() -> Result<()> {
    let mut guard = SESSION.lock().unwrap_or_else(|e| e.into_inner());
    *guard = None; // Drop 順序：_mitm 先（graceful shutdown 等 in-flight）→ _proxy（還原 sys proxy）
    Ok(())
}

pub fn cleanup_stale_proxy() -> Result<bool> {
    sys_proxy::cleanup_stale(PROXY_ADDR)
}
