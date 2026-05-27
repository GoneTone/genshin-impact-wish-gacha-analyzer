# 推導並顯示 getConfigList URL 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 命中 `getGachaLog` 時，從同一條 URL 推導出 `getConfigList` URL（path 內 `/getGachaLog` → `/getConfigList`），透過 `CapturedRequest` 新增的 `config_list_url` 欄位推給 Dart，UI 在 `_HitCard` 內上下並列兩條 URL。

**Architecture:** Rust 端 `mitm.rs` 在 sink.add 之前對 url 字串做 `replace("/getGachaLog", "/getConfigList")` 推導，Rust schema `CapturedRequest` 加非 nullable `config_list_url: String` 欄位。FRB codegen 自動產生 Dart `configListUrl: String`。Dart `_HitCard` 多顯示一段 `SelectableText`。**不**新增任何 MITM 攔截規則。

**Tech Stack:** Rust（hudsucker handler / `flutter_rust_bridge` v2 schema）、Flutter / Dart、`flutter_rust_bridge_codegen` CLI。

**Spec 來源:** `docs/superpowers/specs/2026-05-08-config-list-url-derive-design.md`

---

## 通用約定

- **PoC 階段不寫單元測試**（既有約定；spec §7 已說明 derive 由手動驗收 step 7-bis 覆蓋）
- **每個 Task 結束做一個原子 commit**
- **FRB codegen 必跑**（schema 變更）
- **Drop 順序與 fired/pending_stop flag 邏輯不動**

---

## 檔案結構（最終樣貌）

| 路徑 | 角色 | 任務 |
|---|---|---|
| `rust/src/api/capture.rs` | `CapturedRequest` 加 `config_list_url` 欄位 | T1 |
| `rust/src/mitm.rs` | `handle_request` 命中後 derive + 加進 sink.add；多印一行 trace log | T1 |
| `lib/src/rust/**` | FRB codegen 自動產生 Dart binding（含新欄位） | T1（不手改） |
| `lib/pages/poc_capture_page.dart` | `_HitCard` 增加 getConfigList 段落（小標題 + SelectableText） | T2 |

---

## Task 1：Rust schema + derive + FRB codegen

**Files:**
- Modify: `rust/src/api/capture.rs`
- Modify: `rust/src/mitm.rs`
- Generated: `lib/src/rust/api/capture.dart`、`lib/src/rust/frb_generated.*`（不手改）

- [ ] **Step 1.1：在 `rust/src/api/capture.rs` 為 `CapturedRequest` 加 `config_list_url` 欄位**

把既有 struct 改成：

```rust
#[derive(Clone)]
#[frb]
pub struct CapturedRequest {
    pub method: String,
    pub url: String,
    pub host: String,
    pub timestamp_ms: i64,
    pub config_list_url: String,
}
```

不動其他 function（`start_capture` / `stop_capture` / `cleanup_stale_proxy` / `Session` struct / `SESSION` static 等）。

- [ ] **Step 1.2：在 `rust/src/mitm.rs::handle_request` 命中後段加 derive 並帶進 sink.add**

把命中分支從：

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
```

改成：

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

不改 handler 結構、`fired`/`pending_stop` flag、`handle_response` 或 `start()`。

- [ ] **Step 1.3：跑 FRB codegen**

Run（在 repo root，PowerShell）：
```powershell
flutter_rust_bridge_codegen generate
```

Expected：
- `lib/src/rust/api/capture.dart` 內 `CapturedRequest` 多一個 `configListUrl` 屬性
- 無 codegen 錯誤

如果 CLI 不在 PATH，先 `cargo install flutter_rust_bridge_codegen --version "^2"`（user 機器先前已裝過則 skip）。

- [ ] **Step 1.4：編譯 Rust**

Run（在 `rust/`）：
```powershell
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"; cargo build
```

Expected：編譯成功，唯一警告是既有 `unexpected_cfg` on `#[frb]`（非本任務引入）。

- [ ] **Step 1.5：靜態檢查 Dart**

Run（在 repo root）：
```powershell
flutter analyze
```

Expected：本 task 在 Dart 端不改 `_HitCard`（仍只用舊欄位），所以 analyze 對我們的 .dart 檔仍 0 issues；既有 cargokit-related 警告無關，可忽略。

- [ ] **Step 1.6：Commit**

```bash
git add rust/src/api/capture.rs rust/src/mitm.rs lib/src/rust/
git commit -m "Derive getConfigList URL alongside getGachaLog hit"
```

---

## Task 2：Dart `_HitCard` 顯示兩條 URL

**Files:**
- Modify: `lib/pages/poc_capture_page.dart`（只改 `_HitCard.build`）

- [ ] **Step 2.1：把 `_HitCard.build` 改成上下並列兩條 URL**

