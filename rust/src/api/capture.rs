use std::sync::Mutex;
use anyhow::{anyhow, Result};
use once_cell::sync::Lazy;
use crate::{ca, cert_store, sys_proxy};

const PROXY_ADDR: &str = "127.0.0.1:18080";

struct Session {
    _proxy: sys_proxy::SysProxyGuard,
}

static SESSION: Lazy<Mutex<Option<Session>>> = Lazy::new(|| Mutex::new(None));

pub fn start_capture() -> Result<()> {
    let mut guard = SESSION.lock().unwrap();
    if guard.is_some() {
        return Err(anyhow!("capture already running"));
    }

    let root = ca::load_or_generate()?;
    cert_store::install_to_current_user_root(&root.cert_der)?;
    let proxy = sys_proxy::apply(PROXY_ADDR)?;

    *guard = Some(Session { _proxy: proxy });
    Ok(())
}

pub fn stop_capture() -> Result<()> {
    let mut guard = SESSION.lock().unwrap();
    *guard = None; // Drop SysProxyGuard 還原
    Ok(())
}

pub fn cleanup_stale_proxy() -> Result<bool> {
    sys_proxy::cleanup_stale(PROXY_ADDR)
}
