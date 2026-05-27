# 撤回 getConfigList derive、改 hardcode gacha types 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 撤回上一 iteration 的 getConfigList URL derive（schema 欄位、Rust derive、UI 第二段顯示），改在 Dart 端建立一份 5 筆 hardcoded `GachaType` const list 給未來選單使用。

**Architecture:** 一個 atomic commit 同時做四件事：(1) `CapturedRequest` 移除 `config_list_url` 欄位；(2) `mitm.rs::handle_request` 命中分支移除 derive 與對應 log；(3) FRB codegen 同步；(4) `_HitCard.build` 回到單條 URL 樣貌（無小標題）；(5) 新增 `lib/data/gacha_types.dart`。Rust filter / drop 順序 / pending_stop 等核心邏輯**不動**。

**Tech Stack:** Rust（hudsucker handler / FRB v2 schema）、Flutter / Dart、`flutter_rust_bridge_codegen` CLI。

**Spec 來源:** `docs/superpowers/specs/2026-05-08-hardcode-gacha-types-design.md`

---

## 通用約定

- **PoC 階段不寫單元測試**（既有約定）
- **單一 commit 涵蓋撤舊 + 加新**（user 已選定 brainstorming 內的「直接修正到位」選項）
- **FRB codegen 必跑**（schema 縮欄）
- **不動 mitm filter（is_target）、Drop 順序、`fired`/`pending_stop` flag**

---

## 檔案結構（最終樣貌）

| 路徑 | 角色 | 任務 |
|---|---|---|
| `rust/src/api/capture.rs` | `CapturedRequest` 縮回 4 欄 | T1 |
| `rust/src/mitm.rs` | `handle_request` 命中分支移除 derive | T1 |
| `rust/src/frb_generated.rs` | FRB codegen 自動更新 | T1 |
| `lib/src/rust/api/capture.dart` | FRB codegen 自動更新 | T1 |
| `lib/src/rust/frb_generated.dart` | FRB codegen 自動更新 | T1 |
| `lib/pages/poc_capture_page.dart` | `_HitCard.build` 回到單條 URL（無小標題） | T1 |
| `lib/data/gacha_types.dart` | **新增**：`GachaType` class + `const gachaTypes` 5 筆 | T1 |

---

## Task 1：撤回 getConfigList derive，加入 hardcode gacha types

**Files:**
- Modify: `rust/src/api/capture.rs`
- Modify: `rust/src/mitm.rs`
- Generated: `rust/src/frb_generated.rs`、`lib/src/rust/api/capture.dart`、`lib/src/rust/frb_generated.dart`
- Modify: `lib/pages/poc_capture_page.dart`
- Create: `lib/data/gacha_types.dart`

- [ ] **Step 1.1：在 `rust/src/api/capture.rs` 把 `CapturedRequest` 縮回 4 欄**

把 struct 改成（移除 `config_list_url`）：

```rust
#[derive(Clone)]
#[frb]
pub struct CapturedRequest {
    pub method: String,
    pub url: String,
    pub host: String,
    pub timestamp_ms: i64,
}
```

不動其他 function（`start_capture` / `stop_capture` / `cleanup_stale_proxy` / `Session` struct / `SESSION` static / 既有註解）。

- [ ] **Step 1.2：在 `rust/src/mitm.rs::handle_request` 命中分支移除 derive 與對應 log**

把命中分支從目前的：

```rust
        let method = parts.method.to_string();
        let url = parts.uri.to_string();
        let host = parts.uri.host().unwrap_or("").to_string();
        let timestamp_ms = chrono::Utc::now().timestamp_millis();

        let config_list_url = url.replacen("/getGachaLog", "/getConfigList", 1);

        tracing::info!(target: "mitm", "hit getGachaLog: {} {}", method, url);
        tracing::info!(target: "mitm", "derived getConfigList: {}", config_list_url);

        let _ = self.sink.add(CapturedRequest {
            method,
            url,
            host,
            timestamp_ms,
            config_list_url,
        });

        // 暫不 spawn stop_capture：要等 response 從上游回來，避免 hudsucker 太早 shutdown 切斷 connection。
        self.pending_stop.store(true, Ordering::SeqCst);

        Request::from_parts(parts, body).into()
```

改回：

