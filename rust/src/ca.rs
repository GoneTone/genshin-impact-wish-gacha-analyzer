use anyhow::{Context, Result};
use rcgen::{BasicConstraints, CertificateParams, DistinguishedName, DnType, IsCa, KeyPair, KeyUsagePurpose};
use sha1::Digest;
use std::fs;
use std::path::PathBuf;

/// Returns `%APPDATA%\genshin_impact_wish_gacha_analyzer\ca\`, creating it if missing.
pub fn ca_dir() -> Result<PathBuf> {
    let appdata = std::env::var("APPDATA").context("APPDATA environment variable not set")?;
    let dir = PathBuf::from(appdata)
        .join("genshin_impact_wish_gacha_analyzer")
        .join("ca");
    fs::create_dir_all(&dir).with_context(|| format!("Failed to create CA directory: {}", dir.display()))?;
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
    eprintln!(
        "[ca] load_or_generate start: path={} cert_exists={} key_exists={}",
        dir.display(), cert_exists, key_exists
    );

    let result: Result<RootCa> = if cert_exists && key_exists {
        eprintln!("[ca] load branch (existing files)");

        let cert_pem = fs::read_to_string(&cert_path)
            .with_context(|| format!("Failed to read {}", cert_path.display()))?;
        let key_pem = fs::read_to_string(&key_path)
            .with_context(|| format!("Failed to read {}", key_path.display()))?;

        // Parse PEM to extract DER bytes using the `pem` crate.
        let pem_obj = pem::parse(&cert_pem)
            .with_context(|| "Failed to parse root_ca.pem")?;
        let cert_der = pem_obj.contents().to_vec();

        Ok(RootCa { cert_pem, key_pem, cert_der })
    } else {
        eprintln!("[ca] generate branch (no existing files)");

        // Generate a new self-signed root CA.
        let mut params = CertificateParams::new(Vec::new())
            .context("Failed to create CertificateParams")?;

        params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        params.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];

        let mut dn = DistinguishedName::new();
        dn.push(DnType::CommonName, "GIWA PoC Root CA");
        dn.push(DnType::OrganizationName, "GIWA PoC");
        params.distinguished_name = dn;

        let key_pair = KeyPair::generate().context("Failed to generate key pair")?;
        let cert = params.self_signed(&key_pair).context("Failed to self-sign certificate")?;

        let cert_pem = cert.pem();
        let key_pem = key_pair.serialize_pem();
        let cert_der = cert.der().as_ref().to_vec();

        fs::write(&cert_path, &cert_pem)
            .with_context(|| format!("Failed to write {}", cert_path.display()))?;
        fs::write(&key_path, &key_pem)
            .with_context(|| format!("Failed to write {}", key_path.display()))?;

        Ok(RootCa { cert_pem, key_pem, cert_der })
    };

    if let Ok(ref ca) = result {
        let hash = sha1::Sha1::digest(&ca.cert_der);
        eprintln!("[ca] load_or_generate done: sha1={}", hex::encode(hash));
    }
    result
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
