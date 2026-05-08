use anyhow::{Context, Result};
use windows::core::HSTRING;
use windows::Win32::Foundation::{ERROR_FILE_NOT_FOUND, ERROR_SUCCESS};
use windows::Win32::Networking::WinInet::{
    InternetSetOptionW, INTERNET_OPTION_REFRESH, INTERNET_OPTION_SETTINGS_CHANGED,
};
use windows::Win32::System::Registry::{
    RegCloseKey, RegDeleteValueW, RegOpenKeyExW, RegQueryValueExW, RegSetValueExW,
    HKEY_CURRENT_USER, KEY_READ, KEY_WRITE, REG_DWORD, REG_SZ,
};

const REG_PATH: &str = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings";

/// 代理程式狀態快照，用於恢復原始設定。
#[derive(Debug, Clone)]
pub struct SavedProxyState {
    pub enable: u32,
    pub server: Option<String>,
}

/// 啟用系統代理並返回 RAII guard；guard 被 drop 時自動恢復原始設定。
pub fn apply(addr: &str) -> Result<SysProxyGuard> {
    let saved = read_state().context("讀取原有代理設定失敗")?;
    write_state(1, Some(addr)).context("寫入代理設定失敗")?;
    broadcast_change().context("廣播代理設定變更失敗")?;
    Ok(SysProxyGuard { saved: Some(saved) })
}

/// 若目前代理指向 `target`，則清除代理設定並廣播；否則不動作。
///
/// 此函式用於程式崩潰後的殘留設定清理。
pub fn cleanup_stale(target: &str) -> Result<bool> {
    let state = read_state().context("讀取代理設定失敗")?;
    if state.enable == 1 && state.server.as_deref() == Some(target) {
        write_state(0, None).context("清除代理設定失敗")?;
        broadcast_change().context("廣播代理設定變更失敗")?;
        Ok(true)
    } else {
        Ok(false)
    }
}

/// RAII guard：drop 時自動將代理設定恢復到 `saved` 的狀態。
pub struct SysProxyGuard {
    saved: Option<SavedProxyState>,
}

impl Drop for SysProxyGuard {
    fn drop(&mut self) {
        if let Some(saved) = self.saved.take() {
            // Drop 不能 propagate 錯誤，以 let _ = 靜默忽略。
            let _ = write_state(saved.enable, saved.server.as_deref());
            let _ = broadcast_change();
        }
    }
}

// ── 內部 helpers ───────────────────────────────────────────────────────────

/// 讀取目前的代理設定狀態。
fn read_state() -> Result<SavedProxyState> {
    // SAFETY:
    // - HKEY_CURRENT_USER 為有效的預定義 HKEY 常數，生命週期為程式執行期間。
    // - phkresult 指向本地變數，RegOpenKeyExW 成功後才使用其內容。
    // - RegCloseKey 在使用完 hkey 後立刻呼叫，不存在 use-after-close。
    let hkey = unsafe {
        let mut hkey = std::mem::zeroed();
        RegOpenKeyExW(
            HKEY_CURRENT_USER,
            &HSTRING::from(REG_PATH),
            None,
            KEY_READ,
            &mut hkey,
        )
        .ok()
        .context("RegOpenKeyExW (read) 失敗")?;
        hkey
    };

    let enable = read_dword(hkey, "ProxyEnable").unwrap_or(0);
    let server = read_string(hkey, "ProxyServer").ok();

    // SAFETY: hkey 由 RegOpenKeyExW 取得且尚未關閉。
    unsafe {
        let _ = RegCloseKey(hkey);
    }

    Ok(SavedProxyState { enable, server })
}

/// 將代理設定寫入登錄。
/// - `enable`：寫入 ProxyEnable DWORD。
/// - `server`：`Some(s)` 寫入 ProxyServer REG_SZ；`None` 刪除 ProxyServer 值。
fn write_state(enable: u32, server: Option<&str>) -> Result<()> {
    // SAFETY:
    // - HKEY_CURRENT_USER 為有效預定義常數。
    // - phkresult 指向本地變數，函式成功後才讀取。
    // - RegCloseKey 在所有寫入完成後才呼叫。
    let hkey = unsafe {
        let mut hkey = std::mem::zeroed();
        RegOpenKeyExW(
            HKEY_CURRENT_USER,
            &HSTRING::from(REG_PATH),
            None,
            KEY_WRITE,
            &mut hkey,
        )
        .ok()
        .context("RegOpenKeyExW (write) 失敗")?;
        hkey
    };

    // 寫入 ProxyEnable DWORD
    // SAFETY:
    // - hkey 有效，由上方 RegOpenKeyExW 取得。
    // - enable_bytes 為本地 [u8; 4]，生命週期覆蓋 FFI 呼叫。
    // - Option<&[u8]> 傳入 Some(&enable_bytes[..])，長度為 4。
    let enable_bytes = enable.to_le_bytes();
    let write_enable_result = unsafe {
        RegSetValueExW(
            hkey,
            &HSTRING::from("ProxyEnable"),
            None,
            REG_DWORD,
            Some(&enable_bytes),
        )
        .ok()
    };

    let write_server_result = match server {
        Some(s) => {
            // 將 UTF-8 字串編碼為 UTF-16 含 null 結尾
            let wide: Vec<u16> = s.encode_utf16().chain(std::iter::once(0u16)).collect();
            // SAFETY:
            // - `wide` 在整個 FFI 呼叫期間保持有效（本地 Vec，借用於此 unsafe 區塊）。
            // - `as_ptr() as *const u8` 合法：u16 對齊 ≥ u8，且 from_raw_parts 的長度以位元組計。
            // - 長度 = wide.len() * 2 精確表示字串的位元組數（含 null 結尾）。
            let byte_slice = unsafe {
                std::slice::from_raw_parts(wide.as_ptr() as *const u8, wide.len() * 2)
            };
            unsafe {
                RegSetValueExW(
                    hkey,
                    &HSTRING::from("ProxyServer"),
                    None,
                    REG_SZ,
                    Some(byte_slice),
                )
                .ok()
            }
        }
        None => {
            // SAFETY: hkey 有效；字串 "ProxyServer" 透過 HSTRING 傳遞，生命週期覆蓋呼叫。
            let result = unsafe {
                RegDeleteValueW(hkey, &HSTRING::from("ProxyServer"))
            };
            // ERROR_FILE_NOT_FOUND 表示值本不存在，視為成功。
            if result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND {
                Ok(())
            } else {
                result.ok()
            }
        }
    };

    // SAFETY: hkey 有效且尚未關閉。
    unsafe {
        let _ = RegCloseKey(hkey);
    }

    write_enable_result.context("RegSetValueExW ProxyEnable 失敗")?;
    write_server_result.context("RegSetValueExW/RegDeleteValueW ProxyServer 失敗")?;
    Ok(())
}

