# Root CA 識別資料正名與舊憑證遷移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 MITM root CA 的 PoC 佔位識別資料正名為產品資料，並在偵測到舊名稱時自動刪舊（appdata 檔 + Windows 根存放區）後重生。

**Architecture:** 在 `ca.rs` 抽出 `generate_and_persist` 與 `subject_identity` 兩個 helper；`load_or_generate` 的 load 分支用 `x509-parser` 讀現存憑證 subject 與常數比對，不符即移除舊憑證並落回 generate。`cert_store.rs` 新增以 SHA-1 指紋刪除憑證的函式。`api/capture.rs` 不動——其既有 `install_to_current_user_root` 會自然把新憑證裝回。

**Tech Stack:** Rust、rcgen 0.14、pem 3、sha1 0.10、x509-parser（新增）、windows 0.62（Win32 Cryptography）、tracing。

**Spec:** `docs/superpowers/specs/2026-05-17-ca-cert-identity-and-migration-design.md`

**注意（提交範圍）:** `docs/superpowers/` 在此 repo 的 `.gitignore` 內，不進版控。各步驟 `git add` 只加 Rust 原始檔，**不要** add 本 plan 或 spec。

---

## File Structure

- `rust/Cargo.toml` — 新增 `x509-parser` 依賴。
- `rust/src/ca.rs` — 新增常數 `EXPECTED_CN` / `EXPECTED_ORG`、`subject_identity` helper、`generate_and_persist` helper；重寫 `load_or_generate` 加遷移分支；新增遷移測試。
- `rust/src/cert_store.rs` — 新增 `remove_from_current_user_root`。
- `rust/src/sys_proxy.rs` — 第 25 行文件註解措辭修正（純文字）。

所有 `cargo` 指令的工作目錄為 `rust/`。

---

### Task 1: 正名 CA 識別資料 + 可讀回 subject

把 generate 分支改用常數正名，並新增 `subject_identity` helper 讓之後的遷移分支能讀回現存憑證的 CN/O。

**Files:**
- Modify: `rust/Cargo.toml`
- Modify: `rust/src/ca.rs`
- Test: `rust/src/ca.rs`（`mod tests`）

- [ ] **Step 1: 新增 x509-parser 依賴**

工作目錄 `rust/`，執行：

```bash
cargo add x509-parser
```

預期：`Cargo.toml` `[dependencies]` 多一行 `x509-parser = "0.x"`（取最新可用版本即可，不需手動指定版本）。

- [ ] **Step 2: 寫失敗測試**

在 `rust/src/ca.rs` 的 `#[cfg(test)] mod tests` 內，`round_trip_generate_and_reload` 之後新增：

```rust
    #[test]
    fn generated_ca_has_product_identity() {
        let dir = tempfile::tempdir().unwrap();
        std::env::set_var("APPDATA", dir.path());

        let ca = load_or_generate().unwrap();
        let (cn, org) = subject_identity(&ca.cert_der).expect("subject should parse");

        assert_eq!(cn, EXPECTED_CN);
        assert_eq!(org, EXPECTED_ORG);
    }
```

- [ ] **Step 3: 跑測試確認失敗**

```bash
cargo test --lib ca::tests::generated_ca_has_product_identity
```

預期：編譯失敗，`cannot find function `subject_identity``、`cannot find value `EXPECTED_CN``。

- [ ] **Step 4: 加常數、helper，並把 generate 分支改用常數**

在 `rust/src/ca.rs` 頂部 import 區，將：

```rust
use std::path::PathBuf;
use tracing::debug;
```

改為：

```rust
use std::path::{Path, PathBuf};
use tracing::{debug, warn};
```

在 `ca_dir()` 之前（`use` 區塊之後）新增常數：

```rust
/// root CA 的 subject CommonName / Organization。
/// generate 與 load 分支共用，避免兩處字串漂移。
pub const EXPECTED_CN: &str = "Genshin Impact Wish Gacha Analyzer Root CA";
pub const EXPECTED_ORG: &str = "GoneTone";
```

在檔案中（`load_or_generate` 之後、`#[cfg(test)]` 之前）新增兩個 helper：

