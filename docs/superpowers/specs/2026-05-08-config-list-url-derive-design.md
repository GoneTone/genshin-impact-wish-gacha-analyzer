# 推導並顯示 getConfigList URL 設計

> **目的：** 命中 `getGachaLog` 後，從同一條 URL 推導出 `getConfigList` URL（共用 authkey 與所有簽章參數），同時推給 UI 顯示。下一個 iteration 做 replay 時可直接用。
>
> **範圍：** Rust 端 `CapturedRequest` 加一個 `config_list_url` 欄位 + `mitm.rs` 命中時做字串 replace + Dart 端 `_HitCard` 多顯示一條 URL。**不**新增 MITM 攔截規則（不再攔 getConfigList）。
>
> **前置：** `2026-05-08-gacha-log-filter-and-auto-stop-design.md` 已實裝並通過驗收。

## 1. 背景與目標

`getConfigList` 與 `getGachaLog` 是同一個 webview 開啟時都會打的 sibling API，使用**同一支 authkey** 與**同一組簽章/語系/region 參數**。從攔到的 `getGachaLog` URL 把 path 內 `/getGachaLog` 換成 `/getConfigList`，其他 query string 完整保留即可呼叫。

本 iteration 把這個 derived URL 推到 UI 一起顯示，使用者可從 UI 複製兩條 URL 各自貼到瀏覽器驗證，並為下一個 replay iteration 預留資料路徑。

## 2. 關鍵決策（已對齊）

| 項目 | 決定 | 理由 |
|---|---|---|
| Derive 位置 | Rust 端 (`mitm.rs::handle_request`) | schema 明確、Rust log 可看到 derived URL；Dart 純展示 |
| Derive 方式 | `url.replace("/getGachaLog", "/getConfigList")` | 1 行字串 replace；不必 parse Uri / 重組 query |
| Query string 處理 | 全部保留，不 strip | hoyoverse server 對未知 params 容忍；YAGNI |
| 資料模型 | `CapturedRequest` 加 `config_list_url: String` 欄位 | 命中即代表 path 結尾為 `/getGachaLog`，replace 必產出有效 URL，不需 `Option` |
| MITM 規則 | **不**新增攔截 getConfigList | 參數可從 getGachaLog URL 推導，多攔一支會增加複雜度且無價值 |
| UI 顯示 | 同一張 `_HitCard` 內上下並列，各自小標題 | 兩條 URL 一目了然，使用者不需切換 |

## 3. 資料模型變更

`rust/src/api/capture.rs`：

```rust
#[derive(Clone)]
#[frb]
pub struct CapturedRequest {
    pub method: String,
    pub url: String,
    pub host: String,
    pub timestamp_ms: i64,
    pub config_list_url: String,   // 新增
}
```

FRB codegen 會自動產生 Dart 端 `configListUrl: String`（camelCase）。

設計要點：
- **非 nullable `String`**：handler 命中時 path 結尾必為 `/getGachaLog`，replace 必產出有效字串。
- **欄位名 `config_list_url`**：直接對應 endpoint name `getConfigList`，未來看 schema 不必猜對應哪支 API。
- **與上一個 iteration spec §4.2 「資料模型不變」的關係**：上一 iteration 當時的設計沒這個需求，本 iteration 的擴充與當時決策不矛盾，是新需求觸發的擴充。

## 4. Derive 邏輯（`mitm.rs`）

`handle_request` 命中後段：

```rust
let method = parts.method.to_string();
let url = parts.uri.to_string();
let host = parts.uri.host().unwrap_or("").to_string();
let timestamp_ms = chrono::Utc::now().timestamp_millis();

let config_list_url = url.replace("/getGachaLog", "/getConfigList");

tracing::info!(target: "mitm", "hit getGachaLog: {} {}", method, url);
tracing::info!(target: "mitm", "derived getConfigList: {}", config_list_url);

let _ = self.sink.add(CapturedRequest {
    method,
    url,
    host,
    timestamp_ms,
    config_list_url,
});
```