/// 通知 Windows 網際網路設定已變更，使所有程式立即套用。
fn broadcast_change() -> Result<()> {
    // SAFETY:
    // - 第一個參數 None 表示全域設定（非特定 session）。
    // - lpbuffer 為 None（INTERNET_OPTION_SETTINGS_CHANGED 不需要資料）。
    // - dwbufferlength 為 0，與 None buffer 一致。
    unsafe {
        InternetSetOptionW(None, INTERNET_OPTION_SETTINGS_CHANGED, None, 0)
            .context("InternetSetOptionW SETTINGS_CHANGED 失敗")?;
        InternetSetOptionW(None, INTERNET_OPTION_REFRESH, None, 0)
            .context("InternetSetOptionW REFRESH 失敗")?;
    }
    Ok(())
}

/// 讀取指定值名稱的 DWORD。
fn read_dword(hkey: windows::Win32::System::Registry::HKEY, name: &str) -> Result<u32> {
    let mut data = [0u8; 4];
    let mut data_len = 4u32;
    // SAFETY:
    // - hkey 由呼叫端保證有效且未關閉。
    // - data 與 data_len 為本地變數，FFI 呼叫期間有效。
    // - lptype 傳 None（不需要驗證型別）。
    unsafe {
        RegQueryValueExW(
            hkey,
            &HSTRING::from(name),
            None,
            None,
            Some(data.as_mut_ptr()),
            Some(&mut data_len),
        )
        .ok()
        .context("RegQueryValueExW DWORD 失敗")?;
    }
    Ok(u32::from_le_bytes(data))
}

/// 讀取指定值名稱的 REG_SZ 字串。
fn read_string(hkey: windows::Win32::System::Registry::HKEY, name: &str) -> Result<String> {
    // 先查詢所需緩衝區大小
    let mut data_len = 0u32;
    // SAFETY:
    // - hkey 由呼叫端保證有效。
    // - lpdata 傳 None 以查詢所需大小，這是 Win32 API 的標準用法。
    unsafe {
        RegQueryValueExW(
            hkey,
            &HSTRING::from(name),
            None,
            None,
            None,
            Some(&mut data_len),
        )
        .ok()
        .context("RegQueryValueExW 查詢大小失敗")?;
    }

    // 分配緩衝區並讀取資料（data_len 為位元組數）
    let mut buf = vec![0u8; data_len as usize];
    // SAFETY:
    // - buf 已分配足夠空間（data_len 位元組）。
    // - buf.as_mut_ptr() 在 FFI 呼叫期間有效（buf 存活於此 unsafe 後）。
    unsafe {
        RegQueryValueExW(
            hkey,
            &HSTRING::from(name),
            None,
            None,
            Some(buf.as_mut_ptr()),
            Some(&mut data_len),
        )
        .ok()
        .context("RegQueryValueExW 讀取字串失敗")?;
    }

    // 將位元組緩衝區解析為 UTF-16，去除 null 結尾後轉換為 String
    // SAFETY:
    // - buf 的長度為偶數（REG_SZ 以 UTF-16 存儲，每個字元 2 位元組）。
    // - from_raw_parts 的指標對齊需求：u8 對齊 ≤ u16；透過複製至新 Vec<u16> 避免對齊問題。
    let wide_len = buf.len() / 2;
    let mut wide = vec![0u16; wide_len];
    for (i, chunk) in buf.chunks_exact(2).enumerate() {
        wide[i] = u16::from_le_bytes([chunk[0], chunk[1]]);
    }
    // 去除尾部 null 字元
    while wide.last() == Some(&0) {
        wide.pop();
    }
    String::from_utf16(&wide).context("REG_SZ UTF-16 解碼失敗")
}