```rust
/// 解析 DER 憑證 subject，回傳 (CommonName, Organization)。任何解析失敗回傳 None。
fn subject_identity(cert_der: &[u8]) -> Option<(String, String)> {
    use x509_parser::prelude::*;
    let (_, cert) = X509Certificate::from_der(cert_der).ok()?;
    let subject = cert.subject();
    let cn = subject.iter_common_name().next()?.as_str().ok()?.to_string();
    let org = subject.iter_organization().next()?.as_str().ok()?.to_string();
    Some((cn, org))
}

/// 產生帶正式識別資料的自簽 root CA 並寫入 cert_path / key_path。
fn generate_and_persist(cert_path: &Path, key_path: &Path) -> Result<RootCa> {
    debug!(target: "ca", "generate branch");

    let mut params =
        CertificateParams::new(Vec::new()).context("Failed to create CertificateParams")?;
    params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    params.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];

    let mut dn = DistinguishedName::new();
    dn.push(DnType::CommonName, EXPECTED_CN);
    dn.push(DnType::OrganizationName, EXPECTED_ORG);
    params.distinguished_name = dn;

    let key_pair = KeyPair::generate().context("Failed to generate key pair")?;
    let cert = params
        .self_signed(&key_pair)
        .context("Failed to self-sign certificate")?;

    let cert_pem = cert.pem();
    let key_pem = key_pair.serialize_pem();
    let cert_der = cert.der().as_ref().to_vec();

    fs::write(cert_path, &cert_pem)
        .with_context(|| format!("Failed to write {}", cert_path.display()))?;
    fs::write(key_path, &key_pem)
        .with_context(|| format!("Failed to write {}", key_path.display()))?;

    Ok(RootCa {
        cert_pem,
        key_pem,
        cert_der,
    })
}
```

此步驟僅新增上述項目，`load_or_generate` 本體於 Task 3 重寫；本步驟先讓 `generated_ca_has_product_identity` 能通過——但現有 `load_or_generate` 的 generate 分支仍是舊字串，故還需 Task 3。為讓本 Task 測試先綠，於本步將現有 `load_or_generate` 內 generate 分支（`else { ... }` 區塊）整段替換為呼叫新 helper：

把現有：

```rust
    } else {
        debug!(target: "ca", "generate branch (no existing files)");

        // Generate a new self-signed root CA.
        let mut params =
            CertificateParams::new(Vec::new()).context("Failed to create CertificateParams")?;

        params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        params.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];

        let mut dn = DistinguishedName::new();
        dn.push(DnType::CommonName, "GIWA PoC Root CA");
        dn.push(DnType::OrganizationName, "GIWA PoC");
        params.distinguished_name = dn;

        let key_pair = KeyPair::generate().context("Failed to generate key pair")?;
        let cert = params
            .self_signed(&key_pair)
            .context("Failed to self-sign certificate")?;

        let cert_pem = cert.pem();
        let key_pem = key_pair.serialize_pem();
        let cert_der = cert.der().as_ref().to_vec();

        fs::write(&cert_path, &cert_pem)
            .with_context(|| format!("Failed to write {}", cert_path.display()))?;
        fs::write(&key_path, &key_pem)
            .with_context(|| format!("Failed to write {}", key_path.display()))?;

        Ok(RootCa {
            cert_pem,
            key_pem,
            cert_der,
        })
    };
```

替換為：

```rust
    } else {
        generate_and_persist(&cert_path, &key_path)
    };
```

（`load_or_generate` 的 load 分支與後段 SHA-1 debug 保持原樣，Task 3 再重寫整個函式。）

- [ ] **Step 5: 跑測試確認通過**

```bash
cargo test --lib ca::tests
```

預期：`generated_ca_has_product_identity` 與既有 `round_trip_generate_and_reload` 皆 PASS。

- [ ] **Step 6: Commit**

```bash
git add rust/Cargo.toml rust/Cargo.lock rust/src/ca.rs
git commit -m "feat(ca): rename root CA identity to product values, add subject_identity helper

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: cert_store 新增以指紋移除憑證

新增 `remove_from_current_user_root`，鏡像既有 `install_to_current_user_root` 的 store 開啟/查找/關閉慣例。

**Files:**
- Modify: `rust/src/cert_store.rs`
- Test: `rust/src/cert_store.rs`（新增 `#[cfg(test)] mod tests`）

- [ ] **Step 1: 寫失敗測試**

