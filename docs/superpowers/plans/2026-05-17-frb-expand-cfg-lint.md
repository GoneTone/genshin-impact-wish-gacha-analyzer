# 修正 frb_expand unexpected_cfgs clippy lint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `cargo clippy --all-targets -- -D warnings` 在 `rust/` 乾淨通過，不再被 3 個 `frb_expand` lint 卡住。

**Architecture:** 純 manifest 設定變更——在 `rust/Cargo.toml` 加 flutter_rust_bridge 官方建議的 `[lints.rust]` `unexpected_cfgs` 設定，把 `frb_expand` 列為已知 cfg；保留 `level = "warn"` 不犧牲對其他未預期 cfg 的偵測。零程式碼/測試改動。

**Tech Stack:** Cargo manifest（`[lints]` table，Cargo 1.74+）、flutter_rust_bridge `=2.12.0`、Rust 1.80+ `unexpected_cfgs` lint。

**Spec:** `docs/superpowers/specs/2026-05-17-frb-expand-cfg-lint-design.md`

**注意（提交範圍）:** `docs/superpowers/` 在此 repo 的 `.gitignore` 內，不進版控。`git add` 只加 `rust/Cargo.toml`，不要 add 本 plan 或 spec。

---

## File Structure

- `rust/Cargo.toml` — 唯一變更檔。新增頂層 `[lints.rust]` table（與 `[dependencies]`、`[dev-dependencies]` 等同層級，非巢狀其下）。

無新建檔、無測試檔（純設定，驗證標準即 clippy 閘通過）。

---

### Task 1: 加入 frb_expand check-cfg lint 設定

**Files:**
- Modify: `rust/Cargo.toml`

- [ ] **Step 1: 確認問題重現**

工作目錄 `E:\IdeaProjects\genshin_impact_wish_gacha_analyzer\rust`，執行：

```
cargo clippy --all-targets -- -D warnings
```

Expected: 失敗（exit 101），輸出 3 個 `error: unexpected `cfg` condition name: `frb_expand``，位於 `src/api/capture.rs:11`、`src/api/logging.rs:13`、`src/api/logging.rs:96`。

- [ ] **Step 2: 加入 [lints.rust] 設定**

讀取 `rust/Cargo.toml` 確認目前無 `[lints]` 區段。在檔案**末尾**（最後一個現有 table 之後，與 `[dependencies]` 同為頂層 table，不可放在任何 `[target....]` 或 `[dependencies]` 之下）新增以下三行：

```toml

[lints.rust]
unexpected_cfgs = { level = "warn", check-cfg = ['cfg(frb_expand)'] }
```

（開頭保留一個空行與前一個 table 區隔。內容與 flutter_rust_bridge 官方 troubleshooting 文件一字不差。）

- [ ] **Step 3: 驗證 clippy 閘通過**

工作目錄 `rust/`，執行：

```
cargo clippy --all-targets -- -D warnings
```

Expected: 成功（exit 0），不再有任何 `frb_expand` 訊息，也無其他新增 warning/error。

若仍出現 `frb_expand`：確認 `[lints.rust]` 是頂層 table 且 `check-cfg` 字串為 `'cfg(frb_expand)'`（單引號、`cfg(...)` 包裹）。若出現 `unused manifest key: lints` 之類訊息，表示 Cargo 版本過舊（< 1.74）——回報 BLOCKED 並附 `cargo --version`。

- [ ] **Step 4: 驗證 fmt 與 test 未受影響**

工作目錄 `rust/`，依序執行：

```
cargo fmt
```
Expected: 無輸出、無檔案變更（`git -C E:\IdeaProjects\genshin_impact_wish_gacha_analyzer diff --stat` 只顯示 `rust/Cargo.toml`）。

```
cargo test
```
Expected: `test result: ok. 4 passed; 0 failed`（`ca::tests` 3 項 + `cert_store::tests::remove_absent_cert_is_ok`）。

- [ ] **Step 5: Commit**

```
git -C E:\IdeaProjects\genshin_impact_wish_gacha_analyzer add rust/Cargo.toml
git -C E:\IdeaProjects\genshin_impact_wish_gacha_analyzer commit -m "build(rust): declare frb_expand cfg to silence unexpected_cfgs lint

Official flutter_rust_bridge troubleshooting fix; keeps the lint at
warn level so other unexpected cfgs are still caught.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

不要傳入 `--no-verify` 或任何 `-c gpgsign` 旗標。`git add` 僅限 `rust/Cargo.toml`。

---

## Self-Review

- **Spec coverage:** spec §設計（加 `[lints.rust]`）→ Task 1 Step 2；§驗證 1/2/3（clippy/fmt/test）→ Step 3/4；§背景問題重現 → Step 1；§範圍外（不動 CLAUDE.md、不加 build.rs、不調 FRB 版本）→ plan 未觸及，符合。無遺漏。
- **Placeholder scan:** 無 TBD/TODO；所有步驟含確切指令、確切 toml 內容、確切預期輸出。
- **Type consistency:** 無程式碼型別；唯一 artifact 是固定 toml 字串，前後一致。
