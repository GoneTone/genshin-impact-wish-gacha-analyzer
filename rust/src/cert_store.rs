use anyhow::Context;
use sha1::{Digest, Sha1};
use windows::core::w;
use windows::Win32::Security::Cryptography::{
    CertAddEncodedCertificateToStore, CertCloseStore, CertFindCertificateInStore, CertOpenStore,
    CERT_FIND_SHA1_HASH, CERT_OPEN_STORE_FLAGS, CERT_QUERY_ENCODING_TYPE, CERT_STORE_ADD_NEW,
    CERT_STORE_PROV_SYSTEM_W, CERT_SYSTEM_STORE_CURRENT_USER, CRYPT_INTEGER_BLOB,
    X509_ASN_ENCODING,
};

/// 將 DER 編碼的 CA 憑證安裝到當前使用者的「根」憑證存放區。
///
/// 以 SHA-1 指紋（thumbprint）比對是否已安裝相同憑證：
/// - 已存在 → 跳過，不觸發 Windows 確認對話框。
/// - 不存在 → 呼叫 `CertAddEncodedCertificateToStore`（使用者只有首次安裝時看到對話框）。
pub fn install_to_current_user_root(cert_der: &[u8]) -> anyhow::Result<()> {
    // 計算 cert_der 的 SHA-1 指紋（20 bytes）
    let mut hash: [u8; 20] = Sha1::digest(cert_der).into();

    // SAFETY:
    // - store handle 僅在 CertOpenStore 成功後至 CertCloseStore 之間使用。
    // - `hash` 陣列存活至函式結束，`blob.pbData` 在整段 unsafe 區塊內始終有效。
    // - `pvfindpara` 指向 `blob`（CRYPT_HASH_BLOB），而 `blob.pbData` 指向同一 stack frame
    //   上的 `hash`，CertFindCertificateInStore 呼叫完成前二者均不會被釋放或移動。
    // - `Some(w!("Root").as_ptr() as _)` 指向靜態 UTF-16 字串，生命週期為整個程式執行期間。
    unsafe {
        // 開啟 CurrentUser\Root 憑證存放區
        let store_name = w!("Root");
        let store = CertOpenStore(
            CERT_STORE_PROV_SYSTEM_W,
            CERT_QUERY_ENCODING_TYPE(0),
            None,
            CERT_OPEN_STORE_FLAGS(CERT_SYSTEM_STORE_CURRENT_USER),
            Some(store_name.as_ptr() as *const core::ffi::c_void),
        )
        .context("CertOpenStore Root 失敗")?;

        // 以 SHA-1 指紋查詢存放區是否已有相同憑證（canonical thumbprint dedup）
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

        if !existing.is_null() {
            // 憑證已存在，跳過安裝，不觸發 Windows 確認對話框
            let _ = CertCloseStore(Some(store), 0);
            return Ok(());
        }

        // 憑證不存在，安裝之（使用者僅在此首次安裝時看到對話框）
        let result = CertAddEncodedCertificateToStore(
            Some(store),
            X509_ASN_ENCODING,
            cert_der,
            CERT_STORE_ADD_NEW,
            None,
        );

        let _ = CertCloseStore(Some(store), 0);

        result.context("CertAddEncodedCertificateToStore 失敗")
    }
}