在 `rust/src/cert_store.rs` 檔末新增：

```rust
#[cfg(test)]
mod tests {
    use super::*;

    /// 一張未安裝到存放區的隨機憑證：find 應查無，remove 視為已移除回傳 Ok。
    /// 不會變更使用者真實的 CurrentUser\Root（只做唯讀 find）。
    #[test]
    fn remove_absent_cert_is_ok() {
        use rcgen::{CertificateParams, KeyPair};
        let params = CertificateParams::new(Vec::new()).unwrap();
        let kp = KeyPair::generate().unwrap();
        let cert = params.self_signed(&kp).unwrap();
        let der = cert.der().as_ref().to_vec();

        remove_from_current_user_root(&der).expect("absent cert removal should be Ok");
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

```bash
cargo test --lib cert_store::tests::remove_absent_cert_is_ok
```

預期：編譯失敗，`cannot find function `remove_from_current_user_root``。

- [ ] **Step 3: 實作 remove_from_current_user_root**

在 `rust/src/cert_store.rs` 的 `use windows::Win32::Security::Cryptography::{...}` import 清單中，加入 `CertDeleteCertificateFromStore`（與既有 `CertAddEncodedCertificateToStore` 同模組）。

在 `install_to_current_user_root` 函式之後新增：

```rust
/// 從當前使用者「根」憑證存放區移除指定 DER 憑證（以 SHA-1 指紋比對）。
///
/// - 查無相同憑證 → 視為已移除，回傳 `Ok(())`，不報錯。
/// - 找到 → `CertDeleteCertificateFromStore`（會釋放該 context）。
pub fn remove_from_current_user_root(cert_der: &[u8]) -> anyhow::Result<()> {
    let mut hash: [u8; 20] = Sha1::digest(cert_der).into();
    debug!(target: "cert_store", sha1 = %hex::encode(hash), "removing cert by thumbprint");

    // SAFETY:
    // - store handle 僅在 CertOpenStore 成功後至 CertCloseStore 之間使用。
    // - `hash` 陣列存活至函式結束，`blob.pbData` 在整段 unsafe 區塊內始終有效。
    // - `existing` 由 CertFindCertificateInStore 取得；CertDeleteCertificateFromStore
    //   會釋放此 context，之後不得再使用 `existing`，亦不另呼叫 CertFreeCertificateContext。
    // - `w!("Root")` 指向靜態 UTF-16 字串，生命週期為整個程式執行期間。
    unsafe {
        let store_name = w!("Root");
        let store = CertOpenStore(
            CERT_STORE_PROV_SYSTEM_W,
            CERT_QUERY_ENCODING_TYPE(0),
            None,
            CERT_OPEN_STORE_FLAGS(CERT_SYSTEM_STORE_CURRENT_USER),
            Some(store_name.as_ptr() as *const core::ffi::c_void),
        )
        .context("CertOpenStore Root 失敗")?;

        let blob = CRYPT_INTEGER_BLOB {
            cbData: hash.len() as u32,
            pbData: hash.as_mut_ptr(),
        };
        let existing = CertFindCertificateInStore(
            store,
            X509_ASN_ENCODING,
            0,
            CERT_FIND_SHA1_HASH,
            Some(&blob as *const CRYPT_INTEGER_BLOB as *const core::ffi::c_void),
            None,
        );

        if existing.is_null() {
            debug!(target: "cert_store", "cert not in store, nothing to remove");
            let _ = CertCloseStore(Some(store), 0);
            return Ok(());
        }

        debug!(target: "cert_store", "deleting cert from store");
        // `existing` 為 *mut CERT_CONTEXT，會隱式弱化為 *const CERT_CONTEXT
        let result = CertDeleteCertificateFromStore(existing);
        let _ = CertCloseStore(Some(store), 0);

        result.context("CertDeleteCertificateFromStore 失敗")
    }
}
```

注意：`CertDeleteCertificateFromStore` 在 `windows` 0.62 簽章為 `unsafe fn(*const CERT_CONTEXT) -> windows_core::Result<()>`，傳入 find 取得的 `existing` 即可（`*mut` 隱式弱化為 `*const`）。其餘 store 開啟/查找/關閉呼叫沿用既有 `install_to_current_user_root` 的相同寫法即正確；以 `cargo build` 驗證型別。

- [ ] **Step 4: 跑測試確認通過**

```bash
cargo test --lib cert_store::tests::remove_absent_cert_is_ok
```

預期：PASS（隨機憑證不在存放區 → find 查無 → `Ok`）。

- [ ] **Step 5: Commit**

```bash
git add rust/src/cert_store.rs
git commit -m "feat(cert-store): add remove_from_current_user_root by SHA-1 thumbprint

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: load_or_generate 加入遷移分支