設計要點：
- **`/getGachaLog` 加 `/` 前綴**：避免極小機率 query string 內出現 `getGachaLog` 字樣造成誤替換（觀察到的 URL query 不含此字樣，但加前綴成本低）。
- **`replace` 不是 `replacen(.., 1)`**：path 內通常只出現一次；即使多出現也應全換。
- **不 parse `hyper::Uri` 重組**：純字串對 PoC 充分，不必引入 url crate / 額外重組成本。
- **加一行 tracing log**：debug 時與 hit log 緊鄰，方便對照。

## 5. UI 變更（`_HitCard`）

```dart
Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '✅ 已取得 getGachaLog URL，攔截已停止',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text('Method: ${captured.method}'),
        Text('Host: ${captured.host}'),
        const SizedBox(height: 16),
        const Text('getGachaLog URL', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        SelectableText(captured.url, style: const TextStyle(fontFamily: 'monospace')),
        const SizedBox(height: 16),
        const Text('getConfigList URL', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        SelectableText(captured.configListUrl, style: const TextStyle(fontFamily: 'monospace')),
      ],
    ),
  ),
)
```

要點：
- 兩個小標題加粗，URL 區塊間距 `SizedBox(height: 16)` 比 Method/Host 大，視覺分組
- 兩條 URL 都是 `SelectableText` monospace，各自可獨立 copy
- 原 `_HitCard` 其餘部分（綠色提示、Method/Host）保留

## 6. 手動驗收

延用上一 iteration 的步驟，修改 step 5 與新增 step 7-bis：

1. `flutter run -d windows --release` 啟動 → 看到「尚未開始攔截」中央提示、按鈕「開始攔截」
2. 點「開始攔截」→ 顯示 `CircularProgressIndicator` + 「等待 getGachaLog 請求…」
3. 開瀏覽器打 `https://example.com` → UI 完全無變化
4. 開瀏覽器打 `https://www.hoyoverse.com` → UI 完全無變化
5. 開原神 → 卡池 → 歷史紀錄 → UI 切換成綠卡片 + Method/Host + **兩條 URL**（getGachaLog + getConfigList）；console 看到 `hit getGachaLog: ...` 與 `derived getConfigList: ...` 兩行 log
6. 系統 Proxy 已自動關閉
7. 從 UI 複製 **getGachaLog URL** 貼瀏覽器 → 取得 gacha log JSON
7-bis. 從 UI 複製 **getConfigList URL** 貼瀏覽器 → 取得 `data.gacha_type_list[]` JSON（驗證 derive URL 可用）
8. 再點「開始攔截」→ 卡片消失、再次命中 → 兩條 URL 都重新顯示
9. 命中前手動點「停止攔截」→ proxy 還原（不變）

## 7. Out of Scope

| 項目 | 為什麼不做 |
|---|---|
| 自動呼叫 getConfigList API 並 parse `gacha_type_list` 顯示在 UI | 下個 iteration / replay 階段做 |
| MITM 規則新增 getConfigList 攔截 | 不需要，URL 從攔到的 getGachaLog 推導即可 |
| URL 內 query string 清理（移除 gacha_type/page/size/end_id 等） | hoyoverse server 容忍未知 params；YAGNI |
| `Option<String>` 或多版本 endpoint 切換 | 命中即必有 derived URL；多版本是未來事 |
| 單元測試 derive 邏輯 | 1 行字串 replace；手動驗收 step 7-bis 已覆蓋 |

## 8. 已知風險

| 風險 | 嚴重度 | 處理 |
|---|---|---|
| 未來原神改 path（如 `/getGachaLogV2`）→ derive 出 `/getConfigListV2` 是猜測 | 低 | 上一 iteration spec §9「path 改版」已涵蓋；屆時兩條 URL 都需重新驗證 |
| `replace` 匹配 query 內字樣 | 極低 | 加 `/` 前綴防大部分；觀察到的 URL 不含此字樣 |
| FRB schema 變更需重跑 codegen | 必然 | implementation plan 列入步驟 |
| getConfigList 對「多餘 query params」嚴格 reject | 低 | step 7-bis 即驗收；若 reject 則改 strip 不必要 params |
