# HTTPS 流量攔截 PoC 設計（Windows 端）

> 目的：驗證跨平台遊戲卡池歷史分析應用程式的核心可行性——能否在 Flutter app 內，透過原生模組攔截目標遊戲開啟卡池紀錄頁時的 HTTPS request，並把帶 authkey 的完整 URL（與 body）即時推給 Dart UI 顯示。
>
> 本 PoC 範圍僅限 Windows；Android 端 (VpnService) 在驗證 Windows 通路後再規劃。

## 1. 背景與目標

最終產品要做跨 Windows / Android 的遊戲卡池歷史分析工具，核心動作是「攔截遊戲開啟卡池紀錄頁時呼叫的 HTTPS API」，從中取得帶 authkey 的 URL，後續即可 replay 該 API 取得卡池資料。

PoC 不做最終 UI、不做卡池資料分析，只做一個最小可驗證單元：

- 一個按鈕，點下後啟動 HTTPS 攔截
- 按鈕下方有一個列表，即時顯示攔截到的 URL
- 再點一次按鈕停止攔截，還原系統設定

如果這個 PoC 可以攔到原神卡池歷史頁的 `getGachaLog` URL（含 `authkey`），整體技術路線就成立，可以接著規劃 Android 端與正式產品功能。

## 2. 關鍵決策（已對齊）

| 項目 | 決定 | 理由 |
|---|---|---|
| PoC 平台 | 只做 Windows | Android 同時要處理「使用者裝 CA」+「SSL pinning」兩個難關，先在 Windows 驗證 Flutter ↔ 原生通路 |
| 攔截範圍 | URL + 完整 HTTP body | body 後續分析需要；也是最完整的可行性驗證 |
| MITM 引擎 | Rust：hudsucker + rcgen | hyper + rustls 成熟 stack；未來可重用到 Android |
| Flutter ↔ Rust 整合 | `flutter_rust_bridge` v2 | Stream 直接映射，URL 即時推送無摩擦；codegen 維護成本低 |
| 系統 Proxy 設定 | 全自動修改 HKCU Internet Settings | 一鍵驗證，使用者不用手動切 proxy |
| CA 安裝 | 自動安裝到 `CurrentUser\Root`（首次跳一次系統確認框） | 不需 admin；CA 留著重複使用 |

## 3. 整體架構

```
┌────────────────────────────────────────────┐
│  Flutter UI (Dart)                         │
│  - PocCapturePage：按鈕 + 即時 URL 列表    │
│  - 訂閱 Rust 推來的 Stream<CapturedRequest>│
└────────────────────────────────────────────┘
                  ↕  flutter_rust_bridge
┌────────────────────────────────────────────┐
│  Rust core (cdylib, Windows)               │
│                                            │
│  公開 API：                                  │
│    start_capture() -> Stream<CapturedRequest>│
│    stop_capture()  -> Result<()>           │
│                                            │
│  內部模組：                                  │
│  ├─ ca.rs        rcgen 產 root CA          │
│  ├─ cert_store.rs 安裝/查找 CurrentUser\Root│
│  ├─ sys_proxy.rs  HKCU\...\Internet Settings│
│  └─ mitm.rs       hudsucker on 127.0.0.1   │
└────────────────────────────────────────────┘
```

設計要點：

- 所有原生工作（含 Win32 API 操作）都收在 Rust 一邊；Dart 只 call 兩個 function、訂一條 Stream
- CA 一次裝好就留著，下次啟動直接用同一張，不重複跳 Windows 確認框
- Stop 路徑用 RAII guard，確保系統 proxy 一定被還原（即使中間 panic）

## 4. Data Flow

### 4.1 啟動流程

```
[使用者點 Start]
  ↓
Dart: capture_bridge.startCapture()
  ↓ (FFI)
Rust:
  1. 載入或產生 root CA（首次：rcgen 產 → 寫到 %APPDATA%\genshin_impact_wish_gacha_analyzer\ca\）
  2. 確認 CA 已在 CurrentUser\Root；不在則 CertAddCertificateContextToStore
       └─ 首次安裝時 Windows 跳一次「您要安裝此憑證嗎」確認框
  3. 啟動 hudsucker MITM proxy on 127.0.0.1:18080
  4. 修改 HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
       ProxyEnable = 1, ProxyServer = "127.0.0.1:18080"
       呼叫 InternetSetOptionW(INTERNET_OPTION_SETTINGS_CHANGED) 廣播
  5. 回傳 Stream<CapturedRequest> 給 Dart
  ↓
hudsucker 每攔到一個 request:
  StreamSink.add(CapturedRequest { method, url, host, timestamp })
  ↓
Dart: state.urls.insert(0, event); setState();
  ↓
UI: 列表頂端多一筆
```

