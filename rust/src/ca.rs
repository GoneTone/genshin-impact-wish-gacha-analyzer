use anyhow::{Context, Result};
use rcgen::{
    BasicConstraints, CertificateParams, DistinguishedName, DnType, IsCa, KeyPair, KeyUsagePurpose,
};
use sha1::Digest;
use std::fs;
use std::path::{Path, PathBuf};
use tracing::debug;

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

    let result: Result<RootCa> = if cert_exists && key_exists {
        debug!(target: "ca", "load branch (existing files)");

        let cert_pem = fs::read_to_string(&cert_path)
            .with_context(|| format!("Failed to read {}", cert_path.display()))?;
        let key_pem = fs::read_to_string(&key_path)
            .with_context(|| format!("Failed to read {}", key_path.display()))?;

        // Parse PEM to extract DER bytes using the `pem` crate.
        let pem_obj = pem::parse(&cert_pem).with_context(|| "Failed to parse root_ca.pem")?;
        let cert_der = pem_obj.contents().to_vec();

        Ok(RootCa {
            cert_pem,
            key_pem,
            cert_der,
        })
    } else {
        generate_and_persist(&cert_path, &key_path)
    };

    if let Ok(ref ca) = result {
        let hash = sha1::Sha1::digest(&ca.cert_der);
        debug!(target: "ca", sha1 = %hex::encode(hash), "load_or_generate done");
    }
    result
}

/// 解析 DER 憑證 subject，回傳 (CommonName, Organization)。任何解析失敗回傳 None。
// Task 3 將加入 staleness 偵測的 production 呼叫端，屆時移除此 allow。
#[allow(dead_code)]
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
}