重寫 `load_or_generate`：load 分支讀回 subject 與常數比對，不符即移除舊憑證（檔案 + 存放區）並重生。

**Files:**
- Modify: `rust/src/ca.rs`
- Test: `rust/src/ca.rs`（`mod tests`）

- [ ] **Step 1: 寫失敗測試**

在 `rust/src/ca.rs` 的 `mod tests` 內，需要 `rcgen` 型別。確認 `mod tests` 內 `use super::*;` 已存在（既有測試已有）。在 `generated_ca_has_product_identity` 之後新增：

```rust
    #[test]
    fn regenerates_when_identity_is_stale() {
        let _appdata = APPDATA_GUARD
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let dir = tempfile::tempdir().unwrap();
        std::env::set_var("APPDATA", dir.path());

        // 預先寫入帶舊 PoC DN 的 CA
        let ca_path_dir = dir
            .path()
            .join("genshin_impact_wish_gacha_analyzer")
            .join("ca");
        std::fs::create_dir_all(&ca_path_dir).unwrap();

        let mut params = CertificateParams::new(Vec::new()).unwrap();
        params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        let mut dn = DistinguishedName::new();
        dn.push(DnType::CommonName, "GIWA PoC Root CA");
        dn.push(DnType::OrganizationName, "GIWA PoC");
        params.distinguished_name = dn;
        let kp = KeyPair::generate().unwrap();
        let old = params.self_signed(&kp).unwrap();
        std::fs::write(ca_path_dir.join("root_ca.pem"), old.pem()).unwrap();
        std::fs::write(ca_path_dir.join("root_ca.key"), kp.serialize_pem()).unwrap();
        let old_der = old.der().as_ref().to_vec();

        let ca = load_or_generate().unwrap();

        let (cn, org) = subject_identity(&ca.cert_der).unwrap();
        assert_eq!(cn, EXPECTED_CN);
        assert_eq!(org, EXPECTED_ORG);
        // 確認真的重生（DER 與舊的不同）
        assert_ne!(ca.cert_der, old_der);
    }
```

說明：此測試會經由遷移分支呼叫 `cert_store::remove_from_current_user_root(old_der)`；該舊憑證從未安裝到真實存放區，`find` 查無 → no-op，不影響使用者環境。

- [ ] **Step 2: 跑測試確認失敗**

```bash
cargo test --lib ca::tests::regenerates_when_identity_is_stale
```

預期：FAIL，`assert_eq!(cn, EXPECTED_CN)` 失敗（目前 load 分支直接回傳舊憑證，CN 仍為 `GIWA PoC Root CA`）。

- [ ] **Step 3: 重寫 load_or_generate**

把整個 `load_or_generate` 函式（從 `pub fn load_or_generate() -> Result<RootCa> {` 到對應結尾 `}`，含原本的 `let result: Result<RootCa> = if cert_exists && key_exists { ... } else { generate_and_persist(&cert_path, &key_path) };` 與其後 SHA-1 debug 區塊）整段替換為：

