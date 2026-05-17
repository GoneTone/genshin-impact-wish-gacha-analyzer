use anyhow::{Context, Result};
use rcgen::{
    BasicConstraints, CertificateParams, DistinguishedName, DnType, IsCa, KeyPair, KeyUsagePurpose,
};
use sha1::Digest;
use std::fs;
use std::path::{Path, PathBuf};
use tracing::{debug, warn};

/// root CA 的 subject CommonName / Organization。
/// generate 與 load 分支共用，避免兩處字串漂移。
pub const EXPECTED_CN: &str = "Genshin Impact Wish Gacha Analyzer Root CA";
pub const EXPECTED_ORG: &str = "GoneTone";

/// Returns `%APPDATA%\genshin_impact_wish_gacha_analyzer\ca\`, creating it if missing.
pub fn ca_dir() -> Result<PathBuf> {
    let appdata = std::env::var("APPDATA").context("APPDATA environment variable not set")?;
    let dir = PathBuf::from(appdata)
        .join("genshin_impact_wish_gacha_analyzer")
        .join("ca");
    fs::create_dir_all(&dir)
        .with_context(|| format!("Failed to create CA directory: {}", dir.display()))?;
    Ok(dir)
}

/// A self-signed root CA certificate and its private key.
pub struct RootCa {
    pub cert_pem: String,
    pub key_pem: String,
    pub cert_der: Vec<u8>,
}

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
            Some((cn, org)) if cn == EXPECTED_CN && org == EXPECTED_ORG => {
                debug!(target: "ca", "load branch (identity matches)");
                RootCa {
                    cert_pem,
                    key_pem,
                    cert_der,
                }
            }
            other => {
                let (old_cn, old_org) = other
                    .unwrap_or_else(|| ("<unparsable>".to_string(), "<unparsable>".to_string()));
                warn!(
                    target: "ca",
                    old_cn = %old_cn,
                    old_org = %old_org,
                    expected_cn = EXPECTED_CN,
                    expected_org = EXPECTED_ORG,
                    "CA identity mismatch, removing stale CA and regenerating"
                );

                // 刪檔前 cert_der 仍可用：先從 Windows 根存放區移除（best-effort）
                if let Err(e) = crate::cert_store::remove_from_current_user_root(&cert_der) {
                    warn!(target: "ca", error = %e, "failed to remove stale CA from store (continuing)");
                }
                for path in [&cert_path, &key_path] {
                    if let Err(e) = fs::remove_file(path) {
                        if e.kind() != std::io::ErrorKind::NotFound {
                            warn!(
                                target: "ca",
                                path = %path.display(),
                                error = %e,
                                "failed to remove stale CA file (regeneration will overwrite)"
                            );
                        }
                    }
                }
                debug!(target: "ca", "stale CA files cleanup done");

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

/// 解析 DER 憑證 subject，回傳 (CommonName, Organization)。任何解析失敗回傳 None。
pub(crate) fn subject_identity(cert_der: &[u8]) -> Option<(String, String)> {
    use x509_parser::prelude::*;
    let (_, cert) = X509Certificate::from_der(cert_der).ok()?;
    let subject = cert.subject();
    let cn = subject
        .iter_common_name()
        .next()?
        .as_str()
        .ok()?
        .to_string();
    let org = subject
        .iter_organization()
        .next()?
        .as_str()
        .ok()?
        .to_string();
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

#[cfg(test)]
mod tests {
    use super::*;

    /// 序列化所有會改 process-global `APPDATA` 的測試，避免多執行緒競態。
    /// 用 PoisonError::into_inner 容忍先前測試 panic 造成的中毒，不讓其連鎖失敗。
    static APPDATA_GUARD: std::sync::Mutex<()> = std::sync::Mutex::new(());

    #[test]
    fn round_trip_generate_and_reload() {
        let _appdata = APPDATA_GUARD
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let dir = tempfile::tempdir().unwrap();
        std::env::set_var("APPDATA", dir.path());

        let first = load_or_generate().unwrap();
        let second = load_or_generate().unwrap();

        assert_eq!(first.cert_pem, second.cert_pem);
        assert_eq!(first.key_pem, second.key_pem);
        assert_eq!(first.cert_der, second.cert_der);
    }

    #[test]
    fn generated_ca_has_product_identity() {
        let _appdata = APPDATA_GUARD
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let dir = tempfile::tempdir().unwrap();
        std::env::set_var("APPDATA", dir.path());

        let ca = load_or_generate().unwrap();
        let (cn, org) = subject_identity(&ca.cert_der).expect("subject should parse");

        assert_eq!(cn, EXPECTED_CN);
        assert_eq!(org, EXPECTED_ORG);
    }

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

        // 確認新憑證也已寫回磁碟（stale-CA 重生後的 round-trip）
        let reloaded = load_or_generate().unwrap();
        assert_eq!(reloaded.cert_der, ca.cert_der);
    }
}
