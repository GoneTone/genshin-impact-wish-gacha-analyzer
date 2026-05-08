use anyhow::Context;
use windows::core::w;
use windows::Win32::Security::Cryptography::{
    CertAddCertificateContextToStore, CertCloseStore, CertCreateCertificateContext,
    CertFreeCertificateContext, CertOpenStore, CERT_OPEN_STORE_FLAGS, CERT_QUERY_ENCODING_TYPE,
    CERT_STORE_ADD_REPLACE_EXISTING, CERT_STORE_PROV_SYSTEM_W, CERT_SYSTEM_STORE_CURRENT_USER,
    PKCS_7_ASN_ENCODING, X509_ASN_ENCODING,
};

/// 將 DER 編碼的 CA 憑證安裝到當前使用者的「根」憑證存放區。
///
/// 若相同憑證已存在則以新憑證覆蓋（CERT_STORE_ADD_REPLACE_EXISTING），
/// 不會因重複安裝而回傳錯誤。
pub fn install_to_current_user_root(cert_der: &[u8]) -> anyhow::Result<()> {
    // SAFETY:
    // - `cert_der` slice 在整個 FFI 呼叫期間保持有效（借用於函式生命週期內）。
    // - store handle 僅在 CertOpenStore 成功後至 CertCloseStore 之間使用。
    // - cert context 在函式返回前一定會被 CertFreeCertificateContext 釋放。
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

        // 從 DER 位元組建立憑證上下文
        let ctx = CertCreateCertificateContext(
            X509_ASN_ENCODING | PKCS_7_ASN_ENCODING,
            cert_der,
        );
        if ctx.is_null() {
            // 關閉存放區後再回傳錯誤（資源清理順序不得更動）
            let _ = CertCloseStore(Some(store), 0);
            return Err(
                anyhow::Error::from(windows::core::Error::from_thread())
                    .context("CertCreateCertificateContext 回傳 null"),
            );
        }

        // 將憑證加入存放區（若已存在則覆蓋）
        let result = CertAddCertificateContextToStore(
            Some(store),
            ctx,
            CERT_STORE_ADD_REPLACE_EXISTING,
            None,
        );

        // 釋放資源（無論成功與否）
        let _ = CertFreeCertificateContext(Some(ctx));
        let _ = CertCloseStore(Some(store), 0);

        result.context("CertAddCertificateContextToStore 失敗")
    }
}