```rust
/// Loads the existing root CA from disk, or generates and persists a new one.
///
/// 若現存憑證的 subject 與 `EXPECTED_CN` / `EXPECTED_ORG` 不符（或無法解析），
/// 視為舊版殘留：先從 Windows 使用者「根」存放區移除舊憑證，刪除 appdata 檔案，
/// 再重新產生帶正式識別資料的 CA。
pub fn load_or_generate() -> Result<RootCa> {
    let dir = ca_dir()?;
    let cert_path = dir.join("root_ca.pem");
    let key_path = dir.join("root_ca.key");

    let cert_exists = cert_path.exists();
    let key_exists = key_path.exists();
    debug!(
        target: "ca",
        path = %dir.display(),
        cert_exists,
        key_exists,
        "load_or_generate start"
    );

    let ca = if cert_exists && key_exists {
        let cert_pem = fs::read_to_string(&cert_path)
            .with_context(|| format!("Failed to read {}", cert_path.display()))?;
        let key_pem = fs::read_to_string(&key_path)
            .with_context(|| format!("Failed to read {}", key_path.display()))?;
        let pem_obj = pem::parse(&cert_pem).with_context(|| "Failed to parse root_ca.pem")?;
        let cert_der = pem_obj.contents().to_vec();

        match subject_identity(&cert_der) {
            Some((ref cn, ref org)) if cn.as_str() == EXPECTED_CN && org.as_str() == EXPECTED_ORG => {
                debug!(target: "ca", "load branch (identity matches)");
                RootCa {
                    cert_pem,
                    key_pem,
                    cert_der,
                }
            }
            other => {
                let old_cn = other
                    .map(|(cn, _)| cn)
                    .unwrap_or_else(|| "<unparsable>".to_string());
                warn!(
                    target: "ca",
                    old_cn = %old_cn,
                    expected_cn = EXPECTED_CN,
                    "CA identity mismatch, removing stale CA and regenerating"
                );

                // 刪檔前 cert_der 仍可用：先從 Windows 根存放區移除（best-effort）
                if let Err(e) = crate::cert_store::remove_from_current_user_root(&cert_der) {
                    warn!(target: "ca", error = %e, "failed to remove stale CA from store (continuing)");
                }
                let _ = fs::remove_file(&cert_path);
                let _ = fs::remove_file(&key_path);
                debug!(target: "ca", "stale CA files removed");

                generate_and_persist(&cert_path, &key_path)?
            }
        }
    } else {
        generate_and_persist(&cert_path, &key_path)?
    };

    let hash = sha1::Sha1::digest(&ca.cert_der);
    debug!(target: "ca", sha1 = %hex::encode(hash), "load_or_generate done");
    Ok(ca)
}
```

- [ ] **Step 4: 跑全部 ca 測試確認通過**

```bash
cargo test --lib ca::tests
```

預期：`regenerates_when_identity_is_stale`、`generated_ca_has_product_identity`、`round_trip_generate_and_reload` 皆 PASS。

- [ ] **Step 5: Commit**

```bash
git add rust/src/ca.rs
git commit -m "feat(ca): regenerate and remove stale CA when subject identity mismatches

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: sys_proxy 註解措辭修正

把 `apply` 文件註解中「PoC 設定」改為精確描述（純註解，不改行為）。

**Files:**
- Modify: `rust/src/sys_proxy.rs:25`

- [ ] **Step 1: 改註解**

在 `rust/src/sys_proxy.rs`，將該行：

```rust
/// registry 可能殘留 PoC 設定——此種極端情況依賴啟動時的 `cleanup_stale` 自我修復。
```

替換為：

```rust
/// registry 可能殘留本程式寫入的代理設定——此種極端情況依賴啟動時的 `cleanup_stale` 自我修復。
```

（保留行首 `/// `、全形破折號 `——`、反引號 `` `cleanup_stale` ``，僅替換「PoC 設定」為「本程式寫入的代理設定」。）

- [ ] **Step 2: 編譯驗證（註解不影響行為）**

```bash
cargo build
```

預期：編譯成功，無新警告。

- [ ] **Step 3: Commit**

```bash
git add rust/src/sys_proxy.rs
git commit -m "docs(sys-proxy): clarify stale proxy comment, drop PoC wording

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: 提交前品質檢查

**Files:** 無（驗證關卡）

- [ ] **Step 1: 格式化**

```bash
cargo fmt
```

若有改動，檢視後一併納入下方最終 commit。

- [ ] **Step 2: 靜態分析**

```bash
cargo clippy --all-targets -- -D warnings
```

預期：無 error、無 warning。有問題先修。

- [ ] **Step 3: 全測試**

```bash
cargo test
```

預期：全部 PASS（含 `ca::tests` 三項、`cert_store::tests::remove_absent_cert_is_ok`）。

- [ ] **Step 4: 若 fmt 有改動則 commit**

```bash
git add rust/src
git commit -m "style(rust): cargo fmt after CA identity migration

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

（若 Step 1 無改動則跳過此步。）
