# HTTPS 流量攔截 PoC（Windows）實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Flutter Windows app 內，透過 Rust core 攔截全系統 HTTPS 流量並把帶 `authkey` 的 URL 即時推給 Dart UI 顯示。

**Architecture:** Flutter UI（Dart）↔ `flutter_rust_bridge` v2 ↔ Rust cdylib。Rust 內聚 hudsucker MITM proxy、rcgen 動態 CA、`windows` crate 操作 cert store 與 HKCU registry。Windows 全系統 proxy 自動切換到 `127.0.0.1:18080`，CA 自動裝到 `CurrentUser\Root`。

**Tech Stack:** Flutter 3.11.5 / Dart, Rust stable, `flutter_rust_bridge` v2, `hudsucker` (hyper + rustls), `rcgen`, `windows` crate, `tokio`, `anyhow`, `tracing`。

**Spec 來源:** `docs/superpowers/specs/2026-05-08-https-capture-poc-design.md`

---

## 通用約定

- **每個 Task 結束都做一個原子 commit**（commit message 用 imperative 英語短句，跟 repo 風格一致：`Add ...`、`Wire ...`、`Verify ...`）
- **遇到 Rust API 不確定時用 `ctx7` 查最新文件**（user 全域規則）：先 `npx ctx7@latest library <name> "<question>"`，再 `npx ctx7@latest docs <id> "<question>"`
- **PoC 階段不寫單元測試**（spec 已決議），唯一例外是 `ca.rs` 的 round-trip 純邏輯測試
- **每個任務都有手動驗收命令與預期輸出**，沒過就不要進下一個 task

---

## 檔案結構（最終樣貌）

| 路徑 | 角色 | 任務 |
|---|---|---|
| `pubspec.yaml` | Flutter 依賴 | T1 |
| `rust/Cargo.toml` | Rust crate manifest | T2 |
| `rust/src/lib.rs` | FRB 入口（`pub mod api;`） | T2 |
| `rust/src/api/mod.rs` | API 子模組宣告 | T2 |
| `rust/src/api/capture.rs` | 公開 API：`start_capture` / `stop_capture` / `cleanup_stale_proxy` | T2 → T8 → T9 → T10 → T11 |
| `rust/src/ca.rs` | 動態產生 / 持久化 root CA | T5 |
| `rust/src/cert_store.rs` | `CurrentUser\Root` 安裝/查找 | T6 |
| `rust/src/sys_proxy.rs` | HKCU registry + InternetSetOption + RAII guard | T7 |
| `rust/src/mitm.rs` | hudsucker server + handler + RAII guard | T9 |
| `flutter_rust_bridge.yaml` | FRB codegen 設定 | T3 |
| `lib/main.dart` | app 入口 + crash recovery 呼叫 | T3 → T4 → T11 |
| `lib/pages/poc_capture_page.dart` | 按鈕 + URL 列表 UI | T4 → T8 → T10 |
| `lib/src/rust/**` | FRB 自動產生 binding（**不手改**） | T3 |

---

## Task 1：Flutter 依賴

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1.1：在 `pubspec.yaml` 加入 FRB 依賴**

```yaml
name: genshin_impact_wish_gacha_analyzer
description: "A new Flutter project."
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ^3.11.5

dependencies:
  flutter:
    sdk: flutter
  flutter_rust_bridge: ^2.0.0
  ffi: ^2.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
```

> 用 `ctx7` 查 `flutter_rust_bridge` 當前最新穩定版號替換上面的 `^2.0.0`。

- [ ] **Step 1.2：`flutter pub get`**

Run: `flutter pub get`
Expected: `Got dependencies!` 無錯誤

- [ ] **Step 1.3：Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "Add flutter_rust_bridge dependency"
```

---

## Task 2：Rust crate 骨架

**Files:**
- Create: `rust/Cargo.toml`
- Create: `rust/src/lib.rs`
- Create: `rust/src/api/mod.rs`
- Create: `rust/src/api/capture.rs`

- [ ] **Step 2.1：在 repo root 下建立 `rust/Cargo.toml`**

```toml
[package]
name = "genshin_capture_core"
version = "0.1.0"
edition = "2021"
publish = false

[lib]
crate-type = ["cdylib", "staticlib"]

[dependencies]
flutter_rust_bridge = "2"
anyhow = "1"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
tokio = { version = "1", features = ["rt-multi-thread", "macros", "sync", "net"] }
hudsucker = { version = "0.21", features = ["rustls-client", "full"] }
rcgen = "0.12"