### 4.2 停止流程

```
[使用者再點 Stop]
  ↓
Dart: capture_bridge.stopCapture()
  ↓
Rust（RAII guard 順序倒回）：
  1. 還原 HKCU registry：ProxyEnable / ProxyServer 回到原值
       └─ 啟動時把原值記下來，Stop 時寫回；廣播 SETTINGS_CHANGED
  2. shutdown hudsucker（drop server task）
  3. CA 不卸載（留著下次用）
  ↓
Dart: 按鈕回到「未攔截」狀態
```

### 4.3 資料模型

Dart 端對應型別（FRB 從 Rust struct 自動產生）：

```dart
class CapturedRequest {
  final String method;     // "GET" / "POST" / ...
  final String url;        // 完整 URL（含 query string）
  final String host;       // 方便未來篩選用
  final DateTime timestamp;
}
```

PoC 階段 body 不顯示在 UI；hudsucker handler 讀到 body 後印 log 確認可讀，不送 Dart。

### 4.4 錯誤與還原保護

- **RAII guard**：`SysProxyGuard`、`MitmServerGuard` 實作 Rust `Drop`，即使中間 panic，Drop 也會跑還原邏輯
- **啟動 crash recovery**：app 啟動時若偵測到 HKCU proxy 還指向 `127.0.0.1:18080` 但 PoC 沒在跑（前次崩潰殘留），把 `ProxyEnable` 設 0、清空 `ProxyServer`。
  - 限制：若使用者啟動 PoC *前*就已設定其他 proxy，崩潰後該設定無法被還原（PoC 期間僅把原值記在記憶體；正式產品階段再考慮把原值落盤到 `%APPDATA%` 以支援跨 process 還原）。
- **任一啟動步驟失敗**（CA 安裝拒絕 / proxy 寫不進去）→ 把錯誤訊息推 UI，按鈕回到「未攔截」狀態

## 5. 檔案結構與相依套件

### 5.1 Repo 配置

```
genshin_impact_wish_gacha_analyzer/
├─ lib/                              # Dart
│  ├─ main.dart                      # 入口，掛 PocCapturePage
│  ├─ pages/
│  │  └─ poc_capture_page.dart       # 按鈕 + URL 列表
│  └─ src/rust/                      # FRB 自動產生（不手改）
│     ├─ frb_generated.dart
│     └─ api/capture.dart
│
├─ rust/                             # 新增：Rust core
│  ├─ Cargo.toml
│  └─ src/
│     ├─ lib.rs                      # FRB API 入口（pub mod api;）
│     ├─ api/
│     │  └─ capture.rs               # start_capture / stop_capture
│     ├─ ca.rs                       # rcgen 產 root CA + 序列化
│     ├─ cert_store.rs               # CurrentUser\Root 操作
│     ├─ sys_proxy.rs                # HKCU Internet Settings + 廣播
│     └─ mitm.rs                     # hudsucker handler + StreamSink
│
├─ windows/                          # Flutter Windows runner（FRB build hook）
├─ android/                          # 暫不動
├─ flutter_rust_bridge.yaml          # FRB v2 設定檔
├─ pubspec.yaml
└─ docs/superpowers/specs/
   └─ 2026-05-08-https-capture-poc-design.md   # 本 spec
```

### 5.2 Dart 相依（pubspec.yaml）

| 套件 | 用途 |
|---|---|
| `flutter_rust_bridge` ^2 | Rust ↔ Dart bridge runtime |
| `ffi` | dart:ffi helpers（FRB 依賴） |

UI 純用 Material；不引入 state management 套件（PoC 範圍小，`StatefulWidget` + `StreamSubscription` 足夠）。

### 5.3 Rust 相依（rust/Cargo.toml）

