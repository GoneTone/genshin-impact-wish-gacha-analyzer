# 修正 frb_expand unexpected_cfgs clippy lint

日期：2026-05-17
狀態：已核准，待寫實作計畫

## 背景

`cargo clippy --all-targets -- -D warnings` 在 `rust/` 失敗，因 3 個 `unexpected_cfgs` 警告（被 `-D warnings` 升為 error）：

- `rust/src/api/capture.rs:11` — `#[frb]`
- `rust/src/api/logging.rs:13` — `#[frb]`
- `rust/src/api/logging.rs:96` — `#[frb(ignore)]`

`flutter_rust_bridge`（pinned `=2.12.0`）的 `#[frb]` 屬性巨集展開時會產生 `#[cfg(frb_expand)]`。Rust 1.80+ 的 `unexpected_cfgs` lint 不認識 `frb_expand` 這個 cfg 名稱，故對每個 `#[frb]` 使用點發出警告。此狀況在 base `79e2b46` 即存在，與先前的 CA 憑證工作無關；`rust/Cargo.toml` 目前無 `[lints]` 區段，`rust/` 無 `build.rs`。

## 目標

`cargo clippy --all-targets -- -D warnings` 在 `rust/` 乾淨通過（exit 0），且不犧牲 lint 對其他真正未預期 cfg 的偵測能力。

## 決策

| 項目 | 決定 |
|---|---|
| 修法 | 採 flutter_rust_bridge 官方 troubleshooting 文件的標準解法：`rust/Cargo.toml` 加 `[lints.rust]` `unexpected_cfgs` 設定 |
| 精確度 | 用 `check-cfg = ['cfg(frb_expand)']` 只白名單 `frb_expand`，`level = "warn"` 保留 lint（非 blanket allow / 非全域關閉） |
| 範圍 | 只修 lint，不更動 CLAUDE.md 提交前檢查（YAGNI，依使用者決定） |

來源：flutter_rust_bridge 官方文件 `website/docs/manual/troubleshooting.md`「Warning: unexpected cfg condition name: frb_expand」。

## 設計

僅變更 `rust/Cargo.toml`，新增頂層 table：

```toml
[lints.rust]
unexpected_cfgs = { level = "warn", check-cfg = ['cfg(frb_expand)'] }
```

- `check-cfg = ['cfg(frb_expand)']`：將 `frb_expand` 宣告為已知 cfg，`#[frb]` 展開出的 `#[cfg(frb_expand)]` 不再觸發 `unexpected_cfgs`。
- `level = "warn"`：lint 仍對任何**其他**真正未預期的 cfg 名稱發出警告（保留偵測能力，非 `allow` 全域關閉）。
- `[lints]` table 需 Cargo 1.74+；本專案會觸發此 lint 代表使用 Rust 1.80+ 工具鏈，必然滿足。
- 純 manifest 設定，零程式碼與測試改動，不影響 Flutter/Dart 端與 FRB 橋接。

## 驗證

1. `cargo clippy --all-targets -- -D warnings`（工作目錄 `rust/`）→ exit 0，3 個 `frb_expand` error 消失，無新增警告。
2. `cargo fmt` → 無變更（manifest 不受 fmt 影響）。
3. `cargo test` → 仍 4/4 通過（`ca::tests` 3 項 + `cert_store::tests::remove_absent_cert_is_ok`）。

不新增測試：純設定變更，驗證標準即 clippy 閘通過。

## 範圍外（YAGNI）

- 不更動 CLAUDE.md「提交前品質檢查」（仍只列 Flutter 三項）。
- 不引入 `build.rs`（`[lints]` 已足夠，無需 build script）。
- 不調整 `flutter_rust_bridge` 版本或 codegen 設定。