[target.'cfg(windows)'.dependencies]
windows = { version = "0.56", features = [
    "Win32_Security_Cryptography",
    "Win32_Networking_WinInet",
    "Win32_System_Registry",
    "Win32_Foundation",
] }
```

> 各 crate 版本以 `ctx7` 查到的最新 stable 為準。`hudsucker` 的 features 名與大版本要對齊：先 `npx ctx7@latest library hudsucker "rustls feature flags"`。

- [ ] **Step 2.2：建立 `rust/src/lib.rs`**

```rust
pub mod api;
```

- [ ] **Step 2.3：建立 `rust/src/api/mod.rs`**

```rust
pub mod capture;
```

- [ ] **Step 2.4：建立 `rust/src/api/capture.rs`（先放 ping 驗證 toolchain）**

```rust
/// PoC 階段的健全性測試函式：用來確認 FRB codegen 與 dll 載入流程沒問題。
/// 完成 T3 後即可移除。
pub fn ping() -> String {
    "pong".to_string()
}
```

- [ ] **Step 2.5：`cargo build`**

Run（在 `rust/` 目錄）：`cargo build`
Expected：所有依賴下載完並編譯成功，產出 `target/debug/genshin_capture_core.dll`（Windows）或 `.so` / `.dylib`（其他平台）

- [ ] **Step 2.6：Commit**

```bash
git add rust/
git commit -m "Scaffold Rust capture core crate"
```

---

## Task 3：flutter_rust_bridge codegen 設定 + 煙霧測試

**Files:**
- Create: `flutter_rust_bridge.yaml`
- Create / Generated: `lib/src/rust/**`
- Modify: `lib/main.dart`

- [ ] **Step 3.1：安裝 codegen CLI**

Run: `cargo install flutter_rust_bridge_codegen --version "^2"`
Expected：CLI 安裝完成，`flutter_rust_bridge_codegen --version` 印出 2.x

- [ ] **Step 3.2：建立 `flutter_rust_bridge.yaml`（在 repo root）**

```yaml
rust_input: crate::api
rust_root: rust/
dart_output: lib/src/rust
dart_entrypoint_class_name: RustLib
```

> 這是 FRB v2 慣例配置；若 codegen 報錯請以 `ctx7` 查 `flutter_rust_bridge` 當前 yaml schema。

- [ ] **Step 3.3：執行 codegen**

Run（在 repo root）：`flutter_rust_bridge_codegen generate`
Expected：產出 `lib/src/rust/frb_generated.dart`、`lib/src/rust/api/capture.dart`，無錯誤

- [ ] **Step 3.4：把 `lib/main.dart` 改成 ping 煙霧測試**

```dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Rust says: ${ping()}'),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3.5：跑起來確認**

Run: `flutter run -d windows`
Expected：app 視窗顯示 `Rust says: pong`

- [ ] **Step 3.6：Commit**

```bash
git add flutter_rust_bridge.yaml lib/main.dart lib/src/rust/
git commit -m "Wire flutter_rust_bridge codegen and ping smoke test"
```

---

## Task 4：PocCapturePage UI 骨架（純 Dart，按鈕無動作）

**Files:**
- Create: `lib/pages/poc_capture_page.dart`
- Modify: `lib/main.dart`

- [ ] **Step 4.1：建立 `lib/pages/poc_capture_page.dart`**

```dart
import 'package:flutter/material.dart';

class PocCapturePage extends StatefulWidget {
  const PocCapturePage({super.key});

  @override
  State<PocCapturePage> createState() => _PocCapturePageState();
}

class _PocCapturePageState extends State<PocCapturePage> {
  bool _capturing = false;
  final List<String> _urls = [];

  Future<void> _toggle() async {
    setState(() => _capturing = !_capturing);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HTTPS 攔截 PoC')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _toggle,
              child: Text(_capturing ? '停止攔截' : '開始攔截'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _urls.isEmpty
                ? const Center(child: Text('尚無攔截紀錄'))
                : ListView.separated(
                    itemCount: _urls.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      title: Text(
                        _urls[i],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4.2：把 `main.dart` 改成載入這個頁面**

```dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/poc_capture_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: PocCapturePage());
  }
}
```

- [ ] **Step 4.3：執行**

Run: `flutter run -d windows`
Expected：app 顯示 `HTTPS 攔截 PoC` AppBar、「開始攔截」按鈕、「尚無攔截紀錄」中央提示文字。點按鈕只切換按鈕字串

- [ ] **Step 4.4：Commit**

```bash
git add lib/pages/poc_capture_page.dart lib/main.dart
git commit -m "Add PocCapturePage skeleton"
```

---

## Task 5：Rust `ca.rs` — 動態產生與持久化 root CA

**Files:**
- Create: `rust/src/ca.rs`
- Modify: `rust/src/lib.rs`

- [ ] **Step 5.1：在 `rust/src/lib.rs` 新增 module 宣告**

```rust
pub mod api;
pub(crate) mod ca;
```

- [ ] **Step 5.2：建立 `rust/src/ca.rs`**

```rust
use std::fs;
use std::path::{Path, PathBuf};
use anyhow::{Context, Result};
use rcgen::{CertificateParams, DistinguishedName, DnType, KeyPair, KeyUsagePurpose, BasicConstraints, IsCa};

/// `%APPDATA%\genshin_impact_wish_gacha_analyzer\ca\` 內持久化檔名
const CERT_PEM: &str = "root_ca.pem";
const KEY_PEM: &str = "root_ca.key";

pub struct RootCa {
    pub cert_pem: String,
    pub key_pem: String,
    pub cert_der: Vec<u8>,
}

pub fn ca_dir() -> Result<PathBuf> {
    let appdata = std::env::var("APPDATA")
        .context("APPDATA env var not set; PoC 只支援 Windows")?;
    let dir = PathBuf::from(appdata)
        .join("genshin_impact_wish_gacha_analyzer")
        .join("ca");
    fs::create_dir_all(&dir).with_context(|| format!("create_dir_all {:?}", dir))?;
    Ok(dir)
}

/// 載入既有 CA；若不存在則產生新的並寫檔。
pub fn load_or_generate() -> Result<RootCa> {
    let dir = ca_dir()?;
    let cert_path = dir.join(CERT_PEM);
    let key_path = dir.join(KEY_PEM);

    if cert_path.exists() && key_path.exists() {
        let cert_pem = fs::read_to_string(&cert_path)?;
        let key_pem = fs::read_to_string(&key_path)?;
        let cert_der = pem::parse(&cert_pem)?.into_contents();
        return Ok(RootCa { cert_pem, key_pem, cert_der });
    }

    let mut params = CertificateParams::new(vec![]);
    params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    params.key_usages = vec![
        KeyUsagePurpose::KeyCertSign,
        KeyUsagePurpose::CrlSign,
    ];
    let mut dn = DistinguishedName::new();
    dn.push(DnType::CommonName, "GIWA PoC Root CA");
    dn.push(DnType::OrganizationName, "GIWA PoC");
    params.distinguished_name = dn;

    let key_pair = KeyPair::generate()?;
    let cert = params.self_signed(&key_pair)?;

    let cert_pem = cert.pem();
    let key_pem = key_pair.serialize_pem();
    let cert_der = cert.der().to_vec();

    fs::write(&cert_path, &cert_pem)?;
    fs::write(&key_path, &key_pem)?;

    Ok(RootCa { cert_pem, key_pem, cert_der })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_generate_and_reload() {
        let dir = tempfile::tempdir().unwrap();
        std::env::set_var("APPDATA", dir.path());

        let first = load_or_generate().unwrap();
        let second = load_or_generate().unwrap();

        assert_eq!(first.cert_pem, second.cert_pem);
        assert_eq!(first.key_pem, second.key_pem);
        assert_eq!(first.cert_der, second.cert_der);
    }
}
```

> `pem`、`tempfile` 加入 `Cargo.toml`：

```toml
pem = "3"

[dev-dependencies]
tempfile = "3"
```

> ⚠️ rcgen 0.13 起 API 有調整，若 `ctx7` 顯示新版用法不同，請以新版為準調整 `KeyPair::generate` 與 `params.self_signed` 呼叫。

- [ ] **Step 5.3：跑單元測試**

Run（在 `rust/`）：`cargo test ca::tests::round_trip_generate_and_reload`
Expected：1 passed

- [ ] **Step 5.4：Commit**

```bash
git add rust/Cargo.toml rust/src/lib.rs rust/src/ca.rs
git commit -m "Add ca module with rcgen-based root CA persistence"
```

---

## Task 6：Rust `cert_store.rs` — 安裝 CA 到 `CurrentUser\Root`

**Files:**
- Create: `rust/src/cert_store.rs`
- Modify: `rust/src/lib.rs`

- [ ] **Step 6.1：`rust/src/lib.rs` 加 module**

```rust
pub mod api;
pub(crate) mod ca;
pub(crate) mod cert_store;
```

- [ ] **Step 6.2：建立 `rust/src/cert_store.rs`**

```rust
use anyhow::{anyhow, Context, Result};
use windows::core::*;
use windows::Win32::Security::Cryptography::*;

/// 把指定 DER root CA 裝到 CurrentUser\Root（若不存在）。
/// 第一次安裝會跳一次 Windows 系統的「您要安裝此憑證嗎」確認框（OS 行為，無法略過）。
pub fn install_to_current_user_root(cert_der: &[u8]) -> Result<()> {
    unsafe {
        let store_name = w!("Root");
        let store = CertOpenStore(
            CERT_STORE_PROV_SYSTEM_W,
            CERT_QUERY_ENCODING_TYPE(0),
            None,
            CERT_OPEN_STORE_FLAGS(CERT_SYSTEM_STORE_CURRENT_USER_ID << CERT_SYSTEM_STORE_LOCATION_SHIFT),
            Some(store_name.as_ptr() as _),
        ).context("CertOpenStore Root failed")?;

        let ctx = CertCreateCertificateContext(
            X509_ASN_ENCODING | PKCS_7_ASN_ENCODING,
            cert_der,
        );
        if ctx.is_null() {
            CertCloseStore(store, 0);
            return Err(anyhow!("CertCreateCertificateContext returned null"));
        }

        // CERT_STORE_ADD_REPLACE_EXISTING：若已存在指紋相同的憑證直接覆寫，避免重複裝
        let ok = CertAddCertificateContextToStore(
            store,
            ctx,
            CERT_STORE_ADD_REPLACE_EXISTING,
            None,
        );
        CertFreeCertificateContext(ctx);
        CertCloseStore(store, 0);

        ok.ok().context("CertAddCertificateContextToStore failed")
    }
}
```

> Win32 cert API 細節（旗標常數名、`CertOpenStore` 簽章）會隨 `windows` crate 版本微調，請以 `ctx7` 查 `microsoft/windows-rs` 對應版本確認。如果常數名 `CERT_SYSTEM_STORE_CURRENT_USER_ID` / `CERT_SYSTEM_STORE_LOCATION_SHIFT` 在當前版本不同，改用 `CERT_SYSTEM_STORE_CURRENT_USER` 直接旗標。

- [ ] **Step 6.3：編譯（不執行，編得過即可）**

Run（在 `rust/`）：`cargo build`
Expected：no errors

- [ ] **Step 6.4：Commit**

```bash
git add rust/src/lib.rs rust/src/cert_store.rs
git commit -m "Add cert_store module for CurrentUser\\Root install"
```

---

## Task 7：Rust `sys_proxy.rs` — RAII guard 切換 Windows proxy

**Files:**
- Create: `rust/src/sys_proxy.rs`
- Modify: `rust/src/lib.rs`

- [ ] **Step 7.1：`rust/src/lib.rs` 加 module**

```rust
pub mod api;
pub(crate) mod ca;
pub(crate) mod cert_store;
pub(crate) mod sys_proxy;
```

- [ ] **Step 7.2：建立 `rust/src/sys_proxy.rs`**

```rust
use anyhow::{Context, Result};
use windows::core::*;
use windows::Win32::Networking::WinInet::*;
use windows::Win32::System::Registry::*;

const REG_PATH: &str = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings";

#[derive(Debug, Clone)]
pub struct SavedProxyState {
    pub enable: u32,
    pub server: Option<String>,
}

/// 啟用全系統 proxy 指向 `addr`；回傳 RAII guard，drop 時自動還原到啟動前狀態。
pub fn apply(addr: &str) -> Result<SysProxyGuard> {
    let saved = read_state().context("read previous proxy state")?;
    write_state(1, Some(addr))?;
    broadcast_change()?;
    Ok(SysProxyGuard { saved: Some(saved) })
}

/// app 啟動時呼叫：若偵測到 HKCU proxy 還指向 `127.0.0.1:18080`（前次崩潰殘留），
/// 把 ProxyEnable 設 0、清空 ProxyServer；返回是否做了清理。
pub fn cleanup_stale(target: &str) -> Result<bool> {
    let state = read_state()?;
    if state.enable == 1 && state.server.as_deref() == Some(target) {
        write_state(0, None)?;
        broadcast_change()?;
        Ok(true)
    } else {
        Ok(false)
    }
}

pub struct SysProxyGuard {
    saved: Option<SavedProxyState>,
}

impl Drop for SysProxyGuard {
    fn drop(&mut self) {
        if let Some(saved) = self.saved.take() {
            let _ = write_state(saved.enable, saved.server.as_deref());
            let _ = broadcast_change();
        }
    }
}

fn read_state() -> Result<SavedProxyState> {
    unsafe {
        let mut hkey = HKEY::default();
        RegOpenKeyExW(
            HKEY_CURRENT_USER,
            &HSTRING::from(REG_PATH),
            0,
            KEY_READ,
            &mut hkey,
        ).ok().context("RegOpenKeyExW")?;

        let enable = read_dword(hkey, "ProxyEnable").unwrap_or(0);
        let server = read_string(hkey, "ProxyServer").ok();

        RegCloseKey(hkey).ok().ok();
        Ok(SavedProxyState { enable, server })
    }
}

fn write_state(enable: u32, server: Option<&str>) -> Result<()> {
    unsafe {
        let mut hkey = HKEY::default();
        RegOpenKeyExW(
            HKEY_CURRENT_USER,
            &HSTRING::from(REG_PATH),
            0,
            KEY_WRITE,
            &mut hkey,
        ).ok().context("RegOpenKeyExW(write)")?;

        let bytes = enable.to_le_bytes();
        RegSetValueExW(
            hkey,
            w!("ProxyEnable"),
            0,
            REG_DWORD,
            Some(&bytes),
        ).ok().context("set ProxyEnable")?;

        match server {
            Some(s) => {
                let wide: Vec<u16> = s.encode_utf16().chain(std::iter::once(0)).collect();
                let bytes = unsafe {
                    std::slice::from_raw_parts(
                        wide.as_ptr() as *const u8,
                        wide.len() * 2,
                    )
                };
                RegSetValueExW(hkey, w!("ProxyServer"), 0, REG_SZ, Some(bytes))
                    .ok().context("set ProxyServer")?;
            }
            None => {
                let _ = RegDeleteValueW(hkey, w!("ProxyServer"));
            }
        }

        RegCloseKey(hkey).ok().ok();
        Ok(())
    }
}

fn broadcast_change() -> Result<()> {
    unsafe {
        InternetSetOptionW(None, INTERNET_OPTION_SETTINGS_CHANGED, None, 0).ok().ok();
        InternetSetOptionW(None, INTERNET_OPTION_REFRESH, None, 0).ok().ok();
    }
    Ok(())
}

fn read_dword(hkey: HKEY, name: &str) -> Result<u32> {
    unsafe {
        let mut value: u32 = 0;
        let mut size: u32 = 4;
        let mut kind = REG_VALUE_TYPE::default();
        RegQueryValueExW(
            hkey,
            &HSTRING::from(name),
            None,
            Some(&mut kind),
            Some(&mut value as *mut _ as *mut u8),
            Some(&mut size),
        ).ok().context("RegQueryValueExW dword")?;
        Ok(value)
    }
}

fn read_string(hkey: HKEY, name: &str) -> Result<String> {
    unsafe {
        let mut size: u32 = 0;
        RegQueryValueExW(
            hkey,
            &HSTRING::from(name),
            None,
            None,
            None,
            Some(&mut size),
        ).ok().context("RegQueryValueExW size")?;

        let mut buf = vec![0u8; size as usize];
        RegQueryValueExW(
            hkey,
            &HSTRING::from(name),
            None,
            None,
            Some(buf.as_mut_ptr()),
            Some(&mut size),
        ).ok().context("RegQueryValueExW data")?;

        let wide: &[u16] = std::slice::from_raw_parts(
            buf.as_ptr() as *const u16,
            buf.len() / 2,
        );
        let s = String::from_utf16_lossy(wide).trim_end_matches('\0').to_string();
        Ok(s)
    }
}
```

> `windows` crate 0.56 → 0.58 已把 `RegOpenKeyExW` 等簽章微調，若編譯失敗請 `ctx7` 查 `microsoft/windows-rs` 並對齊。

- [ ] **Step 7.3：編譯**

Run（在 `rust/`）：`cargo build`
Expected：no errors

- [ ] **Step 7.4：Commit**

```bash
git add rust/src/lib.rs rust/src/sys_proxy.rs
git commit -m "Add sys_proxy module with RAII guard"
```

---

## Task 8：FRB API（先只做 CA + sys_proxy 生命週期，無 MITM）

**Files:**
- Modify: `rust/src/api/capture.rs`
- Generated: `lib/src/rust/api/capture.dart`
- Modify: `lib/pages/poc_capture_page.dart`

- [ ] **Step 8.1：改寫 `rust/src/api/capture.rs`**

```rust
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
```

> 把 `once_cell = "1"` 加進 `rust/Cargo.toml`。

- [ ] **Step 8.2：移除 T2 殘留的 `ping()` 函式**

在 `rust/src/api/capture.rs` 移除 `pub fn ping()`，並把 `lib/main.dart` 內的 `ping()` 顯示移除（這部分在 T4 已被 PocCapturePage 取代，確認無殘留呼叫）。

- [ ] **Step 8.3：跑 codegen**

Run（在 repo root）：`flutter_rust_bridge_codegen generate`
Expected：產出更新後的 `lib/src/rust/api/capture.dart`，含 `startCapture()`、`stopCapture()`、`cleanupStaleProxy()`

- [ ] **Step 8.4：把按鈕接到 Rust**

修改 `lib/pages/poc_capture_page.dart` 的 `_toggle`：

```dart
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
  final List<String> _urls = [];

  Future<void> _toggle() async {
    setState(() => _error = null);
    try {
      if (_capturing) {
        await rust_capture.stopCapture();
        setState(() => _capturing = false);
      } else {
        await rust_capture.startCapture();
        setState(() => _capturing = true);
      }
    } catch (e) {
      setState(() => _error = '$e');
    }
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
          Expanded(
            child: _urls.isEmpty
                ? const Center(child: Text('尚無攔截紀錄'))
                : ListView.separated(
                    itemCount: _urls.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      title: Text(_urls[i], maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 8.5：手動驗收**

1. `flutter run -d windows`
2. 點「開始攔截」：第一次應跳 Windows 憑證安裝確認框 → 點是
3. 開「Windows 設定 → 網路與網際網路 → Proxy」→ 確認「使用 Proxy 伺服器」打開、位址 `127.0.0.1:18080`
4. 開 `certmgr.msc → 信任的根憑證授權單位 → 憑證`，確認看到 `GIWA PoC Root CA`
5. 點「停止攔截」→ 回到 Proxy 設定畫面確認 proxy 已關
6. 再次點「開始攔截」→ 不應再跳憑證確認框（CA 已存在）

通通過再進下一個 task。

- [ ] **Step 8.6：Commit**

```bash
git add rust/Cargo.toml rust/src/api/capture.rs lib/src/rust/ lib/pages/poc_capture_page.dart lib/main.dart
git commit -m "Wire start/stop capture for CA install and proxy toggle"
```

---

## Task 9：Rust `mitm.rs` — hudsucker MITM proxy（先 stdout log，不上 UI）

**Files:**
- Create: `rust/src/mitm.rs`
- Modify: `rust/src/lib.rs`
- Modify: `rust/src/api/capture.rs`

- [ ] **Step 9.1：`rust/src/lib.rs` 加 module**

```rust
pub mod api;
pub(crate) mod ca;
pub(crate) mod cert_store;
pub(crate) mod sys_proxy;
pub(crate) mod mitm;
```

- [ ] **Step 9.2：建立 `rust/src/mitm.rs`**

```rust
use std::net::SocketAddr;
use anyhow::{Context, Result};
use hudsucker::{
    builder::ProxyBuilder,
    certificate_authority::RcgenAuthority,
    hyper::{Request, Response, Body},
    HttpContext, HttpHandler, RequestOrResponse,
};
use rcgen::KeyPair;
use rustls_pemfile::{certs, pkcs8_private_keys};
use tokio::sync::oneshot;
use tracing::info;

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
struct LogHandler;

#[async_trait::async_trait]
impl HttpHandler for LogHandler {
    async fn handle_request(
        &mut self,
        _ctx: &HttpContext,
        req: Request<Body>,
    ) -> RequestOrResponse {
        let method = req.method().clone();
        let uri = req.uri().to_string();
        info!(target: "mitm", "{} {}", method, uri);
        RequestOrResponse::Request(req)
    }
}

pub fn start(addr: SocketAddr, cert_pem: &str, key_pem: &str) -> Result<MitmServerGuard> {
    // 把 PEM 解碼成 hudsucker 期待的型別
    let mut cert_reader = std::io::BufReader::new(cert_pem.as_bytes());
    let cert_chain = certs(&mut cert_reader)
        .collect::<Result<Vec<_>, _>>()
        .context("parse cert pem")?;

    let mut key_reader = std::io::BufReader::new(key_pem.as_bytes());
    let mut keys = pkcs8_private_keys(&mut key_reader)
        .collect::<Result<Vec<_>, _>>()
        .context("parse key pem")?;
    let key = keys.pop().context("no private key in pem")?;

    let key_pair = KeyPair::from_pem(key_pem).context("rcgen KeyPair from pem")?;
    let ca = RcgenAuthority::new(key_pair, cert_chain[0].clone(), 1_000)
        .context("RcgenAuthority::new")?;

    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();

    let handle = std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("build tokio rt");

        rt.block_on(async move {
            let proxy = ProxyBuilder::new()
                .with_addr(addr)
                .with_rustls_client()
                .with_ca(ca)
                .with_http_handler(LogHandler)
                .with_graceful_shutdown(async {
                    let _ = shutdown_rx.await;
                })
                .build()
                .expect("hudsucker build");

            if let Err(e) = proxy.start().await {
                tracing::error!("proxy stopped: {e}");
            }
        });
    });

    Ok(MitmServerGuard {
        shutdown_tx: Some(shutdown_tx),
        handle: Some(handle),
    })
}
```

> ⚠️ hudsucker 的 builder API（method 名稱、`RcgenAuthority::new` 簽章、`HttpHandler::handle_request` 回傳型別）在 0.20→0.21 之間調整過。**進此 task 前必跑** `npx ctx7@latest library hudsucker "RcgenAuthority builder example"` 確認當前 API；若不同，照新 API 改寫對應呼叫，但骨架（spawn 一個 tokio rt + oneshot shutdown + log handler）不變。
>
> `async_trait`、`rustls-pemfile` 加進 `Cargo.toml`。

- [ ] **Step 9.3：把 mitm 整進 `rust/src/api/capture.rs`**

```rust
use std::sync::Mutex;
use anyhow::{anyhow, Result};
use once_cell::sync::Lazy;
use crate::{ca, cert_store, mitm, sys_proxy};

const PROXY_ADDR: &str = "127.0.0.1:18080";

struct Session {
    _mitm: mitm::MitmServerGuard,
    _proxy: sys_proxy::SysProxyGuard,
}

static SESSION: Lazy<Mutex<Option<Session>>> = Lazy::new(|| Mutex::new(None));

pub fn start_capture() -> Result<()> {
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
    )?;
    // mitm 起好後再切系統 proxy，避免 race
    let proxy = sys_proxy::apply(PROXY_ADDR)?;

    *guard = Some(Session { _mitm: mitm, _proxy: proxy });
    Ok(())
}

pub fn stop_capture() -> Result<()> {
    let mut guard = SESSION.lock().unwrap();
    *guard = None; // Drop 順序：proxy 先還原 → mitm shutdown
    Ok(())
}

pub fn cleanup_stale_proxy() -> Result<bool> {
    sys_proxy::cleanup_stale(PROXY_ADDR)
}
```

注意 Drop 順序：Rust struct field drop 順序是宣告順序，先 `_mitm` 再 `_proxy`。我們希望先還原 proxy 才關 mitm（避免 mitm 已關但系統 proxy 還指向它），所以宣告順序是 `_mitm` 在前、`_proxy` 在後 → drop 時 `_proxy` 先掉。✅ 上面寫法已正確。

- [ ] **Step 9.4：FRB codegen + 編譯**

Run: `flutter_rust_bridge_codegen generate`
Run（在 `rust/`）：`cargo build`
Expected：no errors

- [ ] **Step 9.5：手動驗收**

1. `flutter run -d windows --release`（release 較不會被 debugger 干擾 mitm）
2. 點「開始攔截」
3. 在 cmd 跑：`curl https://example.com`
4. 看 Flutter app 跑出來的 Rust stdout（在執行 `flutter run` 的 console）— 應印出 `mitm: GET https://example.com/`
5. 點「停止攔截」→ proxy 還原

過了再進 T10。如果 curl 報 TLS 錯誤，先確認 CA 真有裝在 CurrentUser\Root（T8 步驟 4）。

- [ ] **Step 9.6：Commit**

```bash
git add rust/Cargo.toml rust/src/lib.rs rust/src/mitm.rs rust/src/api/capture.rs lib/src/rust/
git commit -m "Add hudsucker MITM proxy with stdout logging"
```

---

## Task 10：把攔到的 URL 用 Stream 推到 UI 列表

**Files:**
- Modify: `rust/src/api/capture.rs`
- Modify: `rust/src/mitm.rs`
- Modify: `lib/pages/poc_capture_page.dart`

- [ ] **Step 10.1：在 `rust/src/api/capture.rs` 定義 `CapturedRequest` 與改寫 API**

```rust
use std::sync::Mutex;
use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use flutter_rust_bridge::for_generated::StreamSink;
use once_cell::sync::Lazy;
use crate::{ca, cert_store, mitm, sys_proxy};

const PROXY_ADDR: &str = "127.0.0.1:18080";

#[frb]
pub struct CapturedRequest {
    pub method: String,
    pub url: String,
    pub host: String,
    pub timestamp_ms: i64,
}

struct Session {
    _mitm: mitm::MitmServerGuard,
    _proxy: sys_proxy::SysProxyGuard,
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
    let proxy = sys_proxy::apply(PROXY_ADDR)?;

    *guard = Some(Session { _mitm: mitm, _proxy: proxy });
    Ok(())
}

pub fn stop_capture() -> Result<()> {
    let mut guard = SESSION.lock().unwrap();
    *guard = None;
    Ok(())
}

pub fn cleanup_stale_proxy() -> Result<bool> {
    sys_proxy::cleanup_stale(PROXY_ADDR)
}
```

> FRB v2 對 `StreamSink` 的 import path 在不同版本可能是 `flutter_rust_bridge::for_generated::StreamSink` 或 `flutter_rust_bridge::StreamSink`，請以 `ctx7` 查當前版本確認；codegen 報錯就改另一個。

- [ ] **Step 10.2：把 sink 餵給 `mitm.rs` handler**

```rust
// rust/src/mitm.rs（節錄修改部分）

use flutter_rust_bridge::for_generated::StreamSink;
use crate::api::capture::CapturedRequest;

#[derive(Clone)]
struct LogHandler {
    sink: StreamSink<CapturedRequest>,
}

#[async_trait::async_trait]
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

        RequestOrResponse::Request(req)
    }
}

pub fn start(
    addr: SocketAddr,
    cert_pem: &str,
    key_pem: &str,
    sink: StreamSink<CapturedRequest>,
) -> Result<MitmServerGuard> {
    // ...（前面 PEM 解析與 ca 建立保持不變）...

    let handler = LogHandler { sink };

    let handle = std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("build tokio rt");

        rt.block_on(async move {
            let proxy = ProxyBuilder::new()
                .with_addr(addr)
                .with_rustls_client()
                .with_ca(ca)
                .with_http_handler(handler)
                .with_graceful_shutdown(async {
                    let _ = shutdown_rx.await;
                })
                .build()
                .expect("hudsucker build");

            if let Err(e) = proxy.start().await {
                tracing::error!("proxy stopped: {e}");
            }
        });
    });

    Ok(MitmServerGuard {
        shutdown_tx: Some(shutdown_tx),
        handle: Some(handle),
    })
}
```

> `chrono = "0.4"` 加進 `Cargo.toml`。

- [ ] **Step 10.3：FRB codegen**

Run: `flutter_rust_bridge_codegen generate`
Expected：產出 `class CapturedRequest` 與 `Stream<CapturedRequest> startCapture()`

- [ ] **Step 10.4：UI 訂閱 Stream 並更新列表**

`lib/pages/poc_capture_page.dart`：

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
  final List<rust_capture.CapturedRequest> _urls = [];
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
        setState(() => _capturing = false);
      } else {
        final stream = rust_capture.startCapture();
        _sub = stream.listen(
          (event) => setState(() => _urls.insert(0, event)),
          onError: (e) => setState(() => _error = '$e'),
        );
        setState(() => _capturing = true);
      }
    } catch (e) {
      setState(() => _error = '$e');
    }
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
                const SizedBox(height: 8),
                Text('共 ${_urls.length} 筆'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _urls.isEmpty
                ? const Center(child: Text('尚無攔截紀錄'))
                : ListView.separated(
                    itemCount: _urls.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = _urls[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${r.method}  ${r.url}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        subtitle: Text(r.host),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 10.5：手動驗收**

1. `flutter run -d windows --release`
2. 點「開始攔截」
3. 開瀏覽器打 `https://example.com` → 列表頂端立刻多一筆 `GET https://example.com/`，下方顯示 host `example.com`
4. 連點幾次 F5 → 列表持續更新，計數遞增
5. 點「停止攔截」→ 計數凍結，再開瀏覽器不會新增
6. 再點一次「開始攔截」→ 能繼續攔（不會 panic）

- [ ] **Step 10.6：Commit**

```bash
git add rust/Cargo.toml rust/src/api/capture.rs rust/src/mitm.rs lib/src/rust/ lib/pages/poc_capture_page.dart
git commit -m "Stream captured requests to Dart UI list"
```

---

## Task 11：啟動時 crash recovery

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 11.1：在 `main()` 內呼叫 `cleanupStaleProxy`**

```dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/poc_capture_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart' as rust_capture;
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  try {
    final cleaned = await rust_capture.cleanupStaleProxy();
    if (cleaned) {
      debugPrint('[startup] stale proxy detected and reset');
    }
  } catch (e) {
    debugPrint('[startup] cleanup_stale_proxy failed: $e');
  }

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: PocCapturePage());
  }
}
```

- [ ] **Step 11.2：手動驗收（模擬崩潰）**

1. `flutter run -d windows`
2. 點「開始攔截」
3. 直接從 Task Manager 強制結束 app（不點停止）
4. 開「Windows 設定 → Proxy」→ 確認 proxy 仍然指向 `127.0.0.1:18080`（殘留）
5. 重新 `flutter run -d windows` → app 啟動後，proxy 應自動關閉
6. 確認 console 印出 `[startup] stale proxy detected and reset`

- [ ] **Step 11.3：Commit**

```bash
git add lib/main.dart
git commit -m "Cleanup stale system proxy on app startup"
```

---

## Task 12：完整 spec 驗收（卡池可行性核心）

**Files:** 無檔案變動，只跑 spec 第 7 節驗收。

- [ ] **Step 12.1：依序跑完 spec 6 步驗收**

依 `docs/superpowers/specs/2026-05-08-https-capture-poc-design.md` 第 7 節：

1. `flutter run -d windows --release` → PocCapturePage 顯示按鈕與空白列表 ✅
2. 點「開始攔截」（首次跳憑證確認，第二次起不跳）✅
3. `https://example.com` → 列表出現 `GET https://example.com/` ✅
4. **🎯 核心：** 開原神 → 進卡池 → 點「歷史紀錄」→ 列表出現含 `getGachaLog` 與 `authkey=...` 的長 URL
5. console 印出該 request 的 body 摘要（tracing log，PoC 不上 UI）
6. 點「停止攔截」→ Windows 設定 → Proxy 已關 → 瀏覽器恢復正常上網

- [ ] **Step 12.2：依驗收結果決定下一步**

- 全部過 → PoC PASS，方案成立。可以開始規劃正式產品功能與 Android 端。
- 第 4 步攔不到（且前 3 步都過）→ 高機率是原神 PC 客戶端做 SSL pinning，回 spec 第 8 節「已知風險」評估解 pinning 或改走「讀本地遊戲日誌」備援。
- 其他任一步失敗 → 回對應 task 除錯。

PoC 階段不需要也不該 commit「驗收完成」這種無檔案變動的 placeholder commit。

---

## Self-Review

**Spec coverage：**

| Spec 章節 | 對應 Task |
|---|---|
| §3 整體架構 | T2、T3（FRB 架構建立） |
| §4.1 啟動流程 | T8（CA + proxy）、T9（mitm）、T10（stream） |
| §4.2 停止流程 | T8、T9（RAII guard） |
| §4.3 資料模型 `CapturedRequest` | T10 |
| §4.4 RAII guard | T7、T9 |
| §4.4 crash recovery | T11 |
| §4.4 啟動步驟失敗 → UI 顯錯 | T8（`_error` state） |
| §5.1 Repo 配置 | T2、T3、T5–T11 全部對齊 |
| §5.2 Dart 相依 | T1 |
| §5.3 Rust 相依 | T2、T5、T9、T10（漸進加） |
| §5.4 建置工具 | T3 |
| §6 Out of scope | 計畫中無對應 task ✅ |
| §7 手動驗收 | T12 |
| §8 已知風險 #1 hudsucker H2 | hudsucker 預設處理 H1/H2，T9/T12 驗證涵蓋 |
| §8 已知風險 #2 首次裝 CA 提示 | T8 步驟 8.5 第 2 點 |
| §8 已知風險 #3 SSL pinning | T12 第 4 步即驗收，失敗即觸發 |
| §8 已知風險 #4 全系統 proxy 影響 | T8 驗收已暴露此行為（不另設機制） |
| §8 已知風險 #5 崩潰殘留 | T11 |

無 spec 段落漏覆蓋。

**Placeholder 檢查：** 無 TBD/TODO；所有 code block 都是可執行的具體內容；不確定的 API 點都標註 `ctx7` 查證指引而非「以後填」。

**型別/簽章一致性：**

- `start_capture` 在 T8 是 `() -> Result<()>`，T10 改為 `(StreamSink<CapturedRequest>) -> Result<()>` ✅（明確的演進）
- `CapturedRequest` 欄位 `method/url/host/timestamp_ms` 在 Rust struct 與 Dart 用法一致 ✅
- `cleanup_stale_proxy` Rust → `cleanupStaleProxy` Dart（FRB 自動轉 camelCase）✅
- `SysProxyGuard`、`MitmServerGuard` 命名與 spec §4.4 一致 ✅

審完無需修正。

---