| Crate | 用途 |
|---|---|
| `flutter_rust_bridge` ^2 | bridge runtime（與 Dart 端對齊） |
| `hudsucker` | MITM proxy 框架（hyper + rustls） |
| `rcgen` | 動態產生 root CA 與 leaf cert |
| `tokio` (rt-multi-thread) | hudsucker async runtime |
| `windows`（features：Win32 Security Cryptography / Win32 Networking WinInet / Win32 System Registry） | CertAddCertificateContextToStore、InternetSetOption、registry |
| `anyhow` | FRB 友善的錯誤型別 |
| `tracing` + `tracing-subscriber` | 日誌（PoC 期間 stdout） |

### 5.4 建置工具

- `flutter_rust_bridge_codegen generate` 產生 Dart binding
- Cargo 產出 `genshin_capture_core.dll`，由 FRB 的 build hook 自動 copy 到 `build/windows/x64/runner/<config>/`
- 需要 Rust toolchain（stable）+ MSVC build tools

## 6. Out of Scope（PoC 不做）

依 YAGNI 原則，這些先不做，等 PoC 跑通再依需求加：

| 項目 | 為什麼不做 |
|---|---|
| Android 端整套實作 | PoC 已決議只做 Windows |
| Domain 篩選 / 過濾 UI | 先看到所有 URL 流入即驗證攔得到，篩選是後續功能 |
| Request body 顯示 | UI 只列 URL；body 由 Rust 端讀到後 log 一次驗證可讀，不上傳 Dart |
| Response 攔截 | 卡池 API 主要是 GET URL 帶 authkey，PoC 只需驗 request |
| 持久化儲存 / DB | 列表只存 in-memory state，app 關掉就清空 |
| 多語系 i18n / 主題 | UI 元件直接寫繁中字串 |
| 卸載 CA / 移除按鈕 | CA 留著不影響使用者，未來再做 settings 頁 |
| 系統匣常駐 / 背景啟動 | 前景視窗執行就好 |
| 多筆 connection 並發壓力測試 | 確認流入順序 OK 即可，效能調校後續再做 |
| 單元測試 | 手動驗證為主，等架構穩定再補 |
| HTTPS 以外協定（h2c、QUIC、WebSocket） | hudsucker 預設處理 H1/H2 over TLS；原神 PC API 不走 QUIC |
| Process-specific proxy（只攔某 exe） | 全系統 proxy 最快驗證，影響面後續再縮 |

## 7. 手動驗收步驟

依序執行，全部通過代表 PoC 可行性驗證 PASS：

1. `flutter run -d windows` 啟動 app；看到 PocCapturePage 有「開始攔截」按鈕、空白列表
2. 點「開始攔截」：
   - 首次：Windows 跳一次「您要安裝此憑證嗎」確認框 → 點確認
   - 第二次以後：應**不再**跳憑證框（CA 已存在）
   - 按鈕文字變成「停止攔截」
3. 開瀏覽器打 `https://example.com` → 列表頂端立刻多一筆 `GET https://example.com/`
4. 開原神 → 進入卡池 → 點「歷史紀錄」→ 列表出現含 `getGachaLog` 與 `authkey=...` 的長 URL（**這一步是 PoC 真正的可行性核心**）
5. Rust 端 stdout log 應印出該 request 的 body 摘要（PoC 階段只驗有讀到，不上 UI）
6. 點「停止攔截」→ 開「Windows 設定 → 網路 → Proxy」確認手動 Proxy 已關 → 瀏覽器恢復正常上網

前 3 步先用 example.com 確認通路打通再去碰原神，能更快定位失敗原因。

## 8. 已知風險

| 風險 | 嚴重度 | 處理方式 |
|---|---|---|
| 原神客戶端走 HTTP/2 over TLS，hudsucker 需開 `with_http2()` | 中 | 建立 hudsucker server 時明確啟用 HTTP/2；驗收第 4 步同時驗證 |
| 首次 CA 安裝會跳 Windows 系統 dialog | 低（OS 行為） | PoC 接受此一次性提示；不需 admin |
| 原神 PC 客戶端若做 SSL pinning，攔不到 | 高（致命） | 第 4 步若失敗即代表此風險發生；視結果再評估 PC 端解 pinning 方案，或改走「讀本地遊戲日誌」備援路線 |
| 系統 proxy 影響其他 app 流量（PoC 期間使用者其他 app 都會走 127.0.0.1:18080） | 中 | PoC 接受；正式產品階段再考慮 process-specific 方案（WFP / WinDivert） |
| App 崩潰殘留 system proxy 設定，使用者上不了網 | 高 | 啟動時做 crash recovery（4.4 節）；Drop trait 雙保險 |
