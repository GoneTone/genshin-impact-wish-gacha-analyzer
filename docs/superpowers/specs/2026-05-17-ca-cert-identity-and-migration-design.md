# Root CA 識別資料正名與舊憑證遷移

日期：2026-05-17
狀態：已核准，待寫實作計畫

## 背景

MITM 代理（攔截原神祈願紀錄 URL）使用自簽 root CA。目前 `rust/src/ca.rs` generate 分支的識別資料是 PoC 佔位字串：

- `DnType::CommonName` = `"GIWA PoC Root CA"`
- `DnType::OrganizationName` = `"GIWA PoC"`

`load_or_generate()` 僅在 `%APPDATA%\genshin_impact_wish_gacha_analyzer\ca\` 無現存 `root_ca.pem` / `root_ca.key` 時產生新 CA，產生後寫檔；`api/capture.rs:37-38` 接著 `cert_store::install_to_current_user_root()` 把 DER 裝進 Windows `CurrentUser\Root` 存放區。

全專案中真正帶 PoC 佔位的「資料」僅此一處。另 `sys_proxy.rs:25` 的「PoC」是註解舊用語（非資料，本次一併修正措辭，見下）；`docs/superpowers/specs/` 下檔名含 `poc` 的是歷史設計文件，非出貨內容，不在範圍。

## 目標

1. root CA 識別資料正名為產品資料。
2. 偵測到現存 CA 名稱與新版不符時，自動刪舊（appdata 檔案 + Windows 根存放區）並重生，使舊版使用者無痛升級且不殘留被信任的舊根憑證。

## 決策

| 項目 | 決定 |
|---|---|
| 新 CommonName | `Genshin Impact Wish Gacha Analyzer Root CA` |
| 新 OrganizationName | `GoneTone` |
| 舊 CA 處理 | 名稱不符 → 刪 appdata 檔 + 從 Windows `CurrentUser\Root` 移除 → 重生 |
| subject 解析 | 引入 `x509-parser` 套件，不手刻 DER 解析（依 CLAUDE.md「可引入套件、不要自行造輪子」） |

## 設計

### 1. `rust/src/ca.rs`

- 新增模組常數：
  - `EXPECTED_CN = "Genshin Impact Wish Gacha Analyzer Root CA"`
  - `EXPECTED_ORG = "GoneTone"`
  - generate 分支 DN 與 load 分支比對共用這兩個常數，避免兩處字串漂移。
- generate 分支：`dn.push(DnType::CommonName, EXPECTED_CN)`、`dn.push(DnType::OrganizationName, EXPECTED_ORG)`。
- load 分支：讀檔取得 `cert_der` 後，用 `x509-parser` 解析 subject，取出 CommonName / Organization 與常數比對：
  - **相符** → 行為不變，照常回傳 `RootCa`。
  - **不符，或解析失敗** → 視為需重生（自寫憑證必能解析，解析不了亦以重生最安全），進入遷移分支：
    1. 刪檔前先算舊 `cert_der` 的 SHA-1 指紋並保留。
    2. 刪除 `root_ca.pem` 與 `root_ca.key`。
    3. 呼叫 `cert_store::remove_from_current_user_root(old_cert_der)` 從 `CurrentUser\Root` 移除舊憑證。
    4. 落入既有 generate 分支，產生帶新 DN 的 CA、寫檔，回傳新 `RootCa`。
- 不需改 `api/capture.rs`：其既有的 `install_to_current_user_root(new_der)` 會把重生後的新憑證自然裝回（指紋查無 → 安裝，使用者跳一次 Windows 對話框）。

### 2. `rust/src/cert_store.rs`

新增 `pub fn remove_from_current_user_root(cert_der: &[u8]) -> anyhow::Result<()>`：

- 計算 `cert_der` 的 SHA-1 指紋。
- `CertOpenStore` 開 `CurrentUser\Root` → `CertFindCertificateInStore`（`CERT_FIND_SHA1_HASH`）。
- 找到 → `CertDeleteCertificateFromStore`；找不到 → 視為已移除，回傳 `Ok(())`，不報錯。
- 結構、SAFETY 註解、`target: "cert_store"` 日誌風格對齊既有 `install_to_current_user_root`。

### 3. `rust/Cargo.toml`

新增依賴 `x509-parser`（讀取現存憑證 subject DN）。

### 4. 日誌（CLAUDE.md 規則）

於關鍵節點補 `tracing`（對齊既有 `target: "ca"` / `"cert_store"`；Rust 端用 tracing 而非 Flutter Logger，與現況一致）：

- load 分支偵測到名稱不符：記錄舊 CN → 期望 CN（`warn` 等級，這是觸發遷移的決策點）。
- 刪除 appdata 憑證檔（含結果）。
- Windows 存放區移除結果（找到並刪除 / 查無）。
- 重生完成（沿用既有 `load_or_generate done` 的 SHA-1 紀錄）。

### 5. `rust/src/sys_proxy.rs`（註解措辭修正）

`apply` 的文件註解第 25 行「registry 可能殘留 PoC 設定」中的「PoC 設定」改為精確描述其指涉——本程式寫入的代理設定：

> `registry 可能殘留本程式寫入的代理設定——此種極端情況依賴啟動時的 cleanup_stale 自我修復。`

純註解措辭調整，不改任何行為與邏輯。

### 6. 測試

- 既有 `round_trip_generate_and_reload`：不受影響，仍通過（不檢查 DN 字串）。
- 新增測試：在 temp `APPDATA` 預先寫入「舊 PoC DN」的 CA 檔（CN = `GIWA PoC Root CA`），呼叫 `load_or_generate()`，斷言回傳憑證的 subject CN == `EXPECTED_CN`、檔案已被改寫為新 CA。
- Windows 存放區移除無法於單元測試覆蓋（測試環境未安裝該憑證）；`remove_from_current_user_root` 對「查無」採安全 no-op，故遷移測試不受影響。

## 範圍外（YAGNI）

- 不為 CN/O 字面值額外加鎖定常數的測試斷言以外的測試。
- 不處理歷史 spec 檔名。

## 提交前品質檢查

本變更為 Rust 端，不在 CLAUDE.md 的 Flutter 三項檢查涵蓋內。提交前於 `rust/` 執行並確認全通過：

1. `cargo fmt`
2. `cargo clippy`
3. `cargo test`