```rust
        let method = parts.method.to_string();
        let url = parts.uri.to_string();
        let host = parts.uri.host().unwrap_or("").to_string();
        let timestamp_ms = chrono::Utc::now().timestamp_millis();

        tracing::info!(target: "mitm", "hit getGachaLog: {} {}", method, url);

        let _ = self.sink.add(CapturedRequest {
            method,
            url,
            host,
            timestamp_ms,
        });

        // 暫不 spawn stop_capture：要等 response 從上游回來，避免 hudsucker 太早 shutdown 切斷 connection。
        self.pending_stop.store(true, Ordering::SeqCst);

        Request::from_parts(parts, body).into()
```

差異：刪除 `let config_list_url = ...` 行、`tracing::info!(... derived getConfigList ...)` log 行、struct 構造的 `config_list_url,` 行。

不動 handler struct、`fired` / `pending_stop`、`is_target`、`handle_response`、`start()`、imports。

- [ ] **Step 1.3：跑 FRB codegen**

Working directory: `E:\IdeaProjects\genshin_impact_wish_gacha_analyzer`

PowerShell：
```powershell
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"; flutter_rust_bridge_codegen generate
```

Expected：
- `lib/src/rust/api/capture.dart` 內 `CapturedRequest` 不再有 `configListUrl` 欄位（hashCode/equals 也同步移除）
- `lib/src/rust/frb_generated.dart` 與 `rust/src/frb_generated.rs` 同步更新（DCO arr 長度從 5 縮回 4、SSE 路徑減少一個 String encode/decode）
- 無 codegen 錯誤

- [ ] **Step 1.4：編譯 Rust**

```powershell
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"; cargo build --manifest-path rust/Cargo.toml
```

Expected：成功，唯一警告是既有 `unexpected_cfg` on `#[frb]`。

- [ ] **Step 1.5：改 `lib/pages/poc_capture_page.dart::_HitCard.build` 回單條 URL**

把 `_HitCard.build` 整個替換成：

```dart
@override
Widget build(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '✅ 已取得 getGachaLog URL，攔截已停止',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text('Method: ${captured.method}'),
            Text('Host: ${captured.host}'),
            const SizedBox(height: 8),
            SelectableText(
              captured.url,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    ),
  );
}
```

差異 vs 目前狀態：
- 移除 `getGachaLog URL` 與 `getConfigList URL` 兩個小標題（兩個 `Text(.., FontWeight.bold)` 行）
- 移除第二段 `SelectableText(captured.configListUrl, ...)` 
- 移除中間兩個 `SizedBox(height: 16)`
- 移除標籤與內容之間的 `SizedBox(height: 4)`
- Method/Host 與 URL 之間用 `SizedBox(height: 8)`（與綠色標題到 Method/Host 一致）

不動 `_PocCapturePageState`（state field、`_toggle`、`_buildBody`、`dispose` 與其上方註解）、`_WaitingIndicator`、imports。

- [ ] **Step 1.6：建立 `lib/data/gacha_types.dart`**

Write 整檔內容：

```dart
class GachaType {
  const GachaType({required this.gachaType, required this.name});

  /// 對應 getGachaLog API 的 query string `gacha_type=...`，String 型別跟 query 對齊。
  final String gachaType;

  /// UI 顯示用中文名稱。
  final String name;
}

// TODO: name 欄位後續 i18n 改用 translation key；目前 hardcode 中文。
const gachaTypes = <GachaType>[
  GachaType(gachaType: '301', name: '角色活動祈願'),
  GachaType(gachaType: '302', name: '武器活動祈願'),
  GachaType(gachaType: '500', name: '集錄祈願'),
  GachaType(gachaType: '200', name: '常駐祈願'),
  GachaType(gachaType: '100', name: '新手祈願'),
];
```

`lib/data/` 是新目錄；Write 工具會自動建立。

- [ ] **Step 1.7：靜態檢查 Dart**

```powershell
flutter analyze
```

Expected：我們的 .dart 檔零 issues（既有 cargokit 警告無關）。如果報 `configListUrl` undefined → Step 1.5 _HitCard 還沒清乾淨，回去檢查。如果報 `gacha_types.dart` 內語法錯 → 檢查 Step 1.6 內容。

- [ ] **Step 1.8：Commit**