把既有 `_HitCard.build` 內 `Card` 整個替換成：

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
            const SizedBox(height: 16),
            const Text('getGachaLog URL', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SelectableText(
              captured.url,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            const Text('getConfigList URL', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SelectableText(
              captured.configListUrl,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    ),
  );
}
```

不改 `_PocCapturePageState` 內任何邏輯（state field、`_toggle`、`_buildBody`）；不改 `_WaitingIndicator`。

- [ ] **Step 2.2：靜態檢查**

Run: `flutter analyze`
Expected：本檔零 issue。`captured.configListUrl` 應對應 T1.3 codegen 產生的 Dart 端欄位。

如果 analyze 報 `configListUrl` undefined → 表示 T1.3 codegen 沒成功跑或 commit 漏 stage `lib/src/rust/`，回 T1 修正。

- [ ] **Step 2.3：Commit**

```bash
git add lib/pages/poc_capture_page.dart
git commit -m "Display derived getConfigList URL alongside getGachaLog in hit card"
```

---

## Task 3：手動驗收（spec §6）

**Files:** 無檔案變動。

- [ ] **Step 3.1：啟動 + 開始攔截 + 非命中流量**

依 spec §6 step 1-4：
- `flutter run -d windows --release` → 「尚未開始攔截」
- 點「開始攔截」→ 顯示等待提示
- 開瀏覽器打 `https://example.com` → UI 無變化
- 開瀏覽器打 `https://www.hoyoverse.com` → UI 無變化

- [ ] **Step 3.2：核心驗收 — 兩條 URL 都顯示**

開原神 → 卡池 → 歷史紀錄

Expected：
- UI 卡片顯示綠色「✅ 已取得 getGachaLog URL，攔截已停止」
- 「Method: GET」、「Host: public-operation-hk4e-sg.hoyoverse.com」（或實際 host）
- 「getGachaLog URL」小標題 + 完整 URL
- 「getConfigList URL」小標題 + 完整 URL（**path 部分 `/getConfigList`，其他完全相同**）
- console 看到兩行 log：
  ```
  INFO mitm: hit getGachaLog: GET https://...
  INFO mitm: derived getConfigList: https://...
  ```

- [ ] **Step 3.3：getConfigList URL 可用性驗證**

從 UI 複製 getConfigList URL（`SelectableText`）→ 貼到瀏覽器 → 應返回 JSON：

```json
{
  "retcode": 0,
  "message": "OK",
  "data": {
    "gacha_type_list": [
      { "id": "301", "key": "301", "name": "角色活動祈願" },
      ...
    ],
    "region": "os_asia",
    "region_time_zone": 8
  }
}
```

如果 retcode 非 0（如 -101 authkey timeout）→ 重新攔一次拿新 authkey。
如果 retcode 是某種「invalid params」→ Spec §8 風險「server 嚴格 reject 多餘 params」觸發，需要改 strip query 邏輯（回 T1 修 derive）。

- [ ] **Step 3.4：getGachaLog URL 仍正常**

從 UI 複製 getGachaLog URL → 貼瀏覽器 → 應返回 gacha log JSON（與上一 iteration 驗收 step 7 相同）。

- [ ] **Step 3.5：可重複攔截**

點「開始攔截」→ 卡片消失 → 再進原神卡池 → 兩條 URL 重新顯示。

- [ ] **Step 3.6：依結果決定下一步**

- 全部過 → iteration PASS
- step 3.3 拿到 JSON 但 `gacha_type_list` 為空 → server / authkey 問題，與本 iteration 無關
- step 3.3 retcode invalid params → 回 T1 改 derive 邏輯加 strip
- step 3.2 沒看到 「getConfigList URL」段 → 檢查 T2 是否漏改 `_HitCard.build`
- step 3.2 console 沒看到 derived log → 檢查 T1.2 是否漏加

PoC 階段不需要 commit「驗收完成」這種無檔案變動的 placeholder commit。

---

## Self-Review

**Spec coverage：**

| Spec 章節 | 對應 Task |
|---|---|
| §3 資料模型 `config_list_url` 欄位 | T1.1 |
| §4 Derive 邏輯（`/getGachaLog` → `/getConfigList`） | T1.2 |
| §4 加 tracing log | T1.2 |
| §5 UI 上下並列兩條 URL（小標題、SelectableText） | T2.1 |
| §6 step 1-4 (基本攔截) | T3.1 |
| §6 step 5 (兩條 URL 顯示 + 兩行 log) | T3.2 |
| §6 step 7 / 7-bis (URL 可用性) | T3.3 / T3.4 |
| §6 step 8 (可重複攔截) | T3.5 |
| §7 Out of Scope | 計畫中無對應 task ✅ |
| §8 風險「server 嚴格 reject 多餘 params」 | T3.3 觸發點已標 |
| §8 風險「FRB codegen 必跑」 | T1.3 |

無 spec 段落漏覆蓋。

**Placeholder 檢查：** 無 TBD/TODO；所有 code block 是可執行完整內容；唯一條件性指引（codegen CLI 沒裝 / strip param）都明確標出觸發條件。

**型別/簽章一致性：**
- `config_list_url: String`（Rust）↔ `configListUrl: String`（Dart，FRB camelCase）一致 ✅
- `CapturedRequest` 5 欄與 spec §3 一致 ✅
- `_HitCard.captured.configListUrl` 用法與 codegen 產出一致 ✅
- 無 trait/method 簽章變更（capture.rs 公開 API 完全不變）✅

審完無需修正。

---
