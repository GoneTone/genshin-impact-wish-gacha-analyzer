# Rust log 跨橋脫敏設計

日期：2026-05-18
狀態：設計完成，待實作

## 問題

Flutter 端業務 log 透過 `sanitizeUrl()` / `sanitizeUid()` / `sanitizeFsPath()` 脫敏，
但 Rust 端 `rust/src/mitm.rs:75`：

```rust
tracing::info!(target: "mitm", "hit gacha endpoint: {} {}", method, url);
```

`url` 為完整原始 URL，含明文 `authkey`（等同可讀取整個祈願紀錄的憑證）。該訊息經
`ForwardLayer`（`rust/src/api/logging.rs`）跨橋傳到 Dart，再由 `lib/main.dart` 的
listener 寫進與 Flutter 共用的同一份 log 檔。使用者匯出 log 給人除錯即外洩 authkey。

掃過其餘 Rust `tracing` 呼叫（`ca` / `cert_store` / `panic` / `mitm` 其他行），
目前僅此一行會洩漏敏感資料；但 Dart 端統一處理可一併涵蓋未來新增。

## 方案決策

| | A. 移植 `sanitize_url` 到 Rust | B. Dart 端統一脫敏（採用） |
|---|---|---|
| 重複造輪子 | redact 清單跨語言兩份，需防漂移 | 零重複，沿用既有已測試的 `sanitizeUrl()` |
| 未來防護 | 只修這一行 | 任何 Rust target/行輸出 URL 都自動脫敏 |
| CLAUDE.md | 違反「嚴禁重複造輪子」 | 符合 |
| 代價 | 跨 FFI 維護兩份邏輯 | 需從自由文字訊息抽出 URL 子字串再脫敏 |

採用 **B**：所有 Rust log 跨橋進 Dart 時，在單一匣道（`lib/main.dart` listener）
統一脫敏，沿用既有 `sanitizeUrl()`，不在 Rust 端複製邏輯。

## 改動

### 1. `lib/services/log_sanitize.dart` — 新增 helper

```dart
/// 掃描自由文字訊息中內嵌的 http(s) URL,逐一套 sanitizeUrl 後原位替換。
/// 非 URL 內容原樣保留。Rust log 跨橋進 Dart 時統一呼叫,單一脫敏來源。
String sanitizeLogMessage(String message);
```

- 以 `RegExp(r'https?://\S+')` 找出每段 URL token（log 訊息中 URL 皆為末段或後接
  空白，`\S+` 邊界足夠）。
- 每段丟進**既有的** `sanitizeUrl()`，原位 splice 回原訊息。
- 無 URL 的訊息原樣返回。
- 不改動現有 `sanitizeUrl` / `sanitizeUid` / `sanitizeFsPath`。

### 2. `lib/main.dart` — rust log listener 改用匣道

`_connectRustLogStream()` 內，原：

```dart
Logger('rust.${event.target}').log(_levelFromRust(event.level), event.message);
```

改為：

```dart
Logger(
  'rust.${event.target}',
).log(_levelFromRust(event.level), sanitizeLogMessage(event.message));
```

單一脫敏匣道，自動涵蓋所有現有與未來 Rust target。

### 3. `test/services/log_sanitize_test.dart` — 新增測試群組

`sanitizeLogMessage` 案例至少涵蓋：

- 真實 `hit gacha endpoint: GET https://...&authkey=<long>&sign_type=2&game_biz=hk4e_global&...`
  → `authkey` / `authkey_ver` / `sign_type` / `game_biz` 變 `***`，其餘 query
  （`gacha_type`、`region`、`lang`、`game_version`、`page`、`size` 等）保留。
- 無 URL 的訊息（如 `capture started`）→ 原樣返回。
- URL 後接其他欄位（`url=https://...?x=1 status=200`）→ 只脫敏 URL 段，
  `status=200` 保留。
- malformed URL token → 沿用 `sanitizeUrl` 的 `<malformed url>` 行為。

## 不做（YAGNI / 已裁決）

- 不移植 sanitize 邏輯到 Rust（避免跨語言重複，符合 CLAUDE.md）。
- 不改 `rust/src/mitm.rs:75`（Rust 端維持原樣，脫敏完全在 Dart 匣道做）。
- dev `cargo run` stdout `fmt::layer()` 仍印原始 authkey（不走跨橋路徑）——
  已知限制，不處理：開發者本機、瞬間性、非使用者匯出的 log 檔。

## 驗證

提交前依序通過：

1. `dart format lib/ test/`
2. `flutter analyze` → `No issues found!`
3. `flutter test` → `All tests passed!`

預期 log 檔結果：

```
[rust.mitm] hit gacha endpoint: GET https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog?...&authkey=***&sign_type=***&game_biz=***&gacha_type=301&region=os_asia&...
```

與 Flutter 端 `wish.capture` 完全一致的脫敏規則。