```bash
git add rust/src/api/capture.rs rust/src/mitm.rs rust/src/frb_generated.rs lib/src/rust/ lib/pages/poc_capture_page.dart lib/data/gacha_types.dart
git commit -m "Drop getConfigList derive in favor of hardcoded gacha types"
```

---

## Task 2：手動驗收（spec §5）

**Files:** 無檔案變動。

- [ ] **Step 2.1：編譯確認**

依 spec §5 step 1：
- `cargo build`（在 `rust/`，PATH 含 cargo bin）→ 成功，唯一警告是既有 `unexpected_cfg`
- `flutter analyze` → 我們的 .dart 檔零 issues

- [ ] **Step 2.2：目視 UI 確認 _HitCard 回到單條 URL**

依 spec §5 step 2：
- `flutter run -d windows --release`
- 點「開始攔截」→ 等待提示
- 開原神 → 卡池 → 歷史紀錄 → `_HitCard` 應顯示：
  - 綠色標題「✅ 已取得 getGachaLog URL，攔截已停止」
  - `Method: GET`
  - `Host: public-operation-hk4e-sg.hoyoverse.com`（或實際 host）
  - 一條完整 URL（monospace SelectableText），**無**「getGachaLog URL」「getConfigList URL」小標題、**無**第二條 URL
- console 應只看到一行 `INFO mitm: hit getGachaLog: GET https://...`，**無** `derived getConfigList:` 行

- [ ] **Step 2.3：資料檔健全性**

依 spec §5 step 3：
- 讀 `lib/data/gacha_types.dart` 確認：
  - `class GachaType` 兩欄（`gachaType: String`、`name: String`）
  - 上方有 `// TODO: ... i18n ...` 註解
  - `const gachaTypes` 5 筆，gachaType 字串依序為 `301/302/500/200/100`，name 為「角色活動祈願/武器活動祈願/集錄祈願/常駐祈願/新手祈願」

- [ ] **Step 2.4：依結果決定下一步**

- 全部過 → iteration PASS
- step 2.2 看到 `getConfigList URL` 段或第二條 URL → T1 Step 1.5 沒清乾淨
- step 2.2 console 印 `derived getConfigList:` → T1 Step 1.2 沒清乾淨
- `flutter analyze` 報 `configListUrl` undefined → codegen 沒成功 / 沒 stage（檢查 T1 Step 1.3 與 1.8）
- step 2.3 中文錯字或順序錯 → 改 T1 Step 1.6 的 `gacha_types.dart` 並 amend commit

PoC 階段不需要 commit「驗收完成」這種無檔案變動的 placeholder commit。

---

## Self-Review

**Spec coverage：**

| Spec 章節 | 對應 Task |
|---|---|
| §3 新增資料檔 `lib/data/gacha_types.dart` | T1 Step 1.6 |
| §3 註解 `// TODO: i18n` | T1 Step 1.6 |
| §4 撤回 capture.rs 欄位 | T1 Step 1.1 |
| §4 撤回 mitm.rs derive | T1 Step 1.2 |
| §4 撤回 _HitCard 兩段 + 小標題 | T1 Step 1.5 |
| §4 FRB codegen 同步 | T1 Step 1.3 |
| §5 編譯驗收 | T2 Step 2.1 |
| §5 目視 UI 驗收 | T2 Step 2.2 |
| §5 資料定義健全性 | T2 Step 2.3 |
| §6 Out of Scope（i18n / 選單 UI / replay） | 計畫中無對應 task ✅ |
| §7 風險（i18n hardcode / 未來新 type） | T1 Step 1.6 已加 TODO 註解 |

無 spec 段落漏覆蓋。

**Placeholder 檢查：** 無 TBD/TODO（`// TODO: i18n` 是 spec 明確要求的註解內容，非 plan placeholder）；所有 code block 為可執行完整內容。

**型別/簽章一致性：**
- `CapturedRequest` 4 欄與既有上上 iteration（`af5637a` 之前）狀態一致 ✅
- `GachaType` class 與 `const gachaTypes` 命名與 spec §3 一致 ✅
- `lib/data/gacha_types.dart` 路徑與 spec §3 一致 ✅
- `_HitCard.build` 結構與 spec §4 「回到 iteration `e323fc2` 之前的樣貌」一致（單條 URL、無小標題、`SizedBox(height: 8)`）✅

審完無需修正。

---
